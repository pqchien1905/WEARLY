import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Published catalog completeness and newsletter persistence', () => {
  let app: INestApplication,
    db: PrismaService,
    categoryId: string,
    brandId: string;
  const prefix = 'publication-' + randomUUID(),
    ids: string[] = [];
  const email = prefix + '@example.test';
  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    const [row] = await db.$queryRaw<
      { name: string }[]
    >`SELECT current_database() AS name`;
    expect(row.name.endsWith('_test')).toBe(true);
    categoryId = (
      await db.category.create({ data: { name: prefix, slug: prefix } })
    ).id;
    brandId = (await db.brand.create({ data: { name: prefix, slug: prefix } }))
      .id;
  });
  afterAll(async () => {
    if (db) {
      await db.newsletterSubscription.deleteMany({ where: { email } });
      await db.inventory.deleteMany({
        where: { variant: { productId: { in: ids } } },
      });
      await db.productVariant.deleteMany({ where: { productId: { in: ids } } });
      await db.product.deleteMany({ where: { id: { in: ids } } });
      if (categoryId) await db.category.delete({ where: { id: categoryId } });
      if (brandId) await db.brand.delete({ where: { id: brandId } });
    }
    await app?.close();
  });
  const get = (route: string) =>
    request(app.getHttpServer()).get('/api/v1/' + route);
  it('excludes incomplete products and empty categories, then exposes actual size/style facets', async () => {
    const empty = await get('categories').expect(200);
    expect(empty.body.some((c: { id: string }) => c.id === categoryId)).toBe(
      false,
    );
    for (const [i, size] of ['37', 'Freesize'].entries()) {
      const p = await db.product.create({
        data: {
          slug: prefix + i,
          name: prefix + i,
          description: '',
          material: '',
          style: prefix,
          categoryId,
          brandId,
          variants: {
            create: {
              sku: prefix + i,
              size,
              color: prefix,
              colorHex: '#000000',
              price: '100000',
              inventory: { create: { quantity: 3 } },
            },
          },
        },
      });
      ids.push(p.id);
    }
    expect((await get('products?q=' + prefix).expect(200)).body.total).toBe(0);
    await get('products/' + prefix + '0').expect(404);
    await db.productImage.create({
      data: {
        productId: ids[0],
        url: 'assets/images/shirt.jpg',
        alt: 'Published',
      },
    });
    const result = await get('products?q=' + prefix).expect(200);
    expect(result.body.items.map((p: { id: string }) => p.id)).toEqual([
      ids[0],
    ]);
    const categories = await get('categories').expect(200);
    expect(
      categories.body.some((c: { id: string }) => c.id === categoryId),
    ).toBe(true);
    const facets = await get('products/facets').expect(200);
    expect(facets.body.sizes).toContain('37');
    expect(facets.body.styles).toContain(prefix);
    const filtered = await get('products?q=' + prefix + '&size=37').expect(200);
    expect(filtered.body.total).toBe(1);
    await db.product.update({ where: { id: ids[0] }, data: { active: false } });
    expect(
      (await get('products/facets').expect(200)).body.styles,
    ).not.toContain(prefix);
  });
  it('requires explicit consent and valid email, and safely deduplicates concurrent subscriptions', async () => {
    const post = (body: unknown) =>
      request(app.getHttpServer())
        .post('/api/v1/content/newsletter')
        .send(body as object);
    await post({ email, consent: false }).expect(400);
    await post({ email: 'invalid', consent: true }).expect(400);
    await post({ email, consent: true, role: 'ADMIN' }).expect(400);
    const replies = await Promise.all([
      post({ email: email.toUpperCase(), consent: true }),
      post({ email: ' ' + email + ' ', consent: true }),
    ]);
    expect(replies.map((r) => r.status)).toEqual([201, 201]);
    expect(replies.every((r) => r.body.accepted === true)).toBe(true);
    expect(await db.newsletterSubscription.count({ where: { email } })).toBe(1);
    const before = await db.newsletterSubscription.findUniqueOrThrow({
      where: { email },
    });
    await post({ email, consent: true }).expect(201);
    expect(
      await db.newsletterSubscription.findUniqueOrThrow({ where: { email } }),
    ).toEqual(before);
  });
});
