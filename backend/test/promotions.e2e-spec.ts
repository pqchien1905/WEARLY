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
import { PromotionsService } from '../src/modules/promotions/promotions.service';
describe('Transactional promotions with PostgreSQL', () => {
  let app: INestApplication,
    db: PrismaService,
    admin: string,
    categoryId: string,
    brandId: string;
  const call = (
    method: 'get' | 'post' | 'patch' | 'delete',
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
      await call('post', 'auth/admin/login')
        .send({
          username: a.user.username,
          password: 'Promotion-Test-password-2026',
        })
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
  it('can disable a targeted offer after its last product is deleted, but cannot reactivate it without targets', async () => {
    const c = await buyer();
    const variant = await db.productVariant.findUniqueOrThrow({
      where: { id: c.variantId },
    });
    const offer = (
      await coupon({
        application: 'AUTOMATIC',
        name: 'Removed target',
        scope: 'PRODUCTS',
        productIds: [variant.productId],
        minSubtotal: '0',
        usageLimit: null,
      }).expect(201)
    ).body;
    // This is the same join removal performed by the product FK cascade.
    await db.couponProduct.deleteMany({ where: { couponId: offer.id } });
    const stopped = (
      await call('patch', 'admin/promotions/' + offer.id, admin)
        .send({ expectedVersion: offer.version, active: false })
        .expect(200)
    ).body;
    await call('patch', 'admin/promotions/' + offer.id, admin)
      .send({ expectedVersion: stopped.version, active: true })
      .expect(400);
    await call('delete', 'admin/promotions/' + offer.id, admin)
      .send({ expectedVersion: stopped.version })
      .expect(200);
  });
  it('applies selected-product and storewide automatic prices consistently, snapshots orders, and keeps codes optional', async () => {
    const c = await buyer('200001');
    const variant = await db.productVariant.findUniqueOrThrow({
      where: { id: c.variantId },
    });
    await db.productImage.create({
      data: {
        productId: variant.productId,
        url: 'assets/images/shirt.jpg',
        alt: 'Promotion product',
        position: 0,
      },
    });
    const automatic = (
      await coupon({
        application: 'AUTOMATIC',
        name: 'Ưu đãi sản phẩm',
        scope: 'PRODUCTS',
        productIds: [variant.productId],
        kind: 'PERCENT',
        amount: '10',
      }).expect(201)
    ).body;
    let globalId: string | undefined;
    try {
      const detail = (await call('get', `products/${c.sku}`).expect(200)).body;
      expect(detail.variants[0]).toMatchObject({
        price: { amount: '180001' },
        originalPrice: { amount: '200001' },
        promotion: { id: automatic.id, name: 'Ưu đãi sản phẩm' },
      });
      const filtered = (
        await call(
          'get',
          `products?q=Coupon&maxPrice=180001&sort=price-asc`,
        ).expect(200)
      ).body;
      expect(
        filtered.items.some((p: { id: string }) => p.id === variant.productId),
      ).toBe(true);
      let cart = (await call('get', 'cart', c.accessToken).expect(200)).body;
      expect(cart).toMatchObject({
        subtotal: '180001',
        items: [
          expect.objectContaining({
            unitPrice: '180001',
            originalUnitPrice: '200001',
            promotionName: 'Ưu đãi sản phẩm',
          }),
        ],
      });
      expect((await c.preview(automatic.code)).status).toBe(409);
      await c.create().expect(409);
      const global = (
        await coupon({
          application: 'AUTOMATIC',
          name: 'Toàn cửa hàng',
          amount: '10000',
        }).expect(201)
      ).body;
      globalId = global.id;
      cart = (await call('get', 'cart', c.accessToken).expect(200)).body;
      expect(cart.subtotal).toBe('180001'); // The best offer wins; they never stack.
      const manual = (
        await coupon({
          scope: 'PRODUCTS',
          productIds: [variant.productId],
          amount: '1000',
        }).expect(201)
      ).body;
      const preview = await c.preview(manual.code);
      expect(preview.body).toMatchObject({
        subtotal: '180001',
        discount: '1000',
        total: '209001',
      });
      const order = (
        await c
          .create({ code: manual.code, discount: '1000' }, randomUUID(), {
            expectedSubtotal: '180001',
          })
          .expect(201)
      ).body;
      expect(order).toMatchObject({
        subtotal: '180001',
        discount: '1000',
        total: '209001',
        items: [
          expect.objectContaining({
            unitPrice: '180001',
            originalUnitPrice: '200001',
            automaticPromotionId: automatic.id,
          }),
        ],
      });
      const history = (
        await call(
          'get',
          `admin/promotions/${automatic.id}/redemptions`,
          admin,
        ).expect(200)
      ).body;
      expect(history.items).toEqual([
        expect.objectContaining({ orderId: order.id, discount: '20000' }),
      ]);
      const adminDetail = (
        await call('get', `admin/promotions/${automatic.id}`, admin).expect(200)
      ).body;
      expect(adminDetail).toMatchObject({
        canDelete: false,
        usedCount: 1,
        productIds: [variant.productId],
      });
      await call('delete', `admin/promotions/${automatic.id}`, admin)
        .send({ expectedVersion: 0 })
        .expect(409);
      await call('patch', `admin/promotions/${automatic.id}`, admin)
        .send({ expectedVersion: 0, active: false })
        .expect(200);
      const changed = (await call('get', `products/${c.sku}`).expect(200)).body;
      expect(changed.variants[0].price.amount).toBe('190001');
      expect(
        (
          await db.orderItem.findFirstOrThrow({ where: { orderId: order.id } })
        ).unitPrice.toString(),
      ).toBe('180001');
      await call('patch', `admin/promotions/${globalId}`, admin)
        .send({ expectedVersion: 0, expiresAt: '2020-01-01T00:00:00Z' })
        .expect(200);
      expect(
        (await call('get', `products/${c.sku}`).expect(200)).body.variants[0]
          .price.amount,
      ).toBe('200001');
    } finally {
      await db.coupon.updateMany({
        where: { id: { in: [automatic.id, ...(globalId ? [globalId] : [])] } },
        data: { active: false },
      });
    }
  });
  it('validates automatic scope, rejects missing products and prevents changing application type', async () => {
    await coupon({
      application: 'AUTOMATIC',
      name: 'Automatic',
      scope: 'PRODUCTS',
    }).expect(400);
    await coupon({
      application: 'AUTOMATIC',
      name: 'Automatic',
      scope: 'PRODUCTS',
      productIds: [randomUUID()],
    }).expect(400);
    await coupon({
      application: 'AUTOMATIC',
      name: 'Automatic',
      minSubtotal: '1',
    }).expect(400);
    const automatic = (
      await coupon({
        application: 'AUTOMATIC',
        name: 'Scheduled',
        startsAt: '2099-01-01T00:00:00Z',
      }).expect(201)
    ).body;
    await call('patch', `admin/promotions/${automatic.id}`, admin)
      .send({ expectedVersion: 0, application: 'CODE' })
      .expect(400);
    expect(
      (
        await call(
          'get',
          `admin/promotions?application=AUTOMATIC&scope=ALL`,
          admin,
        ).expect(200)
      ).body.items.every(
        (p: { application: string; scope: string }) =>
          p.application === 'AUTOMATIC' && p.scope === 'ALL',
      ),
    ).toBe(true);
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
    const free = (
      await c
        .create({ ...p, discount: '1500000' }, randomUUID(), {
          paymentMethod: 'vnpay',
        })
        .expect(201)
    ).body;
    expect(free).toMatchObject({
      total: '0',
      payment: { provider: 'free', status: 'PAID', amount: '0' },
    });
    expect(
      await db.paymentAttempt.count({ where: { paymentId: free.payment.id } }),
    ).toBe(0);
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
  it('normalizes codes and reports concurrent duplicates without partial writes', async () => {
    const label = code();
    const results = await Promise.all([
      coupon({ code: ' ' + label.toLowerCase() + ' ' }),
      coupon({ code: label }),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
    expect(results.find((r) => r.status === 409)!.body.error.code).toBe(
      'PROMOTION_CODE_EXISTS',
    );
    expect(await db.coupon.count({ where: { code: label } })).toBe(1);
  });
  it('enforces roles on all admin endpoints and rechecks revoked actors in writes', async () => {
    const p = (await coupon().expect(201)).body;
    for (const role of [
      'MANAGER',
      'WAREHOUSE',
      'SUPPORT',
      'CUSTOMER',
    ] as const) {
      const u = await register();
      await db.user.update({ where: { id: u.user.id }, data: { role } });
      for (const path of [
        '',
        '/summary',
        '/' + p.id,
        '/' + p.id + '/redemptions',
      ])
        await call('get', 'admin/promotions' + path, u.accessToken).expect(
          role === 'MANAGER' ? 200 : 403,
        );
      if (role === 'MANAGER') {
        const made = (
          await call('post', 'admin/promotions', u.accessToken)
            .send({ code: code(), kind: 'FIXED', amount: '1' })
            .expect(201)
        ).body;
        await call('delete', 'admin/promotions/' + made.id, u.accessToken)
          .send({ expectedVersion: made.version })
          .expect(200);
        await db.user.update({
          where: { id: u.user.id },
          data: { role: 'CUSTOMER' },
        });
        await expect(
          app.get(PromotionsService).update(u.user.id, p.id, {
            expectedVersion: p.version,
            active: false,
          }),
        ).rejects.toMatchObject({ status: 403 });
        await expect(
          app.get(PromotionsService).remove(u.user.id, p.id, p.version),
        ).rejects.toMatchObject({ status: 403 });
        await expect(
          app.get(PromotionsService).create(u.user.id, {
            application: 'CODE',
            scope: 'ALL',
            name: '',
            productIds: [],
            code: code(),
            kind: 'FIXED',
            amount: '1',
            active: false,
            minSubtotal: '0',
            perUserLimit: 1,
          }),
        ).rejects.toMatchObject({ status: 403 });
      } else {
        await call('post', 'admin/promotions', u.accessToken)
          .send({ code: code(), kind: 'FIXED', amount: '1' })
          .expect(403);
        await call('patch', 'admin/promotions/' + p.id, u.accessToken)
          .send({ expectedVersion: p.version, active: false })
          .expect(403);
        await call('delete', 'admin/promotions/' + p.id, u.accessToken)
          .send({ expectedVersion: p.version })
          .expect(403);
      }
    }
  });
  it('filters real lifecycle states, searches literally, clamps pages and sorts deterministically', async () => {
    const prefix = code();
    const fixtures = [
      { code: prefix + '_ACTIVE', active: true },
      {
        code: prefix + '_SCHEDULED',
        active: true,
        startsAt: new Date(Date.now() + 3600000).toISOString(),
      },
      {
        code: prefix + '_EXPIRED',
        active: true,
        expiresAt: new Date(Date.now() - 60000).toISOString(),
      },
      { code: prefix + '_INACTIVE', active: false },
      { code: prefix + '_EXHAUSTED', active: true, usageLimit: 1 },
    ];
    const before = (
      await call('get', 'admin/promotions/summary', admin).expect(200)
    ).body;
    const rows = [];
    for (const fixture of fixtures)
      rows.push((await coupon(fixture).expect(201)).body);
    const c = await buyer();
    await c.create(rows[4]).expect(201);
    for (const status of [
      'active',
      'scheduled',
      'expired',
      'inactive',
      'exhausted',
    ]) {
      const r = (
        await call('get', 'admin/promotions', admin)
          .query({ q: prefix.toLowerCase(), status })
          .expect(200)
      ).body;
      expect(r.total).toBe(1);
      expect(r.items[0].status).toBe(status);
    }
    const summary = (
      await call('get', 'admin/promotions/summary', admin).expect(200)
    ).body;
    expect(summary.total - before.total).toBe(5);
    for (const status of [
      'active',
      'scheduled',
      'expired',
      'inactive',
      'exhausted',
    ])
      expect(summary[status] - before[status]).toBe(1);
    const page = (
      await call('get', 'admin/promotions', admin)
        .query({ q: prefix, sort: 'code_asc', limit: 2, page: 999 })
        .expect(200)
    ).body;
    expect(page).toMatchObject({ total: 5, page: 3, limit: 2 });
    expect(page.items).toHaveLength(1);
    expect(page.items[0].code).toBe(prefix + '_SCHEDULED');
    for (const q of [prefix + '%', prefix + '_NO_MATCH', prefix + '\\']) {
      expect(
        (await call('get', 'admin/promotions', admin).query({ q }).expect(200))
          .body.total,
      ).toBe(0);
    }
    expect(
      (
        await call('get', 'admin/promotions', admin)
          .query({ q: prefix, kind: 'PERCENT' })
          .expect(200)
      ).body.total,
    ).toBe(0);
    for (const sort of ['newest', 'updated', 'expiry', 'usage_desc'])
      await call('get', 'admin/promotions', admin)
        .query({ q: prefix, sort })
        .expect(200);
  });
  it('preserves released redemption history and blocks deletion even after cancellation', async () => {
    const c = await buyer(),
      p = (await coupon({ usageLimit: 1 }).expect(201)).body;
    const order = (await c.create(p).expect(201)).body;
    const detail = () =>
      call('get', 'admin/promotions/' + p.id, admin).expect(200);
    expect((await detail()).body).toMatchObject({
      usedCount: 1,
      historyCount: 1,
      discountTotal: '50000',
      canDelete: false,
      status: 'exhausted',
      _count: { redemptions: 1 },
    });
    await call('delete', 'admin/promotions/' + p.id, admin)
      .send({ expectedVersion: p.version })
      .expect(409);
    await call('post', `orders/${order.id}/cancel`, c.accessToken).expect(201);
    expect((await detail()).body).toMatchObject({
      usedCount: 0,
      historyCount: 1,
      discountTotal: '0',
      canDelete: false,
      status: 'active',
    });
    const history = (
      await call('get', 'admin/promotions/' + p.id + '/redemptions', admin)
        .query({ page: 999, limit: 1 })
        .expect(200)
    ).body;
    expect(history).toMatchObject({ page: 1, total: 1, limit: 1 });
    expect(history.items[0]).toMatchObject({
      orderId: order.id,
      discount: '50000',
      order: { status: 'CANCELLED' },
    });
    expect(history.items[0].releasedAt).toBeTruthy();
    expect(history.items[0].userId).toBeUndefined();
    const blocked = await call('delete', 'admin/promotions/' + p.id, admin)
      .send({ expectedVersion: p.version })
      .expect(409);
    expect(blocked.body.error.code).toBe('PROMOTION_IN_USE');
  });
  it('deletes only the expected version and rolls deletion back with its audit', async () => {
    const p = (await coupon().expect(201)).body;
    await call('delete', 'admin/promotions/' + p.id, admin)
      .send({ expectedVersion: p.version + 1 })
      .expect(409);
    const spy = jest
      .spyOn(audit, 'recordAdminActivity')
      .mockRejectedValueOnce(new Error('Audit unavailable'));
    try {
      await call('delete', 'admin/promotions/' + p.id, admin)
        .send({ expectedVersion: p.version })
        .expect(500);
      expect(
        await db.coupon.findUnique({ where: { id: p.id } }),
      ).not.toBeNull();
    } finally {
      spy.mockRestore();
    }
    const responses = await Promise.all([
      call('delete', 'admin/promotions/' + p.id, admin).send({
        expectedVersion: p.version,
      }),
      call('delete', 'admin/promotions/' + p.id, admin).send({
        expectedVersion: p.version,
      }),
    ]);
    expect(responses.map((r) => r.status).sort()).toEqual([200, 404]);
    expect(
      await db.adminAuditEvent.count({
        where: { targetId: p.id, action: 'PROMOTION_DELETED' },
      }),
    ).toBe(1);
    await call('get', 'admin/promotions/' + p.id, admin).expect(404);
    await call(
      'get',
      'admin/promotions/' + p.id + '/redemptions',
      admin,
    ).expect(404);
  });
  it('validates list and deletion input and rejects null required promotion values', async () => {
    for (const query of [
      { page: 0 },
      { limit: 101 },
      { status: 'unknown' },
      { kind: 'other' },
      { sort: 'code;DROP' },
      { q: 'a'.repeat(101) },
    ])
      await call('get', 'admin/promotions', admin).query(query).expect(400);
    const p = (await coupon().expect(201)).body;
    for (const field of [
      'kind',
      'amount',
      'active',
      'minSubtotal',
      'perUserLimit',
    ])
      await call('patch', 'admin/promotions/' + p.id, admin)
        .send({ expectedVersion: p.version, [field]: null })
        .expect(400);
    for (const body of [
      {},
      { expectedVersion: -1 },
      { expectedVersion: null },
      { expectedVersion: '0' },
    ])
      await call('delete', 'admin/promotions/' + p.id, admin)
        .send(body)
        .expect(400);
    await call('delete', 'admin/promotions/bad-id', admin)
      .send({ expectedVersion: 0 })
      .expect(400);
    await coupon({ startsAt: '0000-01-01T00:00:00Z' }).expect(400);
    await coupon({ startsAt: '2026-01-01T00:00:00+25:00' }).expect(400);
  });
  it('serializes deletion against checkout without losing an order discount or history', async () => {
    const c = await buyer(),
      p = (await coupon().expect(201)).body;
    const [checkout, deleted] = await Promise.all([
      c.create(p),
      call('delete', 'admin/promotions/' + p.id, admin).send({
        expectedVersion: p.version,
      }),
    ]);
    if (checkout.status === 201) {
      expect(deleted.status).toBe(409);
      expect(deleted.body.error.code).toBe('PROMOTION_IN_USE');
      expect(
        await db.couponRedemption.count({ where: { couponId: p.id } }),
      ).toBe(1);
      expect(checkout.body.discount).toBe('50000');
    } else {
      expect(checkout.status).toBe(409);
      expect(deleted.status).toBe(200);
      expect(
        await db.couponRedemption.count({ where: { couponId: p.id } }),
      ).toBe(0);
    }
  });
});
