import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Verified product reviews with PostgreSQL', () => {
  let app: INestApplication,
    db: PrismaService,
    categoryId: string,
    brandId: string;
  const suffix = randomUUID(),
    users: string[] = [],
    tokens: string[] = [],
    products: string[] = [],
    variants: string[] = [],
    orders: string[] = [];
  const path = (product = 0) => `/api/v1/products/${products[product]}/reviews`;
  const call = (
    method: 'get' | 'post' | 'patch' | 'delete',
    tail = '',
    user = 0,
    product = 0,
  ) =>
    request(app.getHttpServer())
      [method](path(product) + tail)
      .auth(tokens[user], { type: 'bearer' });
  beforeAll(async () => {
    if (
      !process.env.TEST_DATABASE_URL ||
      !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test')
    )
      throw new Error('Dedicated _test database required');
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    process.env.NODE_ENV = 'test';
    process.env.JWT_ACCESS_SECRET = 'test-access-'.repeat(5);
    process.env.JWT_REFRESH_SECRET = 'test-refresh-'.repeat(5);
    app = (
      await Test.createTestingModule({ imports: [AppModule] }).compile()
    ).createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    for (let i = 0; i < 3; i++) {
      const r = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({
          name: 'Private review buyer',
          email: `review-${i}-${suffix}@example.test`,
          password: 'Reviews-test-password-2026',
        })
        .expect(201);
      users.push(r.body.user.id);
      tokens.push(r.body.accessToken);
    }
    categoryId = (
      await db.category.create({
        data: { slug: 'reviews-' + suffix, name: 'Review test' },
      })
    ).id;
    brandId = (
      await db.brand.create({
        data: { slug: 'reviews-' + suffix, name: 'Review test' },
      })
    ).id;
    for (let i = 0; i < 2; i++) {
      const p = await db.product.create({
        data: {
          slug: `reviews-${i}-${suffix}`,
          name: 'Review shirt',
          description: '',
          material: '',
          style: '',
          categoryId,
          brandId,
          images:
            i === 0
              ? {
                  create: [
                    {
                      url: 'assets/review-secondary.jpg',
                      alt: 'Side',
                      position: 2,
                    },
                    {
                      url: 'assets/review-primary.jpg',
                      alt: 'Front',
                      position: 0,
                    },
                  ],
                }
              : undefined,
          variants: {
            create: {
              sku: `reviews-${i}-${suffix}`,
              size: 'M',
              color: 'Black',
              colorHex: '#000000',
              price: '490000',
            },
          },
        },
        include: { variants: true },
      });
      products.push(p.id);
      variants.push(p.variants[0].id);
    }
    for (let i = 0; i < 2; i++) {
      const order = await db.order.create({
        data: {
          userId: users[i],
          idempotencyKey: randomUUID(),
          requestHash: '',
          addressSnapshot: {},
          subtotal: '490000',
          shipping: '0',
          total: '490000',
          items: {
            create: {
              variantId: variants[0],
              sku: `reviews-0-${suffix}`,
              slug: `reviews-0-${suffix}`,
              name: 'Review shirt',
              size: 'M',
              color: 'Black',
              image: '',
              unitPrice: '490000',
              quantity: 1,
            },
          },
        },
      });
      orders.push(order.id);
    }
  });
  afterAll(async () => {
    if (db) {
      await db.review.deleteMany({ where: { productId: { in: products } } });
      await db.orderItem.deleteMany({ where: { orderId: { in: orders } } });
      await db.order.deleteMany({ where: { id: { in: orders } } });
      await db.user.deleteMany({ where: { id: { in: users } } });
      await db.productVariant.deleteMany({ where: { id: { in: variants } } });
      await db.product.deleteMany({ where: { id: { in: products } } });
      if (categoryId) await db.category.delete({ where: { id: categoryId } });
      if (brandId) await db.brand.delete({ where: { id: brandId } });
    }
    if (app) await app.close();
  });
  it('allows anonymous empty reads, protects writes and validates payloads', async () => {
    expect(
      (await request(app.getHttpServer()).get(path()).expect(200)).body,
    ).toEqual({ items: [], total: 0, average: null, page: 1, limit: 5 });
    for (const [method, tail] of [
      ['get', '/me'],
      ['post', ''],
      ['patch', '/me'],
      ['delete', '/me'],
    ] as const)
      await request(app.getHttpServer())
        [method](path() + tail)
        .expect(401);
    await request(app.getHttpServer())
      .get('/api/v1/products/not-uuid/reviews')
      .expect(400);
    await request(app.getHttpServer())
      .get(`/api/v1/products/${randomUUID()}/reviews`)
      .expect(404);
    await call('get', '?limit=21').expect(400);
    await call('get', '?page=0').expect(400);
    for (const body of [
      { rating: 0, comment: 'Good' },
      { rating: 6, comment: 'Good' },
      { rating: 3.5, comment: 'Good' },
      { rating: '5', comment: 'Good' },
      { rating: 5, comment: ' ' },
      { rating: 5, comment: 'a'.repeat(2001) },
      { rating: 5, comment: 'Good', userId: users[1] },
    ])
      await call('post').send(body).expect(400);
    expect((await call('get', '/me')).body).toEqual({
      review: null,
      canReview: false,
    });
    await call('post', '', 2).send({ rating: 5, comment: 'Good' }).expect(403);
  });
  it('requires a delivered purchase of this product and rejects duplicate creation', async () => {
    for (const status of [
      'PENDING',
      'CONFIRMED',
      'SHIPPED',
      'CANCELLED',
    ] as const) {
      await db.order.update({ where: { id: orders[0] }, data: { status } });
      await call('post').send({ rating: 4, comment: 'Good' }).expect(403);
    }
    await db.order.update({
      where: { id: orders[0] },
      data: { status: 'DELIVERED' },
    });
    expect((await call('get', '/me')).body.canReview).toBe(true);
    await call('post', '', 0, 1)
      .send({ rating: 4, comment: 'Wrong product' })
      .expect(403);
    const saved = await call('post')
      .send({ rating: 4, comment: '  Cotton mềm  ' })
      .expect(201);
    expect(saved.body).toMatchObject({ rating: 4, comment: 'Cotton mềm' });
    expect(saved.body.userId).toBeUndefined();
    await call('post').send({ rating: 4, comment: 'Duplicate' }).expect(409);
    expect((await call('get', '/me')).body.review.id).toBe(saved.body.id);
    expect((await call('get', '/me', 1)).body.review).toBeNull();
  });
  it('serializes duplicate creation and publishes consistent anonymous pages/average', async () => {
    await db.order.update({
      where: { id: orders[1] },
      data: { status: 'DELIVERED' },
    });
    const results = await Promise.all([
      call('post', '', 1).send({ rating: 2, comment: 'Hơi rộng' }),
      call('post', '', 1).send({ rating: 2, comment: 'Hơi rộng' }),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
    await db.review.create({
      data: {
        userId: users[2],
        productId: products[0],
        rating: 5,
        comment: 'Unverified legacy review',
      },
    });
    const first = (
      await request(app.getHttpServer())
        .get(path() + '?limit=1')
        .expect(200)
    ).body;
    const second = (
      await request(app.getHttpServer())
        .get(path() + '?limit=1&page=2')
        .expect(200)
    ).body;
    expect(first).toMatchObject({ total: 2, average: 3, limit: 1 });
    expect(first.items).toHaveLength(1);
    expect(second.items).toHaveLength(1);
    expect(first.items[0].id).not.toBe(second.items[0].id);
    expect(Object.keys(first.items[0]).sort()).toEqual(
      ['id', 'rating', 'comment', 'createdAt', 'updatedAt'].sort(),
    );
    expect(JSON.stringify(first)).not.toMatch(
      /Private review buyer|example.test|userId|Unverified/,
    );
  });
  it('lists only owned reviews with stable pages and current edit eligibility', async () => {
    const history = (user = 0, query = '') =>
      request(app.getHttpServer())
        .get('/api/v1/users/me/reviews' + query)
        .auth(tokens[user], { type: 'bearer' });
    await request(app.getHttpServer())
      .get('/api/v1/users/me/reviews')
      .expect(401);
    for (const query of [
      '?page=0',
      '?limit=21',
      '?userId=' + users[1],
      '?rating=0',
      '?rating=6',
      '?rating=no',
      '?q=' + 'a'.repeat(101),
    ]) {
      await history(0, query).expect(400);
    }
    const extra = await db.review.create({
      data: {
        userId: users[0],
        productId: products[1],
        rating: 3,
        comment: 'Own legacy second product',
      },
    });
    try {
      await db.review.updateMany({
        where: { userId: users[0] },
        data: { createdAt: new Date('2026-01-01T00:00:00.000Z') },
      });
      const first = (await history(0, '?limit=1').expect(200)).body;
      const second = (await history(0, '?limit=1&page=2').expect(200)).body;
      expect(first).toMatchObject({ total: 2, page: 1, limit: 1 });
      expect(second).toMatchObject({ total: 2, page: 2, limit: 1 });
      const rows = [...first.items, ...second.items];
      expect(rows.map((r: { id: string }) => r.id)).toEqual(
        rows
          .map((r: { id: string }) => r.id)
          .sort()
          .reverse(),
      );
      expect(new Set(rows.map((r: { id: string }) => r.id)).size).toBe(2);
      expect(
        rows.find((r: { productId: string }) => r.productId === products[0]),
      ).toMatchObject({
        canEdit: true,
        product: {
          name: 'Review shirt',
          slug: `reviews-0-${suffix}`,
          image: 'assets/review-primary.jpg',
        },
      });
      expect(rows.find((r: { id: string }) => r.id === extra.id)).toMatchObject(
        { canEdit: false, product: { image: null } },
      );
      expect(Object.keys(rows[0]).sort()).toEqual(
        [
          'id',
          'rating',
          'comment',
          'createdAt',
          'updatedAt',
          'productId',
          'product',
          'canEdit',
        ].sort(),
      );
      expect(JSON.stringify(rows)).not.toMatch(
        /userId|email|Private review buyer|Hơi rộng|Unverified legacy review/,
      );
      expect((await history(1).expect(200)).body).toMatchObject({
        total: 1,
        items: [{ comment: 'Hơi rộng', canEdit: true }],
      });
      expect((await history(2).expect(200)).body).toMatchObject({
        total: 1,
        items: [{ comment: 'Unverified legacy review', canEdit: false }],
      });
      expect(
        (await history(0, '?page=3&limit=1').expect(200)).body,
      ).toMatchObject({ total: 2, items: [] });
      const filtered = (
        await history(0, '?q=SHIRT%20legacy&rating=3&limit=1').expect(200)
      ).body;
      expect(filtered).toMatchObject({ total: 1, items: [{ id: extra.id }] });
      expect(
        (await history(0, '?q=legacy&rating=3&page=2&limit=1').expect(200))
          .body,
      ).toMatchObject({ total: 1, items: [] });
      expect(
        (await history(1, '?q=legacy&rating=3').expect(200)).body,
      ).toMatchObject({ total: 0, items: [] });
      expect((await history(0, '?q=%25').expect(200)).body).toMatchObject({
        total: 0,
        items: [],
      });
    } finally {
      await db.review.delete({ where: { id: extra.id } });
    }
  });
  it('keeps hidden product reviews removable without exposing product metadata', async () => {
    const history = () =>
      request(app.getHttpServer())
        .get('/api/v1/users/me/reviews')
        .auth(tokens[0], { type: 'bearer' });
    const extra = await db.review.create({
      data: {
        userId: users[0],
        productId: products[1],
        rating: 3,
        comment: 'Hidden review',
      },
    });
    try {
      for (const hiddenBy of ['product', 'variant']) {
        await db.product.update({
          where: { id: products[1] },
          data: { active: hiddenBy !== 'product' },
        });
        await db.productVariant.update({
          where: { id: variants[1] },
          data: { active: hiddenBy !== 'variant' },
        });
        const rows = (await history().expect(200)).body.items;
        const hidden = rows.find((r: { id: string }) => r.id === extra.id);
        expect(hidden).toMatchObject({
          productId: products[1],
          comment: 'Hidden review',
          product: null,
          canEdit: false,
        });
        expect(JSON.stringify(hidden)).not.toContain(`reviews-1-${suffix}`);
        expect(JSON.stringify(hidden)).not.toContain('Review shirt');
        const searched = await request(app.getHttpServer())
          .get('/api/v1/users/me/reviews?q=Review%20shirt')
          .auth(tokens[0], { type: 'bearer' })
          .expect(200);
        expect(
          searched.body.items.some((r: { id: string }) => r.id === extra.id),
        ).toBe(false);
      }
      await call('delete', '/me', 0, 1)
        .send({ expectedUpdatedAt: extra.updatedAt.toISOString() })
        .expect(200);
      expect((await history().expect(200)).body.total).toBe(1);
    } finally {
      await db.review.deleteMany({ where: { id: extra.id } });
      await db.product.update({
        where: { id: products[1] },
        data: { active: true },
      });
      await db.productVariant.update({
        where: { id: variants[1] },
        data: { active: true },
      });
    }
  });
  it('guards stale updates/deletes and never targets another customer review', async () => {
    const before = (await call('get', '/me')).body.review;
    await call('patch', '/me')
      .send({ rating: 5, comment: 'Missing version' })
      .expect(400);
    await call('patch', '/me', 2)
      .send({
        rating: 5,
        comment: 'Not a buyer',
        expectedUpdatedAt: before.updatedAt,
      })
      .expect(403);
    const edits = await Promise.all(
      [1, 5].map((rating) =>
        call('patch', '/me').send({
          rating,
          comment: 'Updated',
          expectedUpdatedAt: before.updatedAt,
        }),
      ),
    );
    expect(edits.map((r) => r.status).sort()).toEqual([200, 409]);
    const after = edits.find((r) => r.status === 200)!.body;
    expect(new Date(after.updatedAt).getTime()).toBeGreaterThan(
      new Date(before.updatedAt).getTime(),
    );
    await call('delete', '/me')
      .send({ expectedUpdatedAt: before.updatedAt })
      .expect(409);
    await call('delete', '/me', 1)
      .send({ expectedUpdatedAt: after.updatedAt })
      .expect(409);
    await call('delete', '/me')
      .send({ expectedUpdatedAt: after.updatedAt })
      .expect(200);
    await call('delete', '/me')
      .send({ expectedUpdatedAt: after.updatedAt })
      .expect(200);
    await call('patch', '/me')
      .send({
        rating: 5,
        comment: 'Deleted',
        expectedUpdatedAt: after.updatedAt,
      })
      .expect(404);
    expect((await call('get')).body).toMatchObject({ total: 1, average: 2 });
  });
  it('rejects unsupported ISO versions before reaching database operations', async () => {
    for (const expectedUpdatedAt of [
      '2026-W01-1',
      '2026-01-01',
      '2026-01-01T00:00:00+07:00',
    ]) {
      await call('patch', '/me', 1)
        .send({ rating: 4, comment: 'Changed', expectedUpdatedAt })
        .expect(400);
      await call('delete', '/me', 1).send({ expectedUpdatedAt }).expect(400);
    }
  });
  it('hides public reviews for unavailable products but permits owner removal', async () => {
    await db.product.update({
      where: { id: products[0] },
      data: { active: false },
    });
    await call('get').expect(404);
    const mine = (await call('get', '/me', 1).expect(200)).body;
    expect(mine.canReview).toBe(false);
    expect(mine.review.comment).toBe('Hơi rộng');
    await call('post').send({ rating: 5, comment: 'Hidden' }).expect(404);
    await call('patch', '/me', 1)
      .send({
        rating: 5,
        comment: 'Hidden',
        expectedUpdatedAt: mine.review.updatedAt,
      })
      .expect(404);
    await call('delete', '/me', 1)
      .send({ expectedUpdatedAt: mine.review.updatedAt })
      .expect(200);
    await db.product.update({
      where: { id: products[0] },
      data: { active: true },
    });
    await db.productVariant.update({
      where: { id: variants[0] },
      data: { active: false },
    });
    await call('get').expect(404);
  });
});
