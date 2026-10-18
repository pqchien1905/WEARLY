import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
describe('Commerce with real PostgreSQL', () => {
  let app: INestApplication, db: PrismaService;
  const pass = 'Wearly-Test-password-2026';
  beforeAll(async () => {
    if (
      !process.env.TEST_DATABASE_URL ||
      !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test')
    )
      throw new Error(
        'Set TEST_DATABASE_URL to a dedicated database ending in _test; never run against business data.',
      );
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    process.env.NODE_ENV = 'test';
    process.env.JWT_ACCESS_SECRET = 'test-access-'.repeat(5);
    process.env.JWT_REFRESH_SECRET = 'test-refresh-'.repeat(5);
    process.env.CORS_ORIGINS = 'http://localhost:5173';
    process.env.SWAGGER_ENABLED = 'true';
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
  });
  afterAll(async () => {
    if (app) await app.close();
  });
  async function customer() {
    const email = randomUUID() + '@example.test';
    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({ name: 'Test Customer', email, password: pass })
      .expect(201);
    const address = await request(app.getHttpServer())
      .post('/api/v1/users/me/addresses')
      .auth(res.body.accessToken, { type: 'bearer' })
      .send({
        recipient: 'Customer',
        phone: '0901234567',
        address: '12 Test Street',
        label: 'Nhà',
        isDefault: true,
      })
      .expect(201);
    return { ...res.body, email, address: address.body };
  }
  async function product(stock = 1) {
    const slug = 'test-' + randomUUID();
    const category = await db.category.upsert({
      where: { slug: 'test' },
      create: { slug: 'test', name: 'Test' },
      update: {},
    });
    const brand = await db.brand.upsert({
      where: { slug: 'test' },
      create: { slug: 'test', name: 'Test' },
      update: {},
    });
    return db.product.create({
      data: {
        slug,
        name: 'Test product',
        description: 'Integration fixture',
        material: 'Cotton',
        style: 'Tối giản',
        categoryId: category.id,
        brandId: brand.id,
        variants: {
          create: {
            sku: slug,
            size: 'M',
            color: 'Đen',
            colorHex: '#29282B',
            price: '490000',
            inventory: { create: { quantity: stock } },
          },
        },
      },
      include: { variants: { include: { inventory: true } } },
    });
  }
  const api = (token: string) => ({
    add: (sku: string, quantity = 1) =>
      request(app.getHttpServer())
        .post('/api/v1/cart/items')
        .auth(token, { type: 'bearer' })
        .send({ sku, quantity }),
    order: (addressId: string, key: string, expectedSubtotal = '490000') =>
      request(app.getHttpServer())
        .post('/api/v1/orders')
        .auth(token, { type: 'bearer' })
        .set('Idempotency-Key', key)
        .send({ addressId, shippingMethod: 'standard', expectedSubtotal }),
  });
  it('serves health and OpenAPI from the real application', async () => {
    await request(app.getHttpServer()).get('/api/v1/health').expect(200);
    const swagger = await request(app.getHttpServer())
      .get('/api/docs-json')
      .expect(200);
    expect(swagger.body.paths['/api/v1/products']).toBeDefined();
  });
  it('rejects public role injection, invalid login and unauthorized resources', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        name: 'x',
        email: 'x@example.test',
        password: pass,
        role: 'ADMIN',
      })
      .expect(400);
    await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email: 'absent@example.test', password: pass })
      .expect(401);
    await request(app.getHttpServer()).get('/api/v1/cart').expect(401);
  });
  it('logs in, rotates refresh tokens, detects replay, and revokes logout sessions', async () => {
    const c = await customer();
    const login = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email: c.email, password: pass })
      .expect(201);
    expect(login.body.user.passwordHash).toBeUndefined();
    const rotated = await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: login.body.refreshToken })
      .expect(201);
    expect(rotated.body.refreshToken).not.toBe(login.body.refreshToken);
    await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: login.body.refreshToken })
      .expect(401);
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .auth(rotated.body.accessToken, { type: 'bearer' })
      .expect(401);
    await request(app.getHttpServer())
      .post('/api/v1/auth/logout')
      .auth(c.accessToken, { type: 'bearer' })
      .expect(201);
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .auth(c.accessToken, { type: 'bearer' })
      .expect(401);
    const sessions = await db.refreshToken.findMany({
      where: { userId: c.user.id },
    });
    expect(
      sessions.every(
        (s) => s.tokenHash.length === 64 && !s.tokenHash.includes('.'),
      ),
    ).toBe(true);
  });
  it('returns catalog filters and exact price strings', async () => {
    const p = await product(2);
    await db.productVariant.create({
      data: {
        productId: p.id,
        sku: p.slug + '-S',
        size: 'S',
        color: 'Trắng',
        colorHex: '#FFFFFF',
        price: '100000',
        inventory: { create: { quantity: 2 } },
      },
    });
    const filtered = await request(app.getHttpServer())
      .get('/api/v1/products')
      .query({ q: p.slug, size: 'M', maxPrice: '100000' })
      .expect(200);
    expect(filtered.body.total).toBe(0);
    const result = await request(app.getHttpServer())
      .get('/api/v1/products/' + p.slug)
      .expect(200);
    expect(result.body.variants[0].price.amount).toEqual(expect.any(String));
    await request(app.getHttpServer())
      .get('/api/v1/products')
      .query({ page: -1 })
      .expect(400);
    await request(app.getHttpServer())
      .get('/api/v1/products/facets')
      .expect(200);
  });
  it('uses database prices, snapshots orders, repeats idempotently and restocks cancellation once', async () => {
    const c = await customer(),
      p = await product(3),
      sku = p.variants[0].sku,
      key = randomUUID();
    await request(app.getHttpServer())
      .post('/api/v1/cart/items')
      .auth(c.accessToken, { type: 'bearer' })
      .send({ sku, quantity: 1, price: 1 })
      .expect(400);
    await api(c.accessToken).add(sku).expect(201);
    const created = await api(c.accessToken)
      .order(c.address.id, key)
      .expect(201);
    expect(created.body.total).toBe('520000');
    expect(created.body.payment.status).toBe('PENDING');
    await db.productVariant.update({
      where: { sku },
      data: { price: '900000' },
    });
    const retry = await api(c.accessToken).order(c.address.id, key).expect(201);
    expect(retry.body.id).toBe(created.body.id);
    expect(retry.body.items[0].unitPrice).toBe('490000');
    await api(c.accessToken).order(c.address.id, key, '900000').expect(409);
    const other = await customer();
    await request(app.getHttpServer())
      .get('/api/v1/orders/' + created.body.id)
      .auth(other.accessToken, { type: 'bearer' })
      .expect(404);
    const cancel = () =>
      request(app.getHttpServer())
        .post('/api/v1/orders/' + created.body.id + '/cancel')
        .auth(c.accessToken, { type: 'bearer' });
    const results = await Promise.all([cancel(), cancel()]);
    expect(results.every((r) => r.status === 201)).toBe(true);
    expect(
      (
        await db.inventory.findUniqueOrThrow({
          where: { variantId: p.variants[0].id },
        })
      ).quantity,
    ).toBe(3);
    expect(
      await db.inventoryMovement.count({
        where: { orderId: created.body.id, reason: 'CANCEL' },
      }),
    ).toBe(1);
  });
  it('prevents overselling the final SKU with simultaneous customers', async () => {
    const p = await product(),
      a = await customer(),
      b = await customer();
    await Promise.all([
      api(a.accessToken).add(p.variants[0].sku).expect(201),
      api(b.accessToken).add(p.variants[0].sku).expect(201),
    ]);
    const results = await Promise.all([
      api(a.accessToken).order(a.address.id, randomUUID()),
      api(b.accessToken).order(b.address.id, randomUUID()),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
    expect(
      (
        await db.inventory.findUniqueOrThrow({
          where: { variantId: p.variants[0].id },
        })
      ).quantity,
    ).toBe(0);
  });
  it('deduplicates simultaneous checkout requests and rolls back on price mismatch', async () => {
    const c = await customer(),
      p = await product(2),
      key = randomUUID();
    await api(c.accessToken).add(p.variants[0].sku).expect(201);
    await api(c.accessToken).order(c.address.id, randomUUID(), '1').expect(409);
    expect(
      (
        await db.inventory.findUniqueOrThrow({
          where: { variantId: p.variants[0].id },
        })
      ).quantity,
    ).toBe(2);
    const results = await Promise.all([
      api(c.accessToken).order(c.address.id, key),
      api(c.accessToken).order(c.address.id, key),
    ]);
    expect(results.map((r) => r.status)).toEqual([201, 201]);
    expect(results[0].body.id).toBe(results[1].body.id);
    expect(await db.order.count({ where: { userId: c.user.id } })).toBe(1);
  });
  it('enforces address ownership and admin authorization', async () => {
    const a = await customer(),
      b = await customer();
    await request(app.getHttpServer())
      .delete('/api/v1/users/me/addresses/' + a.address.id)
      .auth(b.accessToken, { type: 'bearer' })
      .expect(404);
    await request(app.getHttpServer())
      .patch('/api/v1/users/me')
      .auth(a.accessToken, { type: 'bearer' })
      .send({ name: null })
      .expect(400);
    await request(app.getHttpServer())
      .patch('/api/v1/users/me/addresses/' + a.address.id)
      .auth(a.accessToken, { type: 'bearer' })
      .send({ recipient: null })
      .expect(400);
    await request(app.getHttpServer())
      .get('/api/v1/admin/users')
      .auth(a.accessToken, { type: 'bearer' })
      .expect(403);
    await db.user.update({ where: { id: a.user.id }, data: { role: 'ADMIN' } });
    const users = await request(app.getHttpServer())
      .get('/api/v1/admin/users')
      .auth(a.accessToken, { type: 'bearer' })
      .expect(200);
    expect(
      users.body.items.every((u: Record<string, unknown>) => !u.passwordHash),
    ).toBe(true);
  });
  it('does not fabricate AI results when no provider is configured', async () => {
    const c = await customer();
    await request(app.getHttpServer())
      .post('/api/v1/ai/try-on/jobs')
      .auth(c.accessToken, { type: 'bearer' })
      .send({ imageId: randomUUID(), sku: 'missing', consent: true })
      .expect(503);
    await request(app.getHttpServer())
      .get('/api/v1/ai/try-on/jobs/' + randomUUID())
      .auth(c.accessToken, { type: 'bearer' })
      .expect(404);
  });
  it('rejects totals exceeding the database amount range before changing stock', async () => {
    const c = await customer(),
      p = await product(1);
    await db.productVariant.update({
      where: { id: p.variants[0].id },
      data: { price: '99999999999999' },
    });
    await api(c.accessToken).add(p.variants[0].sku).expect(201);
    await request(app.getHttpServer())
      .post('/api/v1/orders')
      .auth(c.accessToken, { type: 'bearer' })
      .set('Idempotency-Key', randomUUID())
      .send({
        addressId: c.address.id,
        shippingMethod: 'express',
        expectedSubtotal: '99999999999999',
      })
      .expect(400);
    expect(
      (
        await db.inventory.findUniqueOrThrow({
          where: { variantId: p.variants[0].id },
        })
      ).quantity,
    ).toBe(1);
  });
});
