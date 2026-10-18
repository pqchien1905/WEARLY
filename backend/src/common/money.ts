import { Prisma } from '../generated/prisma/client';
export function totalForItems(
  items: { price: string | Prisma.Decimal; quantity: number }[],
) {
  return items.reduce((total, item) => {
    const price = new Prisma.Decimal(item.price);
    if (
      !price.isFinite() ||
      !price.isInteger() ||
      price.isNegative() ||
      !Number.isSafeInteger(item.quantity) ||
      item.quantity < 1 ||
      item.quantity > 99
    )
      throw new Error('Invalid money or quantity');
    return total.plus(price.mul(item.quantity));
  }, new Prisma.Decimal(0));
}
export function shippingFee(
  subtotal: string | Prisma.Decimal,
  method: 'standard' | 'express',
) {
  return new Prisma.Decimal(
    method === 'express'
      ? 50000
      : new Prisma.Decimal(subtotal).gte(1500000)
        ? 0
        : 30000,
  );
}
