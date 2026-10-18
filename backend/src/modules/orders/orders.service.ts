import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import { PrismaService } from '../../database/prisma.service';
import { transaction, lockUser } from '../../common/transaction';
import { shippingFee, totalForItems } from '../../common/money';
import { fail } from '../../common/errors';
import { cartInclude } from '../cart/cart.service';
import { CreateOrderDto } from './dto/order.dto';
import { PageDto } from '../products/dto/query-products.dto';
const include = { items: true, payment: true };
@Injectable()
export class OrdersService {
  constructor(private readonly db: PrismaService) {}
  create(userId: string, key: string | undefined, dto: CreateOrderDto) {
    if (!key || !/^[a-zA-Z0-9_-]{8,128}$/.test(key))
      throw new BadRequestException(
        'Idempotency-Key (8–128 letters, numbers, underscores or hyphens) is required',
      );
    const requestHash = createHash('sha256')
      .update(
        JSON.stringify({
          addressId: dto.addressId,
          shippingMethod: dto.shippingMethod,
          expectedSubtotal: dto.expectedSubtotal,
          cartVersion: dto.cartVersion ?? null,
        }),
      )
      .digest('hex');
    return transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      const previous = await tx.order.findUnique({
        where: { userId_idempotencyKey: { userId, idempotencyKey: key } },
        include,
      });
      if (previous) {
        if (previous.requestHash !== requestHash)
          fail(
            409,
            'IDEMPOTENCY_CONFLICT',
            'This key belongs to a different request',
          );
        return previous;
      }
      const address = await tx.address.findFirst({
        where: { id: dto.addressId, userId },
      });
      if (!address) throw new NotFoundException('Address not found');
      const cart = await tx.cart.findUnique({
        where: { userId },
        include: cartInclude,
      });
      if (!cart?.items.length) throw new BadRequestException('Cart is empty');
      if (dto.cartVersion !== undefined && dto.cartVersion !== cart.version)
        fail(409, 'VERSION_CONFLICT', 'Cart changed; refresh before ordering');
      const subtotal = totalForItems(
        cart.items.map((i) => ({
          price: i.variant.price,
          quantity: i.quantity,
        })),
      );
      if (!subtotal.eq(dto.expectedSubtotal))
        fail(409, 'PRICE_CHANGED', 'Prices changed; refresh your cart');
      const shipping = shippingFee(subtotal, dto.shippingMethod);
      if (subtotal.plus(shipping).gt('99999999999999')) {
        fail(
          400,
          'ORDER_TOTAL_TOO_LARGE',
          'Order total exceeds the supported amount',
        );
      }
      // Deterministic order reduces deadlocks across carts with multiple SKUs.
      for (const item of [...cart.items].sort((a, b) =>
        a.variantId.localeCompare(b.variantId),
      )) {
        if (!item.variant.active || !item.variant.product.active)
          fail(409, 'STOCK_CHANGED', 'SKU is no longer available');
        const result = await tx.inventory.updateMany({
          where: {
            variantId: item.variantId,
            quantity: { gte: item.quantity },
          },
          data: {
            quantity: { decrement: item.quantity },
            version: { increment: 1 },
          },
        });
        if (result.count !== 1)
          fail(409, 'STOCK_CHANGED', 'Insufficient stock');
      }
      const order = await tx.order.create({
        data: {
          userId,
          idempotencyKey: key,
          requestHash,
          addressSnapshot: {
            recipient: address.recipient,
            phone: address.phone,
            address: address.address,
          },
          subtotal,
          shipping,
          total: subtotal.plus(shipping),
          items: {
            create: cart.items.map((i) => ({
              variantId: i.variantId,
              name: i.variant.product.name,
              sku: i.variant.sku,
              slug: i.variant.product.slug,
              size: i.variant.size,
              color: i.variant.color,
              image: i.variant.product.images[0]?.url ?? '',
              unitPrice: i.variant.price,
              quantity: i.quantity,
            })),
          },
          payment: {
            create: { provider: 'cod', amount: subtotal.plus(shipping) },
          },
        },
        include,
      });
      for (const item of cart.items)
        await tx.inventoryMovement.create({
          data: {
            inventoryId: item.variant.inventory!.id,
            delta: -item.quantity,
            reason: 'ORDER',
            orderId: order.id,
          },
        });
      await tx.cartItem.deleteMany({ where: { cartId: cart.id } });
      await tx.cart.update({
        where: { id: cart.id },
        data: { version: { increment: 1 } },
      });
      return order;
    });
  }
  async list(userId: string, q: PageDto) {
    const [items, total] = await this.db.$transaction([
      this.db.order.findMany({
        where: { userId },
        include,
        orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
        skip: (q.page - 1) * q.limit,
        take: q.limit,
      }),
      this.db.order.count({ where: { userId } }),
    ]);
    return { items, total, page: q.page, limit: q.limit };
  }
  async get(userId: string, id: string) {
    const order = await this.db.order.findFirst({
      where: { id, userId },
      include,
    });
    if (!order) throw new NotFoundException();
    return order;
  }
  cancel(userId: string, id: string) {
    return transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      const order = await tx.order.findFirst({
        where: { id, userId },
        include,
      });
      if (!order) throw new NotFoundException();
      if (order.status === 'CANCELLED') return order;
      if (order.status !== 'PENDING')
        fail(
          409,
          'ORDER_STATE_CONFLICT',
          'Only pending orders can be cancelled',
        );
      const changed = await tx.order.updateMany({
        where: { id, userId, status: 'PENDING', version: order.version },
        data: { status: 'CANCELLED', version: { increment: 1 } },
      });
      if (changed.count !== 1) fail(409, 'VERSION_CONFLICT', 'Order changed');
      for (const item of [...order.items].sort((a, b) =>
        a.variantId.localeCompare(b.variantId),
      )) {
        const inv = await tx.inventory.update({
          where: { variantId: item.variantId },
          data: {
            quantity: { increment: item.quantity },
            version: { increment: 1 },
          },
        });
        await tx.inventoryMovement.create({
          data: {
            inventoryId: inv.id,
            delta: item.quantity,
            reason: 'CANCEL',
            orderId: id,
          },
        });
      }
      await tx.payment.update({
        where: { orderId: id },
        data: { status: 'CANCELLED' },
      });
      return tx.order.findUniqueOrThrow({ where: { id }, include });
    });
  }
}
