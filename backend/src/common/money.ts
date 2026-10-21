import { Prisma } from '../generated/prisma/client';
export function discountFor(
  subtotal: string | Prisma.Decimal,
  coupon: {
    kind: string;
    amount: string | Prisma.Decimal;
    maxDiscount?: string | Prisma.Decimal | null;
  },
) {
  const base = new Prisma.Decimal(subtotal),
    value = new Prisma.Decimal(coupon.amount);
  if (
    !base.isFinite() ||
    !base.isInteger() ||
    base.isNegative() ||
    !value.isFinite() ||
    !value.isInteger() ||
    value.lte(0) ||
    !['FIXED', 'PERCENT'].includes(coupon.kind) ||
    (coupon.kind === 'PERCENT' && value.gt(100))
  )
    throw new Error('Invalid coupon values');
  let discount =
    coupon.kind === 'PERCENT' ? base.mul(value).div(100).floor() : value;
  if (coupon.maxDiscount != null) {
    const cap = new Prisma.Decimal(coupon.maxDiscount);
    if (!cap.isFinite() || !cap.isInteger() || cap.lte(0))
      throw new Error('Invalid discount ceiling');
    discount = Prisma.Decimal.min(discount, cap);
  }
  return Prisma.Decimal.min(discount, base);
}
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
