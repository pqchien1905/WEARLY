import { Prisma } from '../../generated/prisma/client';
import { fail } from '../../common/errors';
import { queueOrderStatus } from '../mail/outbox';
type Order = Prisma.OrderGetPayload<{
  include: { items: true; payment: true };
}>;
/** Caller owns the order lock and authorizes the allowed state before entering. */
export async function cancelOrder(
  tx: Prisma.TransactionClient,
  order: Order,
  actorId: string,
  note: string,
) {
  if (
    order.payment?.provider === 'vnpay' &&
    (await tx.paymentAttempt.count({
      where: { paymentId: order.payment.id, status: 'PENDING' },
    }))
  )
    fail(
      409,
      'PAYMENT_RECONCILIATION_REQUIRED',
      'Verify pending payment before cancelling',
    );
  await tx.order.update({
    where: { id: order.id },
    data: { status: 'CANCELLED', version: { increment: 1 } },
  });
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
        orderId: order.id,
      },
    });
  }
  // Collected funds remain recorded until a separate verified refund is completed.
  if (
    order.payment &&
    (order.payment.amount.eq(0) ||
      !['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED'].includes(
        order.payment.status,
      ))
  )
    await tx.payment.update({
      where: { id: order.payment.id },
      data: { status: 'CANCELLED' },
    });
  await tx.couponRedemption.updateMany({
    where: { orderId: order.id, releasedAt: null },
    data: { releasedAt: new Date() },
  });
  await tx.orderEvent.create({
    data: {
      orderId: order.id,
      status: 'CANCELLED',
      version: order.version + 1,
      actorId,
      note,
    },
  });
  await queueOrderStatus(tx, order.id, 'CANCELLED', order.version + 1);
}
