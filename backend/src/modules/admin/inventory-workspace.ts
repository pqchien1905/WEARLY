import { NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { fail } from '../../common/errors';
import { can } from '../../common/permissions';
import { lockUser, transaction } from '../../common/transaction';
import { catalogSearch } from '../products/catalog-text';
import { recordAdminActivity } from './audit';
import {
  AdminInventoryQueryDto,
  InventoryHistoryQueryDto,
} from './dto/admin-inventory-query.dto';

export const inventoryVariantInclude = {
  product: {
    select: {
      id: true,
      name: true,
      slug: true,
      active: true,
      category: { select: { id: true, name: true } },
      brand: { select: { id: true, name: true } },
      images: { orderBy: { position: 'asc' as const }, take: 1 },
    },
  },
} satisfies Prisma.ProductVariantInclude;
const source = Prisma.sql`FROM "ProductVariant" v JOIN "Product" p ON p.id=v."productId"
  LEFT JOIN "Inventory" i ON i."variantId"=v.id`;
const active = Prisma.sql`(v.active AND p.active)`;

export async function lockInventoryActor(
  tx: Prisma.TransactionClient,
  actorId: string,
) {
  await lockUser(tx, actorId);
  const actor = await tx.user.findUnique({
    where: { id: actorId },
    select: { active: true, role: true },
  });
  if (!actor?.active || !can(actor.role, 'inventory.write'))
    fail(403, 'FORBIDDEN', 'Không có quyền điều chỉnh kho.');
}

export function inventoryList(db: PrismaService, q: AdminInventoryQueryDto) {
  if (q.status && !['in_stock', 'low', 'out'].includes(q.status))
    fail(400, 'INVALID_FILTER', 'Trạng thái kho không hợp lệ.');
  if (
    [q.minQuantity, q.maxQuantity].some(
      (v) => v !== undefined && Number(v) > 2147483647,
    ) ||
    (q.minQuantity !== undefined &&
      q.maxQuantity !== undefined &&
      Number(q.minQuantity) > Number(q.maxQuantity))
  ) {
    fail(400, 'INVALID_QUANTITY_RANGE', 'Khoảng số lượng không hợp lệ.');
  }
  const missing = q.record === 'missing';
  if (
    missing &&
    (q.status || q.minQuantity !== undefined || q.maxQuantity !== undefined)
  )
    fail(400, 'INVALID_FILTER', 'SKU chưa có kho không có số lượng để lọc.');
  const clauses = [
    missing ? Prisma.sql`i.id IS NULL` : Prisma.sql`i.id IS NOT NULL`,
  ];
  // Preserve legacy status-only links from the dashboard. New UI sends visibility explicitly.
  const visibility = q.visibility ?? (q.status ? 'active' : 'all');
  if (visibility === 'active') clauses.push(active);
  if (visibility === 'hidden') clauses.push(Prisma.sql`NOT ${active}`);
  if (q.brandId) clauses.push(Prisma.sql`p."brandId"=${q.brandId}::uuid`);
  if (q.categoryId)
    clauses.push(Prisma.sql`p."categoryId"=${q.categoryId}::uuid`);
  if (q.productId) clauses.push(Prisma.sql`p.id=${q.productId}::uuid`);
  if (q.status === 'in_stock') clauses.push(Prisma.sql`i.quantity>0`);
  if (q.status === 'low') clauses.push(Prisma.sql`i.quantity BETWEEN 1 AND 5`);
  if (q.status === 'out') clauses.push(Prisma.sql`i.quantity=0`);
  if (q.minQuantity !== undefined)
    clauses.push(Prisma.sql`i.quantity>=${Number(q.minQuantity)}`);
  if (q.maxQuantity !== undefined)
    clauses.push(Prisma.sql`i.quantity<=${Number(q.maxQuantity)}`);
  const search = catalogSearch(q.q ?? '');
  if (search) {
    const pattern = '%' + q.q!.replace(/[\\%_]/g, '\\$&') + '%';
    clauses.push(Prisma.sql`(${search} OR v.sku ILIKE ${pattern} OR v.color ILIKE ${pattern}
      OR v.id::text=${q.q!.toLowerCase()} OR p.id::text=${q.q!.toLowerCase()})`);
  }
  const sorts: Record<string, Prisma.Sql> = {
    newest: Prisma.sql`v."createdAt" DESC,v.id DESC`,
    updated: Prisma.sql`i."updatedAt" DESC NULLS LAST,v.id`,
    sku_asc: Prisma.sql`v.sku,v.id`,
    name_asc: Prisma.sql`p.name,v.sku,v.id`,
    quantity_asc: Prisma.sql`i.quantity ASC NULLS LAST,v.id`,
    quantity_desc: Prisma.sql`i.quantity DESC NULLS LAST,v.id`,
    attention: Prisma.sql`i.quantity ASC NULLS LAST,p.name,v.sku,v.id`,
  };
  return db.$transaction(
    async (tx) => {
      const filter = Prisma.sql`${source} WHERE ${Prisma.join(clauses, ' AND ')}`;
      const [count] = await tx.$queryRaw<
        { total: bigint; units: bigint; lowStock: bigint; outOfStock: bigint }[]
      >(
        Prisma.sql`SELECT COUNT(*) AS total, COALESCE(SUM(i.quantity),0) AS units,
          COUNT(*) FILTER (WHERE i.quantity BETWEEN 1 AND 5) AS "lowStock",
          COUNT(*) FILTER (WHERE i.quantity=0) AS "outOfStock" ${filter}`,
      );
      const total = Number(count.total);
      const page = Math.min(q.page, Math.max(1, Math.ceil(total / q.limit)));
      const rows = await tx.$queryRaw<{ id: string }[]>(
        Prisma.sql`SELECT v.id ${filter} ORDER BY ${sorts[q.sort ?? 'updated']} LIMIT ${q.limit} OFFSET ${(page - 1) * q.limit}`,
      );
      const variants = await tx.productVariant.findMany({
        where: { id: { in: rows.map((r) => r.id) } },
        include: { ...inventoryVariantInclude, inventory: true },
      });
      const byId = new Map(variants.map((v) => [v.id, v]));
      return {
        items: rows.map((row) => {
          const { inventory, ...variant } = byId.get(row.id)!;
          return {
            ...(inventory ?? {
              id: null,
              variantId: variant.id,
              quantity: null,
              version: null,
              updatedAt: null,
            }),
            variant,
          };
        }),
        total,
        page,
        limit: q.limit,
        summary: {
          units: Number(count.units),
          lowStock: Number(count.lowStock),
          outOfStock: Number(count.outOfStock),
        },
      };
    },
    { isolationLevel: 'RepeatableRead' },
  );
}

export function inventorySummary(db: PrismaService) {
  return db.$transaction(
    async (tx) => {
      const [counts] = await tx.$queryRaw<
        Record<string, bigint>[]
      >(Prisma.sql`SELECT
      COUNT(i.id) AS skus,COUNT(DISTINCT p.id) FILTER (WHERE i.id IS NOT NULL) AS products,
      COALESCE(SUM(i.quantity),0) AS units,
      COUNT(*) FILTER (WHERE i.quantity>0) AS "inStock",
      COUNT(*) FILTER (WHERE i.quantity BETWEEN 1 AND 5) AS "lowStock",
      COUNT(*) FILTER (WHERE i.quantity=0) AS "outOfStock",
      COUNT(*) FILTER (WHERE i.id IS NULL) AS missing,
      COALESCE(SUM(i.quantity) FILTER (WHERE ${active}),0) AS "activeUnits" ${source}`);
      const brands = await tx.brand.findMany({
        select: { id: true, name: true },
        orderBy: [{ name: 'asc' }, { id: 'asc' }],
      });
      const categories = await tx.category.findMany({
        select: { id: true, name: true },
        orderBy: [{ name: 'asc' }, { id: 'asc' }],
      });
      return {
        ...Object.fromEntries(
          Object.entries(counts).map(([k, v]) => [k, Number(v)]),
        ),
        lowStockThreshold: 5,
        categories,
        brands,
      };
    },
    { isolationLevel: 'RepeatableRead' },
  );
}
export function inventoryDetail(db: PrismaService, id: string) {
  return db.inventory.findUniqueOrThrow({
    where: { id },
    include: { variant: { include: inventoryVariantInclude } },
  });
}
export function initializeInventory(
  db: PrismaService,
  actorId: string,
  variantId: string,
) {
  return transaction(db, async (tx) => {
    await lockInventoryActor(tx, actorId);
    await tx.$queryRaw`SELECT id FROM "ProductVariant" WHERE id=${variantId}::uuid FOR UPDATE`;
    if (
      !(await tx.productVariant.findUnique({
        where: { id: variantId },
        select: { id: true },
      }))
    )
      throw new NotFoundException();
    const existing = await tx.inventory.findUnique({ where: { variantId } });
    if (existing) return existing; // Safe retry, never reset an existing balance.
    const after = await tx.inventory.create({
      data: { variantId, quantity: 0 },
    });
    await recordAdminActivity(tx, actorId, 'INVENTORY_ADJUSTED', after.id, {
      after,
    });
    return after;
  });
}
export function inventoryHistory(
  db: PrismaService,
  id: string,
  q: InventoryHistoryQueryDto,
) {
  if (q.from && q.to && q.from > q.to)
    fail(
      400,
      'INVALID_DATE_RANGE',
      'Ngày bắt đầu phải trước hoặc bằng ngày kết thúc.',
    );
  const where: Prisma.InventoryMovementWhereInput = {
    inventoryId: id,
    ...(q.type === 'in'
      ? { delta: { gt: 0 } }
      : q.type === 'out'
        ? { delta: { lt: 0 } }
        : {}),
    ...(q.type === 'admin'
      ? { reason: { startsWith: 'ADMIN: ' } }
      : q.type === 'order'
        ? { reason: 'ORDER' }
        : q.type === 'cancel'
          ? { reason: 'CANCEL' }
          : q.type === 'return'
            ? { reason: { in: ['CUSTOMER_RETURN', 'SHIPMENT_RETURN'] } }
            : {}),
    createdAt: {
      ...(q.from ? { gte: new Date(`${q.from}T00:00:00+07:00`) } : {}),
      ...(q.to
        ? {
            lt: new Date(
              new Date(`${q.to}T00:00:00+07:00`).getTime() + 86400000,
            ),
          }
        : {}),
    },
  };
  return db.$transaction(
    async (tx) => {
      if (
        !(await tx.inventory.findUnique({
          where: { id },
          select: { id: true },
        }))
      )
        throw new NotFoundException();
      const total = await tx.inventoryMovement.count({ where });
      const page = Math.min(q.page, Math.max(1, Math.ceil(total / q.limit)));
      const incoming = await tx.inventoryMovement.aggregate({
        where: { AND: [where, { delta: { gt: 0 } }] },
        _sum: { delta: true },
      });
      const outgoing = await tx.inventoryMovement.aggregate({
        where: { AND: [where, { delta: { lt: 0 } }] },
        _sum: { delta: true },
      });
      const rows = await tx.inventoryMovement.findMany({
        where,
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        skip: (page - 1) * q.limit,
        take: q.limit,
        include: { order: { select: { id: true, code: true } } },
      });
      // New manual movements have an explicit link in existing audit JSON. Never
      // infer actor/balances from timestamps or reconstruct incomplete old ledgers.
      const ids = rows
        .filter((r) => r.reason.startsWith('ADMIN: '))
        .map((r) => r.id);
      const audits = ids.length
        ? await tx.adminAuditEvent.findMany({
            where: {
              action: 'INVENTORY_ADJUSTED',
              targetId: id,
              OR: ids.map((movementId) => ({
                details: { path: ['after', 'movementId'], equals: movementId },
              })),
            },
            select: { actorId: true, details: true },
          })
        : [];
      const users = await tx.user.findMany({
        where: { id: { in: audits.map((a) => a.actorId) } },
        select: { id: true, name: true },
      });
      const names = new Map(users.map((u) => [u.id, u.name]));
      const linked = new Map(
        audits.map((a) => {
          const details = a.details as {
            before?: { quantity?: number };
            after?: {
              movementId?: string;
              quantity?: number;
              operation?: string;
            };
          };
          return [
            details.after?.movementId,
            {
              before: details.before?.quantity ?? null,
              after: details.after?.quantity ?? null,
              actor: names.get(a.actorId) ?? null,
              operation: details.after?.operation ?? null,
            },
          ];
        }),
      );
      return {
        items: rows.map((r) => ({
          ...r,
          adjustment: linked.get(r.id) ?? null,
        })),
        total,
        page,
        limit: q.limit,
        summary: {
          incoming: incoming._sum.delta ?? 0,
          outgoing: -(outgoing._sum.delta ?? 0),
          net: (incoming._sum.delta ?? 0) + (outgoing._sum.delta ?? 0),
        },
      };
    },
    { isolationLevel: 'RepeatableRead' },
  );
}
