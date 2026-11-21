import { NotFoundException } from '@nestjs/common';
import { Prisma, Coupon } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AdminPromotionsQueryDto } from './promotions-query.dto';
import { PageDto } from '../products/dto/query-products.dto';

// One aggregate avoids loading every redemption or issuing a query per coupon.
const source = Prisma.sql`WITH events AS (
  SELECT "couponId", "orderId", discount, "releasedAt" FROM "CouponRedemption"
  UNION ALL
  SELECT i."automaticPromotionId", i."orderId", sum((i."originalUnitPrice"-i."unitPrice")*i.quantity),
    CASE WHEN o.status='CANCELLED' THEN o."updatedAt" ELSE NULL END
  FROM "OrderItem" i JOIN "Order" o ON o.id=i."orderId"
  WHERE i."automaticPromotionId" IS NOT NULL GROUP BY i."automaticPromotionId",i."orderId",o.status,o."updatedAt"
), counts AS (
  SELECT "couponId", count(*)::int AS "historyCount",
    count(*) FILTER (WHERE "releasedAt" IS NULL)::int AS "usedCount",
    COALESCE(sum(discount) FILTER (WHERE "releasedAt" IS NULL),0) AS "discountTotal"
  FROM events GROUP BY "couponId"
), promotions AS (
  SELECT c.*, COALESCE(n."historyCount",0) AS "historyCount",
    COALESCE(n."usedCount",0) AS "usedCount", COALESCE(n."discountTotal",0) AS "discountTotal",
    CASE WHEN NOT c.active THEN 'inactive'
      WHEN c."expiresAt" <= (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') THEN 'expired'
      WHEN c."startsAt" > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') THEN 'scheduled'
      WHEN c."usageLimit" IS NOT NULL AND COALESCE(n."usedCount",0) >= c."usageLimit" THEN 'exhausted'
      ELSE 'active' END AS status
  FROM "Coupon" c LEFT JOIN counts n ON n."couponId"=c.id
)`;
type Row = Coupon & {
  historyCount: number;
  usedCount: number;
  discountTotal: Prisma.Decimal;
  status: string;
};
const json = (row: Row) => ({
  ...row,
  _count: { redemptions: row.usedCount },
  canDelete: row.historyCount === 0,
});
function where(q: AdminPromotionsQueryDto) {
  const clauses: Prisma.Sql[] = [Prisma.sql`true`];
  // strpos is a literal substring match: '%' and '_' are never wildcards.
  if (q.q)
    clauses.push(
      Prisma.sql`(strpos(upper(p.code),upper(${q.q}))>0 OR strpos(upper(p.name),upper(${q.q}))>0)`,
    );
  if (q.application) clauses.push(Prisma.sql`p.application=${q.application}`);
  if (q.scope) clauses.push(Prisma.sql`p.scope=${q.scope}`);
  if (q.status) clauses.push(Prisma.sql`p.status=${q.status}`);
  if (q.kind) clauses.push(Prisma.sql`p.kind::text=${q.kind}`);
  return Prisma.join(clauses, ' AND ');
}
const sorts: Record<string, Prisma.Sql> = {
  newest: Prisma.sql`p."createdAt" DESC,p.id`,
  updated: Prisma.sql`p."updatedAt" DESC,p.id`,
  code_asc: Prisma.sql`p.code,p.id`,
  expiry: Prisma.sql`p."expiresAt" ASC NULLS LAST,p.id`,
  usage_desc: Prisma.sql`p."usedCount" DESC,p.id`,
};
export function listPromotions(db: PrismaService, q: AdminPromotionsQueryDto) {
  return db.$transaction(
    async (tx) => {
      const [count] = await tx.$queryRaw<{ total: number }[]>(
        Prisma.sql`${source} SELECT count(*)::int AS total FROM promotions p WHERE ${where(q)}`,
      );
      const page = Math.min(
        q.page,
        Math.max(1, Math.ceil(count.total / q.limit)),
      );
      const rows = await tx.$queryRaw<Row[]>(
        Prisma.sql`${source} SELECT p.* FROM promotions p WHERE ${where(q)} ORDER BY ${sorts[q.sort]} LIMIT ${q.limit} OFFSET ${(page - 1) * q.limit}`,
      );
      const targets = await tx.couponProduct.findMany({
        where: { couponId: { in: rows.map((r) => r.id) } },
        include: { product: { select: { id: true, name: true } } },
      });
      return {
        items: rows.map((row) => ({
          ...json(row),
          products: targets
            .filter((p) => p.couponId === row.id)
            .map((p) => p.product),
          productIds: targets
            .filter((p) => p.couponId === row.id)
            .map((p) => p.productId),
        })),
        total: count.total,
        page,
        limit: q.limit,
      };
    },
    { isolationLevel: 'RepeatableRead' },
  );
}
export async function promotionsSummary(db: PrismaService) {
  const [row] = await db.$queryRaw<
    Record<string, number>[]
  >(Prisma.sql`${source} SELECT count(*)::int AS total,
    count(*) FILTER (WHERE status='active')::int AS active,
    count(*) FILTER (WHERE status='scheduled')::int AS scheduled,
    count(*) FILTER (WHERE status='expired')::int AS expired,
    count(*) FILTER (WHERE status='exhausted')::int AS exhausted,
    count(*) FILTER (WHERE status='inactive')::int AS inactive FROM promotions`);
  return row;
}
export async function promotionDetail(db: PrismaService, id: string) {
  const [row] = await db.$queryRaw<Row[]>(
    Prisma.sql`${source} SELECT * FROM promotions WHERE id=${id}::uuid`,
  );
  if (!row) throw new NotFoundException();
  const targets = await db.couponProduct.findMany({
    where: { couponId: id },
    include: { product: { select: { id: true, name: true } } },
  });
  return {
    ...json(row),
    products: targets.map((p) => p.product),
    productIds: targets.map((p) => p.productId),
  };
}
export function promotionHistory(db: PrismaService, id: string, q: PageDto) {
  return db.$transaction(
    async (tx) => {
      const promotion = await tx.coupon.findUnique({ where: { id } });
      if (promotion?.application === 'AUTOMATIC') {
        const [count] = await tx.$queryRaw<
          { total: number }[]
        >`SELECT count(DISTINCT "orderId")::int AS total FROM "OrderItem" WHERE "automaticPromotionId"=${id}::uuid`;
        const page = Math.min(
          q.page,
          Math.max(1, Math.ceil(count.total / q.limit)),
        );
        const items = await tx.$queryRaw(
          Prisma.sql`SELECT o.id AS id,o.id AS "orderId", o."createdAt", CASE WHEN o.status='CANCELLED' THEN o."updatedAt" ELSE NULL END AS "releasedAt", sum((i."originalUnitPrice"-i."unitPrice")*i.quantity)::text AS discount, json_build_object('code',o.code,'status',o.status) AS "order" FROM "OrderItem" i JOIN "Order" o ON o.id=i."orderId" WHERE i."automaticPromotionId"=${id}::uuid GROUP BY o.id ORDER BY o."createdAt" DESC,o.id LIMIT ${q.limit} OFFSET ${(page - 1) * q.limit}`,
        );
        return { items, total: count.total, page, limit: q.limit };
      }
      if (
        !(await tx.coupon.findUnique({ where: { id }, select: { id: true } }))
      )
        throw new NotFoundException();
      const total = await tx.couponRedemption.count({
        where: { couponId: id },
      });
      const page = Math.min(q.page, Math.max(1, Math.ceil(total / q.limit)));
      const items = await tx.couponRedemption.findMany({
        where: { couponId: id },
        orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
        skip: (page - 1) * q.limit,
        take: q.limit,
        select: {
          id: true,
          orderId: true,
          discount: true,
          createdAt: true,
          releasedAt: true,
          order: { select: { status: true, code: true } },
        },
      });
      return { items, total, page, limit: q.limit };
    },
    { isolationLevel: 'RepeatableRead' },
  );
}
