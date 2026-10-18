import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { QueryProductsDto } from './dto/query-products.dto';
export const catalogInclude = {
  category: true,
  brand: true,
  images: { orderBy: { position: 'asc' as const } },
  variants: {
    where: { active: true },
    orderBy: { sku: 'asc' as const },
    include: { inventory: true },
  },
} satisfies Prisma.ProductInclude;
type CatalogProduct = Prisma.ProductGetPayload<{
  include: typeof catalogInclude;
}>;
export function productJson(p: CatalogProduct) {
  const prices = p.variants.map((v) => v.price);
  return {
    id: p.id,
    slug: p.slug,
    name: p.name,
    description: p.description,
    material: p.material,
    style: p.style,
    active: p.active,
    categoryId: p.category.slug,
    category: p.category,
    brand: p.brand,
    tryOnSupported: p.tryOnSupported,
    images: p.images,
    priceFrom: {
      amount: prices.length ? Prisma.Decimal.min(...prices).toString() : '0',
      currency: 'VND',
    },
    variants: p.variants.map((v) => ({
      id: v.id,
      sku: v.sku,
      size: v.size,
      color: v.color,
      colorHex: v.colorHex,
      price: { amount: v.price.toString(), currency: 'VND' },
      available: v.inventory?.quantity ?? 0,
    })),
    createdAt: p.createdAt,
  };
}
@Injectable()
export class ProductsService {
  constructor(private readonly db: PrismaService) {}
  async list(q: QueryProductsDto) {
    if (
      q.minPrice &&
      q.maxPrice &&
      new Prisma.Decimal(q.minPrice).gt(q.maxPrice)
    )
      throw new BadRequestException('Invalid price range');
    // Parameterized SQL gives stable ordering by minimum active SKU price while
    // keeping all size/color/price/stock predicates on the SAME variant.
    const clauses = [Prisma.sql`p."active" = true`];
    if (q.q)
      clauses.push(
        Prisma.sql`(p."name" ILIKE ${'%' + q.q + '%'} OR p."slug" ILIKE ${'%' + q.q + '%'})`,
      );
    if (q.category) clauses.push(Prisma.sql`c."slug" = ${q.category}`);
    if (q.brand) clauses.push(Prisma.sql`b."slug" = ${q.brand}`);
    if (q.style) clauses.push(Prisma.sql`p."style" = ${q.style}`);
    const variant = [Prisma.sql`v."productId" = p."id" AND v."active" = true`];
    if (q.size) variant.push(Prisma.sql`v."size" = ${q.size}`);
    if (q.color) variant.push(Prisma.sql`v."color" = ${q.color}`);
    if (q.minPrice)
      variant.push(Prisma.sql`v."price" >= ${new Prisma.Decimal(q.minPrice)}`);
    if (q.maxPrice)
      variant.push(Prisma.sql`v."price" <= ${new Prisma.Decimal(q.maxPrice)}`);
    if (q.inStock === 'true')
      variant.push(
        Prisma.sql`EXISTS (SELECT 1 FROM "Inventory" i WHERE i."variantId" = v."id" AND i."quantity" > 0)`,
      );
    clauses.push(
      Prisma.sql`EXISTS (SELECT 1 FROM "ProductVariant" v WHERE ${Prisma.join(variant, ' AND ')})`,
    );
    const filter = Prisma.sql`FROM "Product" p JOIN "Category" c ON c.id=p."categoryId" JOIN "Brand" b ON b.id=p."brandId" WHERE ${Prisma.join(clauses, ' AND ')}`;
    const price = Prisma.sql`(SELECT MIN(v2.price) FROM "ProductVariant" v2 WHERE v2."productId"=p.id AND v2.active=true)`;
    const order =
      q.sort === 'price-asc'
        ? Prisma.sql`${price} ASC,p.id`
        : q.sort === 'price-desc'
          ? Prisma.sql`${price} DESC,p.id`
          : q.sort === 'name'
            ? Prisma.sql`p.name ASC,p.id`
            : Prisma.sql`p."createdAt" DESC,p.id`;
    return this.db.$transaction(
      async (tx) => {
        const counts = await tx.$queryRaw<{ total: bigint }[]>(
          Prisma.sql`SELECT COUNT(*) AS total ${filter}`,
        );
        const ids = await tx.$queryRaw<{ id: string }[]>(
          Prisma.sql`SELECT p.id ${filter} ORDER BY ${order} LIMIT ${q.limit} OFFSET ${(q.page - 1) * q.limit}`,
        );
        const products = await tx.product.findMany({
          where: { id: { in: ids.map((p) => p.id) } },
          include: catalogInclude,
        });
        const byId = new Map(products.map((p) => [p.id, p]));
        return {
          items: ids.map((p) => productJson(byId.get(p.id)!)),
          total: Number(counts[0].total),
          page: q.page,
          limit: q.limit,
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  async bySlug(slug: string) {
    const p = await this.db.product.findFirst({
      where: { slug, active: true, variants: { some: { active: true } } },
      include: catalogInclude,
    });
    if (!p) throw new NotFoundException();
    return productJson(p);
  }
  async facets() {
    const rows = await this.db.productVariant.findMany({
      where: { active: true, product: { active: true } },
      distinct: ['color'],
      select: { color: true },
      orderBy: { color: 'asc' },
    });
    return { colors: rows.map((v) => v.color) };
  }
  categories() {
    return this.db.category.findMany({ orderBy: { name: 'asc' } });
  }
  brands() {
    return this.db.brand.findMany({ orderBy: { name: 'asc' } });
  }
}
