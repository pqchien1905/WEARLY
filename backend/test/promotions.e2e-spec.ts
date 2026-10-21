import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import * as audit from '../src/modules/admin/audit';
describe('Transactional promotions with PostgreSQL', () => {
  let app: INestApplication,
    db: PrismaService,
    admin: string,
    categoryId: string,
    brandId: string;
  const call = (
    method: 'get' | 'post' | 'patch',
    path: string,
    token?: string,
  ) => {
    const r = request(app.getHttpServer())[method]('/api/v1/' + path);
    return token ? r.auth(token, { type: 'bearer' }) : r;
  };
  beforeAll(async () => {
    if (
      !process.env.TEST_DATABASE_URL ||
      !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test')
    )
      throw Error('Dedicated _test database required');
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    process.env.NODE_ENV = 'test';
    process.env.JWT_ACCESS_SECRET = 'test-access-'.repeat(5);
    process.env.JWT_REFRESH_SECRET = 'test-refresh-'.repeat(5);
    process.env.CORS_ORIGINS = 'http://localhost:5173';
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    const a = await register();
    await db.user.update({ where: { id: a.user.id }, data: { role: 'ADMIN' } });
    admin = (
      await call('post', 'auth/login')
        .send({ email: a.user.email, password: 'Promotion-Test-password-2026' })
        .expect(201)
    ).body.accessToken;
    const suffix = randomUUID();
    categoryId = (
      await db.category.create({
        data: { slug: 'promo-' + suffix, name: 'Promo test' },
      })
    ).id;
    brandId = (
      await db.brand.create({
        data: { slug: 'promo-' + suffix, name: 'Promo test' },
      })
    ).id;
  });
  afterAll(async () => {
    if (app) await app.close();
  });
  async function register() {
    return (
      await call('post', 'auth/register')
        .send({
          email: randomUUID() + '@example.test',
          password: 'Promotion-Test-password-2026',
          name: 'Promotion fixture',
        })
        .expect(201)
    ).body;
  }
  const code = () =>
    ('P' + randomUUID().replaceAll('-', '').slice(0, 12)).toUpperCase();
  const coupon = (patch: Record<string, unknown> = {}) =>
    call('post', 'admin/promotions', admin).send({
      code: code(),
      kind: 'FIXED',
      amount: '50000',
      active: true,
      ...patch,
    });
  async function buyer(price = '490000') {
    const c = await register(),
      sku = 'promo-' + randomUUID();
    const address = (
      await call('post', 'users/me/addresses', c.accessToken)
        .send({
          recipient: 'Test',
          phone: '0901234567',
          address: '12 Test Street',
          label: 'Home',
        })
        .expect(201)
    ).body;
    const p = await db.product.create({
      data: {
        slug: sku,
        name: 'Coupon test',
        description: 'Test',
        material: 'Cotton',
        style: 'Test',
        categoryId,
        brandId,
        variants: {
          create: {
            sku,
            size: 'M',
            color: 'Black',
            colorHex: '#000000',
            price,
            inventory: { create: { quantity: 5 } },
          },
        },
      },
      include: { variants: true },
    });
    const add = () =>
      call('post', 'cart/items', c.accessToken).send({ sku, quantity: 1 });
    await add().expect(201);
    const body = {
      addressId: address.id,
      shippingMethod: 'standard',
      expectedSubtotal: price,
    };
    return {
      ...c,
      sku,
      variantId: p.variants[0].id,
      body,
      add,
      create: (
        promotion?: { code: string; discount?: string },
        key = randomUUID(),
        patch = {},
      ) =>
        call('post', 'orders', c.accessToken)
          .set('Idempotency-Key', key)
          .send({
            ...body,
            ...(promotion
              ? {
                  couponCode: promotion.code,
                  expectedDiscount: promotion.discount ?? '50000',
                }
              : {}),
            ...patch,
          }),
      preview: async (couponCode: string) => {
        const cart = (await call('get', 'cart', c.accessToken).expect(200))
          .body;
        return call('post', 'promotions/preview', c.accessToken).send({
          code: couponCode,
          shippingMethod: 'standard',
          cartVersion: cart.version,
        });
      },
    };
  }
  async function uses(couponCode: string) {
    return Number(
      (
        await db.$queryRaw<
          Array<{ count: bigint }>
        >`SELECT count(*) FROM "CouponRedemption" r JOIN "Coupon" c ON c.id=r."couponId" WHERE c.code=${couponCode} AND r."releasedAt" IS NULL`
      )[0].count,
    );
  }
  it('restricts administration and validates ranges, date zones and immutable codes', async () => {
    const c = await register();
    await call('get', 'admin/promotions').expect(401);
    await call('get', 'admin/promotions', c.accessToken).expect(403);
    for (const patch of [
      { kind: 'PERCENT', amount: '101' },
      { amount: '0' },
      { perUserLimit: 0 },
      { usageLimit: -1 },
      { code: 'bad code' },
      { startsAt: '2026-10-21T12:00:00' },
      { startsAt: '2026-12-01T00:00:00Z', expiresAt: '2026-01-01T00:00:00Z' },
    ])
      await coupon(patch).expect(400);
    const created = (await coupon().expect(201)).body;
    await call('patch', `admin/promotions/${created.id}`, admin)
      .send({ code: code(), expectedVersion: created.version })
      .expect(400);
    const updated = (
      await call('patch', `admin/promotions/${created.id}`, admin)
        .send({ active: false, expectedVersion: created.version })
        .expect(200)
    ).body;
    expect(updated.amount).toBe(created.amount);
    expect(updated.active).toBe(false);
    await call('patch', `admin/promotions/${created.id}`, admin)
      .send({ active: true, expectedVersion: created.version })
      .expect(409);
  });
  it('previews server totals without consuming usage and rejects stale cart versions', async () => {
    const c = await buyer('1500001'),
      p = (
        await coupon({
          kind: 'PERCENT',
          amount: '33',
          maxDiscount: '100000',
        }).expect(201)
      ).body;
    const quote = await c.preview(p.code.toLowerCase());
    expect(quote.status).toBe(201);
    expect(quote.body).toMatchObject({
      code: p.code,
      subtotal: '1500001',
      discount: '100000',
      shipping: '0',
      total: '1400001',
    });
    expect(await uses(p.code)).toBe(0);
    await c.add().expect(201);
    await call('post', 'promotions/preview', c.accessToken)
      .send({
        code: p.code,
        shippingMethod: 'standard',
        cartVersion: quote.body.cartVersion,
      })
      .expect(409);
  });
  it('enforces activation, validity windows and minimum merchandise spend at checkout', async () => {
    const c = await buyer();
    for (const patch of [
      { active: false },
      { startsAt: new Date(Date.now() + 3600000).toISOString() },
      { expiresAt: new Date(Date.now() - 1000).toISOString() },
      { minSubtotal: '500000' },
    ]) {
      const p = (await coupon(patch).expect(201)).body;
      await c.create(p).expect(409);
      expect(await uses(p.code)).toBe(0);
    }
    expect(
      (
        await db.inventory.findUniqueOrThrow({
          where: { variantId: c.variantId },
        })
      ).quantity,
    ).toBe(5);
  });
  it('snapshots discount, rejects stale quote and replays after deactivation without consuming twice', async () => {
    const c = await buyer(),
      p = (await coupon().expect(201)).body,
      key = randomUUID();
    await c.create({ ...p, discount: '1' }).expect(409);
    const first = (await c.create(p, key).expect(201)).body;
    expect(first).toMatchObject({
      discount: '50000',
      couponCode: p.code,
      total: '470000',
      payment: { amount: '470000' },
    });
    await call('patch', `admin/promotions/${p.id}`, admin)
      .send({ active: false, expectedVersion: p.version })
      .expect(200);
    expect((await c.create(p, key).expect(201)).body.id).toBe(first.id);
    expect(await uses(p.code)).toBe(1);
    await c.create({ ...p, code: code() }, key).expect(409);
  });
  it('serializes a final global usage across two buyers and releases on pending cancellation', async () => {
    const [a, b] = await Promise.all([buyer(), buyer()]),
      p = (await coupon({ usageLimit: 1 }).expect(201)).body;
    const results = await Promise.all([a.create(p), b.create(p)]);
    expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
    expect(await uses(p.code)).toBe(1);
    const winner = results[0].status === 201 ? a : b,
      loser = results[0].status === 201 ? b : a,
      order = results.find((r) => r.status === 201)!.body;
    await call('post', `orders/${order.id}/cancel`, winner.accessToken).expect(
      201,
    );
    expect(await uses(p.code)).toBe(0);
    await loser.create(p).expect(201);
    expect(await uses(p.code)).toBe(1);
  });
  it('enforces per-buyer limits and rolls back quota with stock failure', async () => {
    const c = await buyer(),
      p = (await coupon({ usageLimit: 10, perUserLimit: 1 }).expect(201)).body;
    await c.create(p).expect(201);
    await c.add().expect(201);
    await c.create(p).expect(409);
    expect(await uses(p.code)).toBe(1);
    const other = await buyer(),
      fresh = (await coupon().expect(201)).body;
    await db.inventory.update({
      where: { variantId: other.variantId },
      data: { quantity: 0 },
    });
    await other.create(fresh).expect(409);
    expect(await uses(fresh.code)).toBe(0);
    expect(
      (await call('get', 'cart', other.accessToken).expect(200)).body.items,
    ).toHaveLength(1);
  });
  it('creates a free order when the selected VNPay provider is disabled', async () => {
    app.get(ConfigService).set('VNPAY_ENABLED', 'false');
    const c = await buyer('1500000'),
      p = (await coupon({ kind: 'PERCENT', amount: '100' }).expect(201)).body;
    const free = (await c.create({ ...p, discount: '1500000' }, randomUUID(), { paymentMethod: 'vnpay' }).expect(201)).body;
    expect(free).toMatchObject({ total: '0', payment: { provider: 'free', status: 'PAID', amount: '0' } });
    expect(await db.paymentAttempt.count({ where: { paymentId: free.payment.id } })).toBe(0);
    expect(await uses(p.code)).toBe(1);
  });
  it('handles zero totals without collecting money and signs VNPay with the discounted total', async () => {
    const c = await buyer('1500000'),
      p = (await coupon({ kind: 'PERCENT', amount: '100' }).expect(201)).body;
    const free = (await c.create({ ...p, discount: '1500000' }).expect(201))
      .body;
    expect(free).toMatchObject({
      total: '0',
      payment: { provider: 'free', status: 'PAID', amount: '0' },
    });
    expect(
      await db.paymentSettlement.count({
        where: { paymentId: free.payment.id },
      }),
    ).toBe(0);
    const config = app.get(ConfigService);
    Object.entries({
      VNPAY_ENABLED: 'true',
      VNPAY_TMN_CODE: 'TEST0001',
      VNPAY_HASH_SECRET: 'promotion-sandbox-fixture-secret',
      VNPAY_RETURN_URL: 'http://localhost:3000/api/v1/payments/vnpay/return',
    }).forEach(([k, v]) => config.set(k, v));
    try {
      const v = await buyer(),
        discount = (await coupon().expect(201)).body;
      const order = (
        await v
          .create(discount, randomUUID(), { paymentMethod: 'vnpay' })
          .expect(201)
      ).body;
      const started = (
        await call(
          'post',
          `payments/orders/${order.id}/start`,
          v.accessToken,
        ).expect(201)
      ).body;
      expect(new URL(started.checkoutUrl).searchParams.get('vnp_Amount')).toBe(
        '47000000',
      );
    } finally {
      config.set('VNPAY_ENABLED', 'false');
    }
  });
  it('rolls back promotion changes when audit persistence fails', async () => {
    const label = code(),
      spy = jest
        .spyOn(audit, 'recordAdminActivity')
        .mockRejectedValueOnce(new Error('Simulated audit failure'));
    try {
      await coupon({ code: label }).expect(500);
      expect(await db.coupon.count({ where: { code: label } })).toBe(0);
    } finally {
      spy.mockRestore();
    }
  });
});
