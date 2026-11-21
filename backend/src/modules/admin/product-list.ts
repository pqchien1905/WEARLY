import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { fail } from '../../common/errors';
import { catalogSearch } from '../products/catalog-text';
import { AdminProductsQueryDto } from './dto/admin-products-query.dto';

// Keep the existing response relations for clients that already consume them.
export const adminProductInclude = {
  category: true,
  brand: true,
  images: { orderBy: { position: 'asc' as const } },
  variants: { orderBy: { sku: 'asc' as const }, include: { inventory: true } },
} satisfies Prisma.ProductInclude;

const source = Prisma.sql`FROM "Product" p
  JOIN "Category" c ON c.id=p."categoryId"
  JOIN "Brand" b ON b.id=p."brandId"
  LEFT JOIN LATERAL (
    SELECT COUNT(*)::int AS variants,
      COUNT(*) FILTER (WHERE v.active)::int AS "activeVariants",
      MIN(v.price) FILTER (WHERE v.active) AS "minPrice",
      MAX(v.price) FILTER (WHERE v.active) AS "maxPrice",
      COALESCE(SUM(i.quantity) FILTER (WHERE v.active),0)::bigint AS stock,
      COALESCE(SUM(i.quantity),0)::bigint AS "totalStock",
      COUNT(*) FILTER (WHERE v.active AND i.quantity BETWEEN 1 AND 5)::int AS "lowVariants",
      COUNT(*) FILTER (WHERE v.active AND COALESCE(i.quantity,0)=0)::int AS "outVariants"
    FROM "ProductVariant" v LEFT JOIN "Inventory" i ON i."variantId"=v.id
    WHERE v."productId"=p.id
  ) s ON true`;
const hasImages = Prisma.sql`EXISTS (SELECT 1 FROM "ProductImage" image WHERE image."productId"=p.id AND image.url<>'')`;
const published = Prisma.sql`(p.active AND s."activeVariants">0 AND ${hasImages})`;
type Metrics = {
  id: string;
  variants: number;
  activeVariants: number;
  minPrice: Prisma.Decimal | null;
  maxPrice: Prisma.Decimal | null;
  stock: bigint;
  totalStock: bigint;
  lowVariants: number;
  outVariants: number;
  published: boolean;
};

