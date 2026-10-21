export type RefundPolicyOrder = {
  status: string;
  shipmentStatus: string | null;
  receivedAmount: string;
  payment: {
    provider: string;
    status: string;
    amount: string;
    transactionNo: string | null;
    settled: boolean;
  } | null;
  attempts: {
    id: string;
    status: string;
    transactionNo: string | null;
    amount: string;
  }[];
  refunds: { attemptId: string | null; amount: string; status: string }[];
};
function vnd(value: string) {
  if (!/^(0|[1-9]\d{0,13})$/.test(value))
    throw new Error('Invalid refund money');
  return BigInt(value);
}
export function refundSources(order: RefundPolicyOrder) {
  const p = order.payment;
  if (!p || vnd(p.amount) === 0n) return [];
  const paid = ['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED'].includes(p.status);
  if (!paid) return [];
  const received = vnd(order.receivedAmount),
    total = vnd(p.amount);
  if (received > total)
    throw new Error('Return entitlement exceeds collection');
  const entitlement =
    order.status === 'CANCELLED' || order.shipmentStatus === 'RETURNED'
      ? total
      : received;
  const sources =
    p.provider === 'cod' && p.settled
      ? [{ id: null, amount: p.amount, primary: true }]
      : p.provider === 'vnpay' &&
          p.transactionNo &&
          order.attempts.some(
            (a) => a.transactionNo === p.transactionNo && a.status === 'PAID',
          )
        ? order.attempts
            .filter((a) => a.status === 'PAID' && a.transactionNo)
            .map((a) => ({
              id: a.id,
              amount: a.amount,
              primary: a.transactionNo === p.transactionNo,
            }))
        : [];
  return sources
    .filter(
      (source) =>
        !(
          source.primary &&
          p.status === 'REFUNDED' &&
          !order.refunds.some(
            (r) => r.attemptId === source.id && r.status === 'SUCCEEDED',
          )
        ),
    )
    .map((source) => {
      const collected = vnd(source.amount),
        entitled = source.primary ? entitlement : collected;
      let refunded = 0n,
        reserved = 0n;
      for (const row of order.refunds.filter(
        (r) => r.attemptId === source.id,
      )) {
        const amount = vnd(row.amount);
        if (row.status !== 'FAILED') reserved += amount;
        if (row.status === 'SUCCEEDED') refunded += amount;
      }
      if (reserved > entitled || entitled > collected)
        throw new Error('Refund ledger exceeds entitlement');
      return {
        attemptId: source.id,
        primary: source.primary,
        collected: collected.toString(),
        entitled: entitled.toString(),
        refunded: refunded.toString(),
        reserved: reserved.toString(),
        available: (entitled - reserved).toString(),
      };
    });
}
