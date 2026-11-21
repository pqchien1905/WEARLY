import {
  refundSources,
  RefundPolicyOrder,
} from '../src/modules/refunds/refund-policy';

function order(patch: Partial<RefundPolicyOrder> = {}): RefundPolicyOrder {
  return {
    status: 'DELIVERED',
    shipmentStatus: 'DELIVERED',
    receivedAmount: '465000',
    payment: {
      provider: 'cod',
      status: 'PAID',
      amount: '960000',
      transactionNo: null,
      settled: true,
    },
    attempts: [],
    refunds: [],
    ...patch,
  };
}
describe('refund entitlement by collected source', () => {
  it('reserves unknown outcomes and returns only the remaining exact merchandise entitlement', () => {
    const input = order({
      refunds: [
        { attemptId: null, amount: '1', status: 'SUCCEEDED' },
        { attemptId: null, amount: '2', status: 'REVIEW' },
        { attemptId: null, amount: '3', status: 'PROCESSING' },
        { attemptId: null, amount: '100', status: 'FAILED' },
      ],
    });
    expect(refundSources(input)).toEqual([
      {
        attemptId: null,
        primary: true,
        collected: '960000',
        entitled: '465000',
        refunded: '1',
        reserved: '6',
        available: '464994',
      },
    ]);
  });
  it('includes shipping for cancellation/carrier return but retains shipping on customer returns', () => {
    expect(refundSources(order({ status: 'CANCELLED' }))[0].entitled).toBe(
      '960000',
    );
    expect(
      refundSources(
        order({ status: 'RETURNED', shipmentStatus: 'RETURNED' }),
      )[0].entitled,
    ).toBe('960000');
    expect(
      refundSources(order({ status: 'RETURNED', receivedAmount: '930000' }))[0]
        .entitled,
    ).toBe('930000');
  });
  it('separates late and double paid VNPay sources from the original partially refunded collection', () => {
    const input = order({
      payment: {
        provider: 'vnpay',
        status: 'PARTIALLY_REFUNDED',
        amount: '960000',
        transactionNo: '11',
        settled: false,
      },
      attempts: [
        {
          id: 'first',
          provider: 'vnpay',
          status: 'PAID',
          transactionNo: '11',
          amount: '960000',
        },
        {
          id: 'extra',
          provider: 'vnpay',
          status: 'PAID',
          transactionNo: '22',
          amount: '960000',
        },
        {
          id: 'pending',
          provider: 'vnpay',
          status: 'PENDING',
          transactionNo: null,
          amount: '960000',
        },
      ],
      refunds: [{ attemptId: 'first', status: 'SUCCEEDED', amount: '465000' }],
    });
    expect(
      refundSources(input).map((s) => [s.attemptId, s.primary, s.available]),
    ).toEqual([
      ['first', true, '0'],
      ['extra', false, '960000'],
    ]);
  });
  it('does not invent receipts or re-refund legacy refunded/free payments', () => {
    for (const payment of [
      {
        provider: 'cod',
        status: 'PAID',
        amount: '100',
        transactionNo: null,
        settled: false,
      },
      {
        provider: 'cod',
        status: 'REFUNDED',
        amount: '100',
        transactionNo: null,
        settled: true,
      },
      {
        provider: 'free',
        status: 'PAID',
        amount: '0',
        transactionNo: null,
        settled: false,
      },
    ])
      expect(refundSources(order({ payment, receivedAmount: '0' }))).toEqual(
        [],
      );
  });
  it('does not infer an ambiguous legacy refund source from the current payment method', () => {
    const input = order({
      status: 'CANCELLED',
      receivedAmount: '0',
      payment: {
        provider: 'vnpay',
        status: 'PAID',
        amount: '960000',
        transactionNo: '11',
        settled: false,
      },
      attempts: [
        {
          id: 'legacy',
          provider: null,
          status: 'PAID',
          transactionNo: '11',
          amount: '960000',
        },
      ],
    });
    expect(refundSources(input)).toEqual([]);
    input.attempts[0].provider = 'momo';
    expect(refundSources(input)[0]).toMatchObject({
      attemptId: 'legacy',
      primary: false,
      available: '960000',
    });
  });
  it('fails closed for inconsistent ledger totals instead of returning a negative/oversized balance', () => {
    expect(() =>
      refundSources(
        order({
          refunds: [{ attemptId: null, amount: '960001', status: 'REVIEW' }],
        }),
      ),
    ).toThrow();
    expect(() => refundSources(order({ receivedAmount: '960001' }))).toThrow();
  });
});
