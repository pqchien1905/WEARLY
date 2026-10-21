import { Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { recordAdminActivity } from '../admin/audit';
import { queueOrderMail } from '../mail/outbox';
import { cancelOrder } from '../orders/cancel-order';
import { adminOrderInclude } from '../orders/order-includes';
import {
  AdminCancelDto,
  CreateReturnDto,
  DecideReturnDto,
  QuoteReturnDto,
  ReceiveReturnDto,
} from './returns.dto';
import { quoteReturn } from './return-money';
const include = {
  items: true,
  payment: true,
  history: { orderBy: { version: 'desc' as const } },
  returns: {
    include: { items: true },
    orderBy: [{ createdAt: 'desc' as const }, { id: 'desc' as const }],
  },
};
type ReturnOrder = Prisma.OrderGetPayload<{ include: typeof include }>;
type Case = ReturnOrder['returns'][number];
const publicCase = (row: Case) => ({
  id: row.id,
  orderId: row.orderId,
  reason: row.reason,
  status: row.status,
  amount: row.amount,
  version: row.version,
  decisionNote: row.decisionNote,
  decidedAt: row.decidedAt,
  receiptNote: row.receiptNote,
  receivedAt: row.receivedAt,
  createdAt: row.createdAt,
  items: row.items.map((i) => ({
    orderItemId: i.orderItemId,
    quantity: i.quantity,
    amount: i.amount,
  })),
});
function received(order: ReturnOrder) {
  const quantities: Record<string, number> = {};
  for (const request of order.returns.filter((r) => r.status === 'RECEIVED'))
    for (const item of request.items)
      quantities[item.orderItemId] =
        (quantities[item.orderItemId] ?? 0) + item.quantity;
  return quantities;
}
function eligibility(order: ReturnOrder) {
  const delivery = order.history.find((e) => e.status === 'DELIVERED'),
    quantities = received(order),
    deadline = delivery
      ? new Date(delivery.createdAt.getTime() + 7 * 86400000)
      : null;
  const reason =
    order.status === 'RETURNED' &&
    order.items.every((i) => (quantities[i.id] ?? 0) >= i.quantity)
      ? 'NOTHING_LEFT'
      : order.status !== 'DELIVERED'
        ? 'NOT_DELIVERED'
        : !['PAID', 'PARTIALLY_REFUNDED'].includes(order.payment?.status ?? '')
          ? 'PAYMENT_NOT_SETTLED'
          : !deadline
            ? 'DELIVERY_DATE_UNKNOWN'
            : deadline.getTime() <= Date.now()
              ? 'WINDOW_EXPIRED'
              : order.returns.some((r) =>
                    ['REQUESTED', 'APPROVED'].includes(r.status),
                  )
                ? 'OPEN_RETURN'
                : order.items.every(
                      (i) => (quantities[i.id] ?? 0) >= i.quantity,
                    )
                  ? 'NOTHING_LEFT'
                  : 'AVAILABLE';
  return {
    canRequest: reason === 'AVAILABLE',
    reason,
    deadline,
    items: order.items.map((i) => ({
      orderItemId: i.id,
      remaining: i.quantity - (quantities[i.id] ?? 0),
    })),
  };
}
@Injectable()
export class ReturnsService {
  constructor(private readonly db: PrismaService) {}
  private async order(
    tx: Prisma.TransactionClient,
    id: string,
    userId?: string,
  ) {
    if (userId)
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid AND "userId"=${userId}::uuid FOR UPDATE`;
    else
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid FOR UPDATE`;
    const order = await tx.order.findFirst({
      where: { id, ...(userId ? { userId } : {}) },
      include,
    });
    if (!order) throw new NotFoundException();
    return order;
  }
  state(userId: string, id: string) {
    return transaction(this.db, async (tx) => {
      const order = await this.order(tx, id, userId);
      return {
        eligibility: eligibility(order),
        requests: order.returns.map(publicCase),
      };
    });
  }
  private quote(order: ReturnOrder, dto: QuoteReturnDto) {
    const rules = eligibility(order);
    if (!rules.canRequest)
      fail(409, 'RETURN_' + rules.reason, 'Return is not currently eligible');
    try {
      return quoteReturn(
        order.items.map((i) => ({ ...i, unitPrice: i.unitPrice.toString() })),
        order.discount.toString(),
        received(order),
        dto.items,
      );
    } catch {
      fail(
        400,
        'RETURN_INVALID_ITEMS',
        'Return quantities must belong to this order and remain available',
      );
    }
  }
  preview(userId: string, id: string, dto: QuoteReturnDto) {
    return transaction(this.db, async (tx) =>
      this.quote(await this.order(tx, id, userId), dto),
    );
  }
  create(userId: string, id: string, dto: CreateReturnDto) {
    const requestHash = createHash('sha256')
      .update(
        JSON.stringify({
          reason: dto.reason,
          ...(dto.expectedAmount === undefined
            ? {}
            : { expectedAmount: dto.expectedAmount }),
          items: [...dto.items]
            .sort((a, b) => a.orderItemId.localeCompare(b.orderItemId))
            .map((i) => ({ orderItemId: i.orderItemId, quantity: i.quantity })),
        }),
      )
      .digest('hex');
    return transaction(this.db, async (tx) => {
      const order = await this.order(tx, id, userId),
        previous = order.returns.find((r) => r.requestKey === dto.requestKey);
      if (previous) {
        if (previous.requestHash !== requestHash)
          fail(
            409,
            'IDEMPOTENCY_CONFLICT',
            'Return request key was reused with different data',
          );
        return publicCase(previous);
      }
      const quote = this.quote(order, dto);
      if (
        dto.expectedAmount !== undefined &&
        quote.amount !== dto.expectedAmount
      )
        fail(
          409,
          'RETURN_QUOTE_CHANGED',
          'Return entitlement changed; preview again',
        );
      const saved = await tx.returnRequest.create({
        data: {
          orderId: id,
          requestKey: dto.requestKey,
          requestHash,
          reason: dto.reason,
          amount: quote.amount,
          items: { create: quote.items },
        },
        include: { items: true },
      });
      await tx.order.update({
        where: { id },
        data: { version: { increment: 1 } },
      });
      return publicCase(saved);
    });
  }
  decide(actorId: string, id: string, returnId: string, dto: DecideReturnDto) {
    return transaction(this.db, async (tx) => {
      const order = await this.order(tx, id),
        request = order.returns.find((r) => r.id === returnId);
      if (!request) throw new NotFoundException();
      if (
        request.status !== 'REQUESTED' ||
        request.version !== dto.expectedVersion
      )
        fail(
          409,
          'RETURN_STATE_CONFLICT',
          'Return changed; reload before deciding',
        );
      const saved = await tx.returnRequest.update({
        where: { id: returnId },
        data: {
          status: dto.status,
          decisionNote: dto.note,
          decidedBy: actorId,
          decidedAt: new Date(),
          version: { increment: 1 },
        },
        include: { items: true },
      });
      await tx.order.update({
        where: { id },
        data: { version: { increment: 1 } },
      });
      await recordAdminActivity(tx, actorId, 'RETURN_DECIDED', id);
      await queueOrderMail(
        tx,
        id,
        `return:${returnId}:decision`,
        'Kết quả yêu cầu trả hàng',
        `Yêu cầu ${returnId}: ${dto.status === 'APPROVED' ? 'đã được chấp nhận' : 'đã bị từ chối'}.\n${dto.note}`,
      );
      return saved;
    });
  }
  receive(
    actorId: string,
    id: string,
    returnId: string,
    dto: ReceiveReturnDto,
  ) {
    return transaction(this.db, async (tx) => {
      const order = await this.order(tx, id),
        request = order.returns.find((r) => r.id === returnId);
      if (!request) throw new NotFoundException();
      if (request.status === 'RECEIVED') {
        if (request.receiptNote !== dto.note)
          fail(409, 'RETURN_RECEIPT_CONFLICT', 'Receipt was already recorded');
        return request;
      }
      if (
        order.status !== 'DELIVERED' ||
        request.status !== 'APPROVED' ||
        request.version !== dto.expectedVersion
      )
        fail(
          409,
          'RETURN_STATE_CONFLICT',
          'Approve the current return before receiving',
        );
      for (const item of [...request.items].sort((a, b) =>
        a.orderItemId.localeCompare(b.orderItemId),
      )) {
        const sold = order.items.find((i) => i.id === item.orderItemId)!;
        const inv = await tx.inventory.update({
          where: { variantId: sold.variantId },
          data: {
            quantity: { increment: item.quantity },
            version: { increment: 1 },
          },
        });
        await tx.inventoryMovement.create({
          data: {
            inventoryId: inv.id,
            orderId: id,
            delta: item.quantity,
            reason: 'CUSTOMER_RETURN',
          },
        });
      }
      const saved = await tx.returnRequest.update({
        where: { id: returnId },
        data: {
          status: 'RECEIVED',
          receiptNote: dto.note,
          receivedBy: actorId,
          receivedAt: new Date(),
          version: { increment: 1 },
        },
        include: { items: true },
      });
      const quantities = received({
          ...order,
          returns: order.returns.map((r) => (r.id === returnId ? saved : r)),
        }),
        all = order.items.every((i) => quantities[i.id] === i.quantity);
      await tx.order.update({
        where: { id },
        data: {
          version: { increment: 1 },
          ...(all ? { status: 'RETURNED' } : {}),
        },
      });
      if (all)
        await tx.orderEvent.create({
          data: {
            orderId: id,
            status: 'RETURNED',
            version: order.version + 1,
            actorId,
            note: 'Đã nhận lại toàn bộ hàng khách trả',
          },
        });
      await recordAdminActivity(tx, actorId, 'RETURN_RECEIVED', id);
      await queueOrderMail(
        tx,
        id,
        `return:${returnId}:received`,
        'Đã nhận hàng khách trả',
        `Đã nhận hàng của yêu cầu ${returnId}. Hoàn tiền được xác nhận riêng.`,
      );
      return saved;
    });
  }
  cancel(actorId: string, id: string, dto: AdminCancelDto) {
    return transaction(this.db, async (tx) => {
      const order = await this.order(tx, id);
      if (order.status === 'CANCELLED') {
        if (
          order.history.find((h) => h.status === 'CANCELLED')?.note !==
          dto.reason
        )
          fail(409, 'CANCELLATION_CONFLICT', 'Order was already cancelled');
        return tx.order.findUniqueOrThrow({
          where: { id },
          include: adminOrderInclude,
        });
      }
      if (
        !['PENDING', 'CONFIRMED'].includes(order.status) ||
        order.version !== dto.expectedVersion
      )
        fail(
          409,
          'ORDER_STATE_CONFLICT',
          'Only current pre-dispatch orders can be cancelled',
        );
      await cancelOrder(tx, order, actorId, dto.reason);
      await recordAdminActivity(tx, actorId, 'ORDER_CANCELLED', id);
      return tx.order.findUniqueOrThrow({
        where: { id },
        include: adminOrderInclude,
      });
    });
  }
}
