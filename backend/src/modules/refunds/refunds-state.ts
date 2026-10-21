import { Prisma } from '../../generated/prisma/client';
import { refundSources } from './refund-policy';
export const refundOrderInclude = {
  payment: {
    include: {
      settlement: true,
      attempts: true,
      refunds: {
        orderBy: [{ createdAt: 'desc' as const }, { id: 'desc' as const }],
      },
    },
  },
  returns: { where: { status: 'RECEIVED' as const }, select: { amount: true } },
  shipment: { select: { status: true } },
};
export type RefundOrder = Prisma.OrderGetPayload<{
  include: typeof refundOrderInclude;
}>;
export type RefundRow = NonNullable<RefundOrder['payment']>['refunds'][number];
export function sources(order: RefundOrder) {
  const p = order.payment;
  return refundSources({
    status: order.status,
    shipmentStatus: order.shipment?.status ?? null,
    receivedAmount: order.returns
      .reduce((s, r) => s + BigInt(r.amount.toFixed(0)), 0n)
      .toString(),
    payment: p
      ? {
          provider: p.provider,
          status: p.status,
          amount: p.amount.toFixed(0),
          transactionNo: p.providerTransactionId,
          settled: !!p.settlement,
        }
      : null,
    attempts:
      p?.attempts.map((a) => ({ ...a, amount: a.amount.toFixed(0) })) ?? [],
    refunds:
      p?.refunds.map((r) => ({ ...r, amount: r.amount.toFixed(0) })) ?? [],
  });
}
export function publicRefund(row: RefundRow, admin = false) {
  return {
    id: row.id,
    amount: row.amount,
    status: row.status,
    reference: row.reference,
    providerTransactionNo: row.providerTransactionNo,
    createdAt: row.createdAt,
    completedAt: row.completedAt,
    provider: row.attemptId ? 'vnpay' : 'cod',
    ...(admin
      ? {
          attemptId: row.attemptId,
          primary: row.primary,
          providerRequestId: row.providerRequestId,
        }
      : {}),
  };
}
export function refundState(order: RefundOrder, admin: boolean) {
  const rows = order.payment?.refunds ?? [];
  return {
    orderId: order.id,
    version: order.version,
    provider: order.payment?.provider ?? null,
    paymentStatus: order.payment?.status ?? null,
    refunded: rows
      .filter((r) => r.status === 'SUCCEEDED')
      .reduce((s, r) => s + BigInt(r.amount.toFixed(0)), 0n)
      .toString(),
    refunds: rows.map((r) => publicRefund(r, admin)),
    ...(admin
      ? {
          sources: sources(order).map((s) => ({
            ...s,
            pending: rows.some(
              (r) =>
                r.attemptId === s.attemptId &&
                ['REVIEW', 'PROCESSING'].includes(r.status),
            ),
          })),
        }
      : {}),
  };
}
