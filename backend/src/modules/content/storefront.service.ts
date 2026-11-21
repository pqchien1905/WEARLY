import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../database/prisma.service';
import { ProductsService, publicProductWhere } from '../products/products.service';
import { ContentService } from './content.service';
import { defaultStoreDetails } from './store-details';

export const escapeMarkup = (value: string) =>
  value.replace(
    /[&<>"']/g,
    (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[
        c
      ]!,
  );
@Injectable()
export class StorefrontService {
  constructor(
    private readonly db: PrismaService,
    private readonly products: ProductsService,
    private readonly content: ContentService,
    private readonly config: ConfigService,
  ) {}
  private productUrl(slug: string) {
    return (
      this.config.getOrThrow<string>('LOCAL_API_ORIGIN') +
      '/api/v1/storefront/products/' +
      encodeURIComponent(slug)
    );
  }
  async product(slug: string): Promise<string> {
    const [product, publication] = await Promise.all([
      this.products.bySlug(slug),
      this.content.readPublished(),
    ]);
    const name = publication.content?.details.name || defaultStoreDetails.name;
    const title = escapeMarkup(product.name + ' — ' + name),
      description = escapeMarkup(product.description.slice(0, 300)),
      canonical = escapeMarkup(this.productUrl(product.slug));
    const shop = escapeMarkup(
      this.config.getOrThrow<string>('LOCAL_STORE_ORIGIN') +
        '/#/products/' +
        encodeURIComponent(product.slug),
    );
    return `<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>${title}</title><meta name="description" content="${description}"><link rel="canonical" href="${canonical}"><meta property="og:type" content="product"><meta property="og:title" content="${title}"><meta property="og:description" content="${description}"><meta property="og:url" content="${canonical}"></head><body><header><p>${escapeMarkup(name)} · Bản demo chạy local</p></header><main><h1>${escapeMarkup(product.name)}</h1><p>${escapeMarkup(product.description)}</p><h2>Biến thể đang hoạt động</h2><ul>${product.variants.map((v) => `<li>${escapeMarkup(v.color)} / ${escapeMarkup(v.size)} — ${escapeMarkup(v.price.amount)} VND</li>`).join('')}</ul><p>Giá và tồn kho được kiểm tra lại khi đặt hàng. Chưa bán hàng thực tế.</p><a href="${shop}">Mở sản phẩm trong cửa hàng</a></main></body></html>`;
  }
  async sitemap(): Promise<string> {
    const products = await this.db.product.findMany({
      where: publicProductWhere,
      select: { slug: true },
      orderBy: { id: 'asc' },
      take: 50001,
    });
    if (products.length > 50000)
      throw new ServiceUnavailableException('Local sitemap limit exceeded');
    const xml =
      '<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' +
      products
        .map(
          (p) =>
            '<url><loc>' +
            escapeMarkup(this.productUrl(p.slug)) +
            '</loc></url>',
        )
        .join('') +
      '</urlset>';
    if (Buffer.byteLength(xml, 'utf8') > 50 * 1024 * 1024)
      throw new ServiceUnavailableException('Local sitemap limit exceeded');
    return xml;
  }
}
