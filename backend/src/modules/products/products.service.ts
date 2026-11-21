import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { QueryProductsDto } from './dto/query-products.dto';
import { catalogSearch } from './catalog-text';
import {
  automaticOffers,
  automaticPrice,
  AutomaticOffer,
  effectivePriceSql,
} from '../promotions/automatic-pricing';
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
export const publicProductWhere = {
  active: true,
  variants: { some: { active: true } },
  images: { some: { url: { not: '' } } },
} satisfies Prisma.ProductWhereInput;
export function productJson(p: CatalogProduct, offers: AutomaticOffer[] = []) {
  const prices = p.variants.map(
    (v) => automaticPrice(p.id, v.price, offers).price,
  );
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
      price: {
        amount: automaticPrice(p.id, v.price, offers).price.toString(),
        currency: 'VND',
      },
      originalPrice: { amount: v.price.toString(), currency: 'VND' },
      promotion: automaticPrice(p.id, v.price, offers).promotion,
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
    const clauses = [
      Prisma.sql`p."active" = true`,
      Prisma.sql`EXISTS (SELECT 1 FROM "ProductImage" image WHERE image."productId"=p.id AND image.url<>'')`,
    ];
    const search = catalogSearch(q.q ?? '');
    if (search) clauses.push(search);
    if (q.category) clauses.push(Prisma.sql`c."slug" = ${q.category}`);
    if (q.brand) clauses.push(Prisma.sql`b."slug" = ${q.brand}`);
    if (q.style) clauses.push(Prisma.sql`p."style" = ${q.style}`);
    const variant = [Prisma.sql`v."productId" = p."id" AND v."active" = true`];
    if (q.size) variant.push(Prisma.sql`v."size" = ${q.size}`);
    if (q.color) variant.push(Prisma.sql`v."color" = ${q.color}`);
    if (q.minPrice)
      variant.push(
        Prisma.sql`${effectivePriceSql('v')} >= ${new Prisma.Decimal(q.minPrice)}`,
      );
    if (q.maxPrice)
      variant.push(
        Prisma.sql`${effectivePriceSql('v')} <= ${new Prisma.Decimal(q.maxPrice)}`,
      );
    if (q.inStock === 'true')
      variant.push(
        Prisma.sql`EXISTS (SELECT 1 FROM "Inventory" i WHERE i."variantId" = v."id" AND i."quantity" > 0)`,
      );
    clauses.push(
      Prisma.sql`EXISTS (SELECT 1 FROM "ProductVariant" v WHERE ${Prisma.join(variant, ' AND ')})`,
    );
    const filter = Prisma.sql`FROM "Product" p JOIN "Category" c ON c.id=p."categoryId" JOIN "Brand" b ON b.id=p."brandId" WHERE ${Prisma.join(clauses, ' AND ')}`;
    const price = Prisma.sql`(SELECT MIN(${effectivePriceSql('v2')}) FROM "ProductVariant" v2 WHERE v2."productId"=p.id AND v2.active=true)`;
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
        const offers = await automaticOffers(tx);
        return {
          items: ids.map((p) => productJson(byId.get(p.id)!, offers)),
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
      where: { slug, ...publicProductWhere },
      include: catalogInclude,
    });
    if (!p) throw new NotFoundException();
    return productJson(p, await automaticOffers(this.db));
  }
  async facets() {
    const [colors, sizes, styles] = await this.db.$transaction(
      [
        this.db.productVariant.findMany({
          where: { active: true, product: publicProductWhere },
          distinct: ['color'],
          select: { color: true },
          orderBy: { color: 'asc' },
        }),
        this.db.productVariant.findMany({
          where: { active: true, product: publicProductWhere },
          distinct: ['size'],
          select: { size: true },
          orderBy: { size: 'asc' },
        }),
        this.db.product.findMany({
          where: publicProductWhere,
          distinct: ['style'],
          select: { style: true },
          orderBy: { style: 'asc' },
        }),
      ],
      { isolationLevel: 'RepeatableRead' },
    );
    const clothing = ['XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'];
    const rank = (size: string) => {
      const index = clothing.indexOf(size.toUpperCase());
      return index < 0 ? clothing.length : index;
    };
    return {
      colors: colors.map((v) => v.color).filter(Boolean),
      sizes: sizes
        .map((v) => v.size)
        .filter(Boolean)
        .sort(
          (a, b) =>
            rank(a) - rank(b) || a.localeCompare(b, 'vi', { numeric: true }),
        ),
      styles: styles.map((p) => p.style).filter(Boolean),
    };
  }
  categories() {
    return this.db.category.findMany({
      where: { products: { some: publicProductWhere } },
      orderBy: { name: 'asc' },
    });
  }
  brands() {
    return this.db.brand.findMany({
      where: { products: { some: publicProductWhere } },
      orderBy: { name: 'asc' },
    });
  }
}
