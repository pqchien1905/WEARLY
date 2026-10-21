import { quoteReturn } from '../src/modules/returns/return-money';

describe('Exact return entitlement', () => {
  it('allocates discounted merchandise over lines with exact whole-VND totals', () => {
    const items = [
      { id: 'b', unitPrice: '3', quantity: 1 },
      { id: 'a', unitPrice: '1', quantity: 2 },
    ];
    expect(
      quoteReturn(items, '1', {}, [
        { orderItemId: 'b', quantity: 1 },
        { orderItemId: 'a', quantity: 2 },
      ]),
    ).toEqual({
      amount: '4',
      items: [
        { orderItemId: 'a', quantity: 2, amount: '1' },
        { orderItemId: 'b', quantity: 1, amount: '3' },
      ],
    });
  });
  it('preserves rounding across repeated partial receipts and zero-price goods', () => {
    const items = [{ id: 'a', unitPrice: '10', quantity: 3 }];
    const values = [0, 1, 2].map(
      (previous) =>
        quoteReturn(items, '25', { a: previous }, [
          { orderItemId: 'a', quantity: 1 },
        ]).amount,
    );
    expect(values).toEqual(['1', '2', '2']);
    expect(
      quoteReturn([{ id: 'a', unitPrice: '0', quantity: 1 }], '0', {}, [
        { orderItemId: 'a', quantity: 1 },
      ]).amount,
    ).toBe('0');
    expect(
      quoteReturn(items, '30', {}, [{ orderItemId: 'a', quantity: 3 }]).amount,
    ).toBe('0');
  });
  it('rejects invalid selections, repeated lines and over-return before any stock operation', () => {
    const items = [{ id: 'a', unitPrice: '10', quantity: 3 }];
    for (const selection of [
      [],
      [{ orderItemId: 'a', quantity: 0 }],
      [{ orderItemId: 'a', quantity: 1.5 }],
      [{ orderItemId: 'unknown', quantity: 1 }],
      [{ orderItemId: 'a', quantity: 3 }],
      [
        { orderItemId: 'a', quantity: 1 },
        { orderItemId: 'a', quantity: 1 },
      ],
    ])
      expect(() => quoteReturn(items, '1', { a: 1 }, selection)).toThrow();
    expect(() =>
      quoteReturn(items, '31', {}, [{ orderItemId: 'a', quantity: 1 }]),
    ).toThrow();
  });
});
