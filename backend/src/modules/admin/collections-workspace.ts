import { NotFoundException } from '@nestjs/common';
import { Prisma, StoreCollection } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { catalogSearch } from '../products/catalog-text';
import {
  AdminCollectionsQueryDto,
  CollectionCoverQueryDto,
} from './dto/admin-collections-query.dto';

// Count Products once, independently of their number of images and SKUs.
const source = Prisma.sql`WITH counts AS (
  SELECT p.style, count(*)::int AS "totalProducts",
    count(*) FILTER (WHERE p.active
      AND EXISTS (SELECT 1 FROM "ProductImage" i WHERE i."productId"=p.id AND i.url<>'')
      AND EXISTS (SELECT 1 FROM "ProductVariant" v WHERE v."productId"=p.id AND v.active))::int AS "productCount"
  FROM "Product" p GROUP BY p.style
), collections AS (
  SELECT c.*, c.title || ' ' || c.style AS name,
    COALESCE(n."totalProducts",0) AS "totalProducts", COALESCE(n."productCount",0) AS "productCount"
  FROM "StoreCollection" c LEFT JOIN counts n ON n.style=c.style
)`;
const cover = Prisma.sql`LEFT JOIN LATERAL (
  SELECT jsonb_build_object('productId',p.id,'productSlug',p.slug,'url',i.url,'alt',COALESCE(NULLIF(i.alt,''),p.name)) AS cover
  FROM "Product" p JOIN LATERAL (
    SELECT url,alt FROM "ProductImage" WHERE "productId"=p.id AND url<>'' ORDER BY position,id LIMIT 1
  ) i ON true
  WHERE p.style=c.style AND p.active
    AND EXISTS (SELECT 1 FROM "ProductVariant" v WHERE v."productId"=p.id AND v.active)
  ORDER BY (p.id=c."coverProductId") DESC NULLS LAST, p."createdAt" DESC, p.id ASC LIMIT 1
) selected ON true`;
type Row = StoreCollection & {
  name: string;
  totalProducts: number;
  productCount: number;
  cover: {
    productId: string;
    productSlug: string;
    url: string;
    alt: string;
  } | null;
};
const json = ({ name: _name, ...row }: Row) => ({
  ...row,
  published: row.active && row.productCount > 0,
  coverFallback:
    row.coverProductId !== null && row.coverProductId !== row.cover?.productId,
});
const hydrate = async (tx: Prisma.TransactionClient, ids: string[]) =>
  ids.length
    ? tx.$queryRaw<Row[]>(
        Prisma.sql`${source} SELECT c.*, selected.cover FROM collections c ${cover} WHERE c.id IN (${Prisma.join(ids.map((id) => Prisma.sql`${id}::uuid`))})`,
      )
    : [];

export function listCollections(
  db: PrismaService,
  q: AdminCollectionsQueryDto,
) {
  const clauses: Prisma.Sql[] = [];
  const search = catalogSearch(q.q ?? '');
  if (search)
    clauses.push(Prisma.sql`(${search} OR p.id::text=${q.q!.toLowerCase()})`);
  if (q.status === 'hidden') clauses.push(Prisma.sql`NOT p.active`);
  if (q.status === 'published')
    clauses.push(Prisma.sql`p.active AND p."productCount">0`);
  if (q.status === 'waiting')
    clauses.push(Prisma.sql`p.active AND p."productCount"=0`);
  const where = clauses.length
    ? Prisma.sql`WHERE ${Prisma.join(clauses, ' AND ')}`
    : Prisma.empty;
  const sorts: Record<string, Prisma.Sql> = {
    position: Prisma.sql`p.position ASC`,
    newest: Prisma.sql`p."createdAt" DESC`,
    updated: Prisma.sql`p."updatedAt" DESC`,
    title_asc: Prisma.sql`p.title ASC`,
    title_desc: Prisma.sql`p.title DESC`,
    products_desc: Prisma.sql`p."productCount" DESC`,
  };
  return db.$transaction(
    async (tx) => {
      const [count] = await tx.$queryRaw<{ total: number }[]>(
        Prisma.sql`${source} SELECT count(*)::int AS total FROM collections p ${where}`,
      );
      const page = Math.min(
        q.page,
        Math.max(1, Math.ceil(count.total / q.limit)),
      );
      const ids = await tx.$queryRaw<{ id: string }[]>(
        Prisma.sql`${source} SELECT p.id FROM collections p ${where} ORDER BY ${sorts[q.sort] ?? sorts.position},p.id ASC LIMIT ${q.limit} OFFSET ${(page - 1) * q.limit}`,
      );
      const rows = new Map(
        (
          await hydrate(
            tx,
            ids.map((r) => r.id),
          )
        ).map((row) => [row.id, json(row)]),
      );
      return {
        items: ids.map((r) => rows.get(r.id)!),
        total: count.total,
        page,
        limit: q.limit,
      };
    },
    { isolationLevel: 'RepeatableRead' },
  );
}
export async function collectionsSummary(db: PrismaService) {
  const [row] = await db.$queryRaw<
    Record<string, number>[]
  >(Prisma.sql`${source}
    SELECT count(*)::int AS total,
      count(*) FILTER (WHERE active AND "productCount">0)::int AS published,
      count(*) FILTER (WHERE NOT active)::int AS hidden,
      count(*) FILTER (WHERE active AND "productCount"=0)::int AS waiting FROM collections`);
  return row;
}
export function collectionAdminDetail(db: PrismaService, id: string) {
  return db.$transaction(
    async (tx) => {
      const [row] = await hydrate(tx, [id]);
      if (!row) throw new NotFoundException();
      const products = await tx.product.findMany({
        where: { style: row.style },
        take: 6,
        orderBy: [{ updatedAt: 'desc' }, { id: 'asc' }],
        select: {
          id: true,
          name: true,
          active: true,
          images: {
            where: { url: { not: '' } },
            orderBy: [{ position: 'asc' }, { id: 'asc' }],
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
export function collectionCovers(
  db: PrismaService,
  q: CollectionCoverQueryDto,
) {
  const search = catalogSearch(q.q ?? '');
  return db.$transaction(
    async (tx) => {
      const where = Prisma.sql`FROM "Product" p WHERE p.style=${q.style} AND p.active
        AND EXISTS (SELECT 1 FROM "ProductImage" i WHERE i."productId"=p.id AND i.url<>'')
        AND EXISTS (SELECT 1 FROM "ProductVariant" v WHERE v."productId"=p.id AND v.active)
        ${search ? Prisma.sql`AND ${search}` : Prisma.empty}`;
      const [{ total }] = await tx.$queryRaw<{ total: number }[]>(
        Prisma.sql`SELECT count(*)::int AS total ${where}`,
      );
      const page = Math.min(q.page, Math.max(1, Math.ceil(total / q.limit)));
      const ids = await tx.$queryRaw<{ id: string }[]>(
        Prisma.sql`SELECT p.id ${where} ORDER BY p.name,p.id LIMIT ${q.limit} OFFSET ${(page - 1) * q.limit}`,
      );
      const items = await tx.product.findMany({
        where: { id: { in: ids.map((p) => p.id) } },
        orderBy: [{ name: 'asc' }, { id: 'asc' }],
        select: {
          id: true,
          name: true,
          slug: true,
          images: {
            where: { url: { not: '' } },
            orderBy: [{ position: 'asc' }, { id: 'asc' }],
            take: 1,
            select: { url: true, alt: true },
          },
        },
      });
      return { items, total, page, limit: q.limit };
    },
    { isolationLevel: 'RepeatableRead' },
  );
}
