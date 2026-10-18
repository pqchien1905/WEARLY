import { shippingFee, totalForItems } from '../src/common/money';
describe('VND arithmetic', () => {
  it('totals exact decimal values and applies the existing free shipping threshold', () => {
    expect(
      totalForItems([
        { price: '490000', quantity: 3 },
        { price: '30000', quantity: 1 },
      ]).toString(),
    ).toBe('1500000');
    expect(shippingFee('1500000', 'standard').toString()).toBe('0');
    expect(shippingFee('1499999', 'standard').toString()).toBe('30000');
    expect(shippingFee('1500000', 'express').toString()).toBe('50000');
  });
  it('rejects fractional VND, unsafe quantities, and negative prices', () => {
    expect(() => totalForItems([{ price: '1.5', quantity: 1 }])).toThrow();
    expect(() => totalForItems([{ price: '-1', quantity: 1 }])).toThrow();
    expect(() => totalForItems([{ price: '1', quantity: 0 }])).toThrow();
  });
});
