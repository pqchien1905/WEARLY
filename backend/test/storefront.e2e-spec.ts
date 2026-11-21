import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Local product HTML previews', () => {
  let app: INestApplication,
    db: PrismaService,
    productId: string,
    categoryId: string,
    brandId: string,
    contentId: string;
  const slug = 'html-' + randomUUID(),
    hostile = '<img src=x onerror="alert(1)"> & sample';
  const html = () =>
    request(app.getHttpServer())
      .get('/api/v1/storefront/products/' + slug)
      .set('Host', 'evil.example');
  beforeAll(async () => {
    if (
      !process.env.TEST_DATABASE_URL ||
      !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test')
    )
      throw Error('Dedicated test database required');
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    process.env.NODE_ENV = 'test';
    process.env.LOCAL_API_ORIGIN = 'http://127.0.0.1:3000';
    process.env.LOCAL_STORE_ORIGIN = 'http://localhost:8080';
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    expect(await db.storeContent.count()).toBe(0);
    categoryId = (
      await db.category.create({ data: { slug, name: 'HTML fixture' } })
    ).id;
    brandId = (await db.brand.create({ data: { slug, name: 'HTML fixture' } }))
      .id;
    productId = (
      await db.product.create({
        data: {
          slug,
          name: hostile,
          description: 'Plain <script>alert(1)</script>',
          material: '',
          style: '',
          categoryId,
          brandId,
          images: { create: { url: 'assets/images/shirt.jpg', alt: 'Product fixture' } },
          variants: {
            create: {
              sku: slug,
              size: 'M',
              color: 'Red',
              colorHex: '#ff0000',
              price: '123456',
            },
          },
        },
      })
    ).id;
    contentId = (
      await db.storeContent.create({
        data: {
          key: 'storefront',
          banner: 'PRIVATE banner',
          policy: 'PRIVATE policy',
          details: { name: 'PRIVATE store' },
        },
      })
    ).id;
  });
  afterAll(async () => {
    try {
      if (db) {
        if (contentId)
          await db.storeContent.delete({ where: { id: contentId } });
        if (productId) {
          await db.productVariant.deleteMany({ where: { productId } });
          await db.product.delete({ where: { id: productId } });
        }
        if (categoryId) await db.category.delete({ where: { id: categoryId } });
        if (brandId) await db.brand.delete({ where: { id: brandId } });
      }
    } finally {
      await app?.close();
      delete process.env.LOCAL_API_ORIGIN;
      delete process.env.LOCAL_STORE_ORIGIN;
    }
  });
  it('escapes product text, uses trusted origins and never exposes draft identity', async () => {
    const r = await html()
      .expect(200)
      .expect('Content-Type', /text\/html/);
    expect(r.headers['x-robots-tag']).toBe('noindex,nofollow');
    expect(r.headers['cache-control']).toBe('no-store');
    expect(r.text).toContain('WEARLY');
    expect(r.text).not.toContain('PRIVATE');
    expect(r.text).not.toContain('evil.example');
    expect(r.text).toContain(
      '&lt;img src=x onerror=&quot;alert(1)&quot;&gt; &amp; sample',
    );
    expect(r.text).not.toContain('<script>');
    expect(r.text).not.toContain('<img');
    expect(r.text).toContain('123456 VND');
    expect(r.text).toContain(
      'http://127.0.0.1:3000/api/v1/storefront/products/' + slug,
    );
    expect(r.text).toContain('http://localhost:8080/#/products/' + slug);
    await db.storeContent.update({
      where: { id: contentId },
      data: {
        publishedAt: new Date(),
        publishedVersion: 1,
        publishedBanner: 'Published',
        publishedPolicy: 'Policy',
        publishedDetails: { name: 'Public & Store' },
      },
    });
    const published = await html().expect(200);
    expect(published.text).toContain('Public &amp; Store');
    expect(published.text).not.toContain('PRIVATE');
  });
  it('lists only active product previews in absolute XML and refuses hidden products', async () => {
    const alias = await request(app.getHttpServer())
      .get('/API/V1/STOREFRONT/sitemap.xml')
      .expect(200);
    expect(alias.headers['x-robots-tag']).toBe('noindex,nofollow');
    expect(alias.headers['cache-control']).toBe('no-store');
    const sitemap = () =>
      request(app.getHttpServer())
        .get('/api/v1/storefront/sitemap.xml')
        .set('Host', 'evil.example');
    const initial = await sitemap().expect(200).expect('Content-Type', /xml/);
    expect(initial.text).toContain(
      '<loc>http://127.0.0.1:3000/api/v1/storefront/products/' +
        slug +
        '</loc>',
    );
    expect(initial.headers['x-robots-tag']).toBe('noindex,nofollow');
    expect(initial.text).not.toContain('evil.example');
    await db.productVariant.updateMany({
      where: { productId },
      data: { active: false },
    });
    await html().expect(404);
    expect((await sitemap()).text).not.toContain(slug);
    await db.productVariant.updateMany({
      where: { productId },
      data: { active: true },
    });
    await db.product.update({
      where: { id: productId },
      data: { active: false },
    });
    const hidden = await html().expect(404);
    expect(hidden.headers['x-robots-tag']).toBe('noindex,nofollow');
    expect((await sitemap()).text).not.toContain(slug);
    await request(app.getHttpServer())
      .get('/api/v1/storefront/products/missing-' + randomUUID())
      .expect(404);
    const robots = await request(app.getHttpServer())
      .get('/api/v1/storefront/robots.txt')
      .expect(200);
    expect(robots.text).toContain('User-agent: *');
    expect(robots.text).not.toContain('Disallow: /');
  });
});
