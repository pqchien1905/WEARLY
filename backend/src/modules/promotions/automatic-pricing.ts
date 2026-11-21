import { Prisma } from '../../generated/prisma/client';
import { discountFor } from '../../common/money';

export type AutomaticOffer = Prisma.CouponGetPayload<{
  include: { products: true };
}>;
export async function automaticOffers(
  db: Prisma.TransactionClient,
  now = new Date(),
): Promise<AutomaticOffer[]> {
  return db.coupon.findMany({
    where: {
      application: 'AUTOMATIC',
      active: true,
      AND: [
        { OR: [{ startsAt: null }, { startsAt: { lte: now } }] },
        { OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] },
      ],
    },
    include: { products: true },
    orderBy: { id: 'asc' },
  });
}
export function automaticPrice(
  productId: string,
  price: Prisma.Decimal,
  offers: AutomaticOffer[],
) {
  let discount = new Prisma.Decimal(0),
    chosen: AutomaticOffer | undefined;
  for (const offer of offers) {
    if (
      offer.scope !== 'ALL' &&
      !offer.products.some((p) => p.productId === productId)
    )
      continue;
    const value = discountFor(price, offer);
    if (value.gt(discount)) {
      discount = value;
      chosen = offer;
    }
  }
  return {
    price: price.minus(discount),
    originalPrice: price,
    promotion: chosen
      ? {
          id: chosen.id,
          name: chosen.name || chosen.code,
          expiresAt: chosen.expiresAt,
        }
      : null,
  };
}

// Same integer-VND rounding/cap as discountFor. Used for catalog filtering AND sorting.
export function effectivePriceSql(alias: 'v' | 'v2') {
  const v = Prisma.raw(alias);
  return Prisma.sql`(${v}.price - COALESCE((SELECT MAX(LEAST(${v}.price,
    COALESCE(c."maxDiscount",${v}.price), CASE WHEN c.kind='PERCENT'
      THEN FLOOR(${v}.price*c.amount/100) ELSE c.amount END))
    FROM "Coupon" c WHERE c.application='AUTOMATIC' AND c.active=true
      AND (c."startsAt" IS NULL OR c."startsAt" <= (CURRENT_TIMESTAMP AT TIME ZONE 'UTC'))
      AND (c."expiresAt" IS NULL OR c."expiresAt" > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC'))
      AND (c.scope='ALL' OR EXISTS (SELECT 1 FROM "CouponProduct" cp WHERE cp."couponId"=c.id AND cp."productId"=${v}."productId"))),0))`;
}
