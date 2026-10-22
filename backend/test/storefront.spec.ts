import { ConfigService } from '@nestjs/config';
import { ServiceUnavailableException } from '@nestjs/common';
import { PrismaService } from '../src/database/prisma.service';
import { ProductsService } from '../src/modules/products/products.service';
import { ContentService } from '../src/modules/content/content.service';
import { StorefrontService } from '../src/modules/content/storefront.service';

it('refuses an oversized sitemap rather than certifying a truncated catalog', async () => {
  const findMany = jest
    .fn()
    .mockResolvedValue(
      Array.from({ length: 50001 }, () => ({ slug: 'fixture' })),
    );
  const service = new StorefrontService(
    { product: { findMany } } as unknown as PrismaService,
    {} as ProductsService,
    {} as ContentService,
    new ConfigService({ LOCAL_API_ORIGIN: 'http://127.0.0.1:3000' }),
  );
  await expect(service.sitemap()).rejects.toBeInstanceOf(
    ServiceUnavailableException,
  );
});
