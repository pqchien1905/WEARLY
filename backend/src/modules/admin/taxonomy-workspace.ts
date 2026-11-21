import { NotFoundException } from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { catalogSearch } from '../products/catalog-text';
import { AdminTaxonomyQueryDto } from './dto/admin-taxonomy-query.dto';
export type TaxonomyKind = 'categories' | 'brands';

// One aggregate per product, including hidden products. Publication matches
// publicProductWhere: enabled product, a usable image and an enabled variant.
function source(kind: TaxonomyKind) {
  // Identifiers come exclusively from this fixed allowlist, never request text.
  const field =
    kind === 'categories' ? Prisma.sql`"categoryId"` : Prisma.sql`"brandId"`;
  const table =
    kind === 'categories' ? Prisma.sql`"Category"` : Prisma.sql`"Brand"`;
  return Prisma.sql`WITH counts AS (
  SELECT p.${field}, count(*)::int AS products,
    count(*) FILTER (WHERE p.active
      AND EXISTS (SELECT 1 FROM "ProductImage" i WHERE i."productId" = p.id AND i.url <> '')
      AND EXISTS (SELECT 1 FROM "ProductVariant" v WHERE v."productId" = p.id AND v.active))::int AS published
  FROM "Product" p GROUP BY p.${field}
), taxonomy AS (
  SELECT p.*, COALESCE(c.products, 0) AS products,
    COALESCE(c.published, 0) AS "publishedProducts"
  FROM ${table} p LEFT JOIN counts c ON c.${field} = p.id
)`;
}
type Row = {
  id: string;
  name: string;
  slug: string;
  createdAt: Date;
  updatedAt: Date;
  products: number;
  publishedProducts: number;
};
const json = ({ products, ...row }: Row) => ({ ...row, _count: { products } });

export function taxonomyList(
  db: PrismaService,
  kind: TaxonomyKind,
  q: AdminTaxonomyQueryDto,
) {
  const conditions: Prisma.Sql[] = [];
  const search = q.q && catalogSearch(q.q);
  if (search)
    conditions.push(
      Prisma.sql`(${search} OR p.id::text = ${q.q!.toLowerCase()})`,
    );
  if (q.coverage === 'empty') conditions.push(Prisma.sql`p.products = 0`);
  if (q.coverage === 'populated') conditions.push(Prisma.sql`p.products > 0`);
  if (q.coverage === 'published')
    conditions.push(Prisma.sql`p."publishedProducts" > 0`);
  if (q.coverage === 'unpublished')
    conditions.push(Prisma.sql`p."publishedProducts" = 0`);
  const where = conditions.length
    ? Prisma.sql`WHERE ${Prisma.join(conditions, ' AND ')}`
    : Prisma.empty;
  const sorts: Record<string, Prisma.Sql> = {
    name_asc: Prisma.sql`p.name ASC`,
    name_desc: Prisma.sql`p.name DESC`,
    newest: Prisma.sql`p."createdAt" DESC`,
    oldest: Prisma.sql`p."createdAt" ASC`,
    updated: Prisma.sql`p."updatedAt" DESC`,
    products_asc: Prisma.sql`p.products ASC`,
    products_desc: Prisma.sql`p.products DESC`,
  };
  return db.$transaction(
    async (tx) => {
      const [count] = await tx.$queryRaw<
        { total: number }[]
      >(Prisma.sql`${source(kind)}
      SELECT count(*)::int AS total FROM taxonomy p ${where}`);
      const page = Math.min(
        q.page,
        Math.max(1, Math.ceil(count.total / q.limit)),
      );
      const items = await tx.$queryRaw<Row[]>(Prisma.sql`${source(kind)}
      SELECT p.* FROM taxonomy p ${where}
      ORDER BY ${sorts[q.sort] ?? sorts.name_asc}, p.id ASC
      LIMIT ${q.limit} OFFSET ${(page - 1) * q.limit}`);
      return {
        items: items.map(json),
        total: count.total,
        page,
        limit: q.limit,
      };
    },
    { isolationLevel: 'RepeatableRead' },
  );
}

export async function taxonomySummary(db: PrismaService, kind: TaxonomyKind) {
  const [result] = (await db.$queryRaw(Prisma.sql`${source(kind)} SELECT
    count(*)::int AS total,
    count(*) FILTER (WHERE products = 0)::int AS empty,
    count(*) FILTER (WHERE "publishedProducts" > 0)::int AS published,
    COALESCE(sum(products), 0)::int AS products,
    COALESCE(sum("publishedProducts"), 0)::int AS "publishedProducts"
    FROM taxonomy`)) as Record<string, number>[];
  return result;
}

export async function taxonomyDetail(
  db: PrismaService,
  kind: TaxonomyKind,
  id: string,
) {
  return db.$transaction(
    async (tx) => {
      const [row] = await tx.$queryRaw<Row[]>(Prisma.sql`${source(kind)}
    SELECT * FROM taxonomy WHERE id = ${id}::uuid`);
      if (!row) throw new NotFoundException();
      const products = await tx.product.findMany({
        where: kind === 'categories' ? { categoryId: id } : { brandId: id },
        orderBy: [{ updatedAt: 'desc' }, { id: 'asc' }],
        take: 6,
        select: {
          id: true,
          name: true,
          slug: true,
          active: true,
          images: {
            where: { url: { not: '' } },
            orderBy: { position: 'asc' },
            take: 1,
            select: { url: true, alt: true },
          },
          variants: { where: { active: true }, take: 1, select: { id: true } },
        },
      });
      return {
        ...json(row),
        recentProducts: products.map(({ variants, ...p }) => ({
          ...p,
          published: p.active && p.images.length > 0 && variants.length > 0,
        })),
      };
    },
    { isolationLevel: 'RepeatableRead' },
  );
}