export function listAdminProducts(db: PrismaService, q: AdminProductsQueryDto) {
  if (q.status && !['active', 'hidden'].includes(q.status))
    fail(400, 'INVALID_FILTER', 'Trạng thái sản phẩm không hợp lệ.');
  if (
    q.minPrice !== undefined &&
    q.maxPrice !== undefined &&
    BigInt(q.minPrice) > BigInt(q.maxPrice)
  )
    fail(
      400,
      'INVALID_PRICE_RANGE',
      'Giá tối thiểu phải nhỏ hơn hoặc bằng giá tối đa.',
    );
  const clauses: Prisma.Sql[] = [];
  if (q.style !== undefined) clauses.push(Prisma.sql`p.style=${q.style}`);
  if (q.status) clauses.push(Prisma.sql`p.active=${q.status === 'active'}`);
  if (q.categoryId)
    clauses.push(Prisma.sql`p."categoryId"=${q.categoryId}::uuid`);
  if (q.brandId) clauses.push(Prisma.sql`p."brandId"=${q.brandId}::uuid`);
  const search = catalogSearch(q.q ?? '');
  if (search) {
    const pattern = '%' + q.q!.replace(/[\\%_]/g, '\\$&') + '%';
    clauses.push(Prisma.sql`(${search} OR p.id::text = ${q.q!.toLowerCase()}
      OR c.name ILIKE ${pattern} OR b.name ILIKE ${pattern}
      OR EXISTS (SELECT 1 FROM "ProductVariant" v WHERE v."productId"=p.id AND v.sku ILIKE ${pattern}))`);
  }
  // Both bounds apply to the same active SKU, as on the storefront.
  if (q.minPrice !== undefined || q.maxPrice !== undefined) {
    const prices = [Prisma.sql`v."productId"=p.id AND v.active`];
    if (q.minPrice !== undefined)
      prices.push(Prisma.sql`v.price>=${new Prisma.Decimal(q.minPrice)}`);
    if (q.maxPrice !== undefined)
      prices.push(Prisma.sql`v.price<=${new Prisma.Decimal(q.maxPrice)}`);
    clauses.push(
      Prisma.sql`EXISTS (SELECT 1 FROM "ProductVariant" v WHERE ${Prisma.join(prices, ' AND ')})`,
    );
  }
  if (q.stock === 'in_stock') clauses.push(Prisma.sql`s.stock>0`);
  if (q.stock === 'low') clauses.push(Prisma.sql`s."lowVariants">0`);
  if (q.stock === 'out')
    clauses.push(Prisma.sql`s."activeVariants">0 AND s.stock=0`);
  if (q.stock === 'no_variants') clauses.push(Prisma.sql`s."activeVariants"=0`);
  if (q.visibility === 'published') clauses.push(published);
  if (q.visibility === 'incomplete') clauses.push(Prisma.sql`NOT ${published}`);
  const filter = Prisma.sql`${source} ${clauses.length ? Prisma.sql`WHERE ${Prisma.join(clauses, ' AND ')}` : Prisma.empty}`;
  const sorts: Record<string, Prisma.Sql> = {
    newest: Prisma.sql`p."createdAt" DESC,p.id DESC`,
    oldest: Prisma.sql`p."createdAt" ASC,p.id`,
    updated: Prisma.sql`p."updatedAt" DESC,p.id DESC`,
    name_asc: Prisma.sql`p.name ASC,p.id`,
    name_desc: Prisma.sql`p.name DESC,p.id`,
    price_asc: Prisma.sql`s."minPrice" ASC NULLS LAST,p.id`,
    price_desc: Prisma.sql`s."minPrice" DESC NULLS LAST,p.id`,
    stock_asc: Prisma.sql`s.stock ASC,p.id`,
    stock_desc: Prisma.sql`s.stock DESC,p.id`,
  };
  return db.$transaction(
    async (tx) => {
      const [count] = await tx.$queryRaw<{ total: bigint }[]>(
        Prisma.sql`SELECT COUNT(*) AS total ${filter}`,
      );
      const rows = await tx.$queryRaw<
        Metrics[]
      >(Prisma.sql`SELECT p.id,s.*,${published} AS published ${filter}
      ORDER BY ${sorts[q.sort ?? 'newest']} LIMIT ${q.limit} OFFSET ${(q.page - 1) * q.limit}`);
      const products = rows.length
        ? await tx.product.findMany({
            where: { id: { in: rows.map((r) => r.id) } },
            include: adminProductInclude,
          })
        : [];
      const byId = new Map(products.map((p) => [p.id, p]));
      return {
        items: rows.map((r) => ({
          ...byId.get(r.id)!,
          summary: {
            variants: r.variants,
            activeVariants: r.activeVariants,
            minPrice: r.minPrice?.toString() ?? null,
            maxPrice: r.maxPrice?.toString() ?? null,
            stock: Number(r.stock),
            totalStock: Number(r.totalStock),
            lowVariants: r.lowVariants,
            outVariants: r.outVariants,
            published: r.published,
          },
        })),
        total: Number(count.total),
        page: q.page,
        limit: q.limit,
      };
    },
    { isolationLevel: 'RepeatableRead' },
  );
}

export function adminProductsSummary(db: PrismaService) {
  return db.$transaction(
    async (tx) => {
      const [counts] = await tx.$queryRaw<
        Record<string, bigint>[]
      >(Prisma.sql`SELECT
      COUNT(*) AS total,COUNT(*) FILTER (WHERE p.active) AS active,
      COUNT(*) FILTER (WHERE NOT p.active) AS hidden,
      COUNT(*) FILTER (WHERE ${published}) AS published,
      COUNT(*) FILTER (WHERE p.active AND s."lowVariants">0) AS "lowStock",
      COUNT(*) FILTER (WHERE p.active AND s."activeVariants">0 AND s.stock=0) AS "outOfStock"
      ${source}`);
      const categories = await tx.category.count();
      return {
        ...Object.fromEntries(
          Object.entries(counts).map(([k, v]) => [k, Number(v)]),
        ),
        categories,
        generatedAt: new Date().toISOString(),
      };
    },
    { isolationLevel: 'RepeatableRead' },
  );
}
