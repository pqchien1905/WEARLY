import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import request from 'supertest';
import { createHmac, randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { WALLET_HTTP } from '../src/integrations/payments/wallet-gateway';
import { PaymentsService } from '../src/modules/payments/payments.service';

const momoSecret = 'momo-fixture-secret-not-a-key';
const key1 = 'zalopay-fixture-key1-not-a-key';
const key2 = 'zalopay-fixture-key2-not-a-key';
const sha256 = (key: string, value: string) =>
  createHmac('sha256', key).update(value).digest('hex');
const reply = (body: unknown) =>
  Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));
// Order total: 490,000 item + 30,000 standard shipping.
const TOTAL = 520000;
let trans = Math.floor(Math.random() * 1e9) + 1e9;
const nextTrans = () => ++trans;

function momoIpn(
  reference: string,
  patch: Record<string, string | number> = {},
): Record<string, string | number> {
  const f: Record<string, string | number> = {
    partnerCode: 'MOMOTEST',
    orderId: reference,
    requestId: reference,
    amount: TOTAL,
    orderInfo: 'Thanh toan don hang ' + reference,
    orderType: 'momo_wallet',
    transId: nextTrans(),
    resultCode: 0,
    message: 'Thành công.',
    payType: 'napas',
    responseTime: Date.now(),
    extraData: '',
    ...patch,
  };
  const raw =
    `accessKey=ACCESSKEY01&amount=${f.amount}&extraData=${f.extraData}&message=${f.message}` +
    `&orderId=${f.orderId}&orderInfo=${f.orderInfo}&orderType=${f.orderType}` +
    `&partnerCode=${f.partnerCode}&payType=${f.payType}&requestId=${f.requestId}` +
    `&responseTime=${f.responseTime}&resultCode=${f.resultCode}&transId=${f.transId}`;
  return { ...f, signature: sha256(momoSecret, raw) };
}
function zaloCallback(reference: string, amount = TOTAL) {
  const data = JSON.stringify({
    app_id: 2553,
    app_trans_id: reference,
    app_user: 'wearly',
    amount,
    zp_trans_id: nextTrans(),
    server_time: Date.now(),
  });
  return { data, mac: sha256(key2, data), type: 1 };
}

describe('MoMo and ZaloPay sandbox workflow with PostgreSQL and signed fixtures', () => {
  let app: INestApplication,
    db: PrismaService,
    config: ConfigService,
    admin: string;
  const http = jest.fn<ReturnType<typeof fetch>, Parameters<typeof fetch>>();
  const call = (
    method: 'get' | 'post' | 'patch',
    path: string,
    token?: string,
  ) => {
    const req = request(app.getHttpServer())[method]('/api/v1/' + path);
    return token ? req.auth(token, { type: 'bearer' }) : req;
  };
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
    process.env.CORS_ORIGINS = 'http://localhost:5173';
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(WALLET_HTTP)
      .useValue(http)
      .compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    config = app.get(ConfigService);
    Object.entries({
      PAYMENT_WEB_RETURN_URL: 'http://localhost:5173/#/payments/return',
      MOMO_ENABLED: 'true',
      MOMO_PARTNER_CODE: 'MOMOTEST',
      MOMO_ACCESS_KEY: 'ACCESSKEY01',
      MOMO_SECRET_KEY: momoSecret,
      MOMO_RETURN_URL: 'http://localhost:3000/api/v1/payments/momo/return',
      MOMO_IPN_URL: 'http://localhost:3000/api/v1/payments/momo/ipn',
      ZALOPAY_ENABLED: 'true',
      ZALOPAY_APP_ID: '2553',
      ZALOPAY_KEY1: key1,
      ZALOPAY_KEY2: key2,
      ZALOPAY_RETURN_URL:
        'http://localhost:3000/api/v1/payments/zalopay/return',
      ZALOPAY_CALLBACK_URL:
        'http://localhost:3000/api/v1/payments/zalopay/callback',
    }).forEach(([k, v]) => config.set(k, v));
    const a = await customer();
    await db.user.update({ where: { id: a.user.id }, data: { role: 'ADMIN' } });
    admin = (
      await call('post', 'auth/admin/login')
        .send({
          username: a.user.username,
          password: 'Wallet-Test-password-2026',
        })
        .expect(201)
    ).body.accessToken;
  });
  afterAll(async () => {
    if (app) await app.close();
  });
  beforeEach(() => http.mockReset());
  async function customer() {
    return (
      await call('post', 'auth/register')
        .send({
          name: 'Wallet fixture',
          email: randomUUID() + '@example.test',
          password: 'Wallet-Test-password-2026',
        })
        .expect(201)
    ).body;
  }
  async function fixture(paymentMethod: 'momo' | 'zalopay') {
    const c = await customer();
    const address = (
      await call('post', 'users/me/addresses', c.accessToken)
        .send({
          recipient: 'Customer',
          phone: '0901234567',
          address: '12 Test Street',
          label: 'Home',
          isDefault: true,
        })
        .expect(201)
    ).body;
    const category = await db.category.upsert({
      where: { slug: 'wallet-test' },
      create: { slug: 'wallet-test', name: 'Wallet test' },
      update: {},
    });
    const brand = await db.brand.upsert({
      where: { slug: 'wallet-test' },
      create: { slug: 'wallet-test', name: 'Wallet test' },
      update: {},
    });
    const sku = 'wallet-' + randomUUID();
    const product = await db.product.create({
      data: {
        slug: sku,
        name: 'Wallet fixture',
        description: 'Test',
        material: 'Cotton',
        style: 'Test',
        categoryId: category.id,
        brandId: brand.id,
        variants: {
          create: {
            sku,
            size: 'M',
            color: 'Black',
            colorHex: '#000000',
            price: '490000',
            inventory: { create: { quantity: 3 } },
          },
        },
      },
      include: { variants: true },
    });
    await call('post', 'cart/items', c.accessToken)
      .send({ sku, quantity: 1 })
      .expect(201);
    const body = {
      addressId: address.id,
      shippingMethod: 'standard',
      expectedSubtotal: '490000',
      paymentMethod,
    };
    const key = randomUUID();
    return {
      ...c,
      product,
      body,
      key,
      create: () =>
        call('post', 'orders', c.accessToken)
          .set('Idempotency-Key', key)
          .send(body),
    };
  }
  async function unpaid(paymentMethod: 'momo' | 'zalopay') {
    const f = await fixture(paymentMethod),
      order = (await f.create().expect(201)).body;
    return {
      ...f,
      order,
      start: () =>
        call('post', `payments/orders/${order.id}/start`, f.accessToken),
      reconcile: () =>
        call('post', `payments/orders/${order.id}/reconcile`, f.accessToken),
      cancel: () => call('post', `orders/${order.id}/cancel`, f.accessToken),
    };
  }
  /** Answers MoMo create calls with a payment page for the request's orderId. */
  function momoCreates() {
    http.mockImplementation((_url, init) => {
      const body = JSON.parse(String(init!.body)) as Record<string, unknown>;
      return reply({
        partnerCode: 'MOMOTEST',
        resultCode: 0,
        orderId: body.orderId,
        amount: body.amount,
        payUrl:
          'https://test-payment.momo.vn/v2/gateway/pay?t=' +
          String(body.orderId),
      });
    });
  }
  const confirm = (order: { id: string }, version: number) =>
    call('patch', `admin/orders/${order.id}/status`, admin).send({
      status: 'CONFIRMED',
      expectedVersion: version,
    });

  it('reports wallet availability and keeps stock when a wallet is disabled', async () => {
    expect(
      (await call('get', 'payments/methods').expect(200)).body,
    ).toMatchObject({
      cod: true,
      momo: true,
      zalopay: true,
      sandbox: true,
    });
    const f = await fixture('momo');
    config.set('MOMO_ENABLED', 'false');
    try {
      expect(
        (await call('get', 'payments/methods').expect(200)).body.momo,
      ).toBe(false);
      expect((await f.create().expect(503)).body.error.code).toBe(
        'PAYMENT_UNAVAILABLE',
      );
      const inv = await db.inventory.findUniqueOrThrow({
        where: { variantId: f.product.variants[0].id },
      });
      expect(inv.quantity).toBe(3);
    } finally {
      config.set('MOMO_ENABLED', 'true');
    }
    const order = (await f.create().expect(201)).body;
    expect(order.payment).toMatchObject({
      provider: 'momo',
      status: 'PENDING',
    });
    // The payment method is part of the idempotency hash.
    await call('post', 'orders', f.accessToken)
      .set('Idempotency-Key', f.key)
      .send({ ...f.body, paymentMethod: 'zalopay' })
      .expect(409);
  });

  it('issues one MoMo link, confirms a signed IPN once and then allows fulfilment', async () => {
    const f = await unpaid('momo');
    momoCreates();
    const first = (await f.start().expect(201)).body;
    expect(first).toMatchObject({ provider: 'momo', paymentStatus: 'PENDING' });
    expect(first.checkoutUrl).toBe(
      'https://test-payment.momo.vn/v2/gateway/pay?t=' +
        first.attempt.reference,
    );
    expect(http).toHaveBeenCalledTimes(1);
    const again = (await f.start().expect(201)).body;
    expect(again.attempt.reference).toBe(first.attempt.reference);
    expect(http).toHaveBeenCalledTimes(1);
    // Unpaid online orders cannot be confirmed or cancelled before verification.
    expect(
      (await confirm(f.order, f.order.version).expect(409)).body.error.code,
    ).toBe('PAYMENT_REQUIRED');
    expect((await f.cancel().expect(409)).body.error.code).toBe(
      'PAYMENT_RECONCILIATION_REQUIRED',
    );
    // Forged and mismatched notifications change nothing.
    await call('post', 'payments/momo/ipn')
      .send({ ...momoIpn(first.attempt.reference), signature: 'f'.repeat(64) })
      .expect(400);
    await call('post', 'payments/momo/ipn')
      .send(momoIpn(first.attempt.reference, { amount: 1000 }))
      .expect(204);
    expect(
      (await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } }))
        .status,
    ).toBe('PENDING');
    const ipn = momoIpn(first.attempt.reference);
    await call('post', 'payments/momo/ipn').send(ipn).expect(204);
    await call('post', 'payments/momo/ipn').send(ipn).expect(204);
    const payment = await db.payment.findUniqueOrThrow({
      where: { orderId: f.order.id },
      include: { attempts: true },
    });
    expect(payment).toMatchObject({
      status: 'PAID',
      providerTransactionId: String(ipn.transId),
    });
    expect(payment.attempts).toHaveLength(1);
    const order = await db.order.findUniqueOrThrow({
      where: { id: f.order.id },
    });
    await confirm(order, order.version).expect(200);
    expect(
      await db.mailOutbox.count({
        where: {
          orderId: f.order.id,
          eventKey: 'momo-paid:' + payment.attempts[0].id,
        },
      }),
    ).toBe(1);
  });

  it('retains an uncertain create request until the gateway verifies failure', async () => {
    const f = await unpaid('momo');
    http.mockRejectedValueOnce(new Error('network'));
    expect((await f.start().expect(503)).body.error.code).toBe(
      'PAYMENT_PROVIDER_UNAVAILABLE',
    );
    const failed = await db.paymentAttempt.findMany({
      where: { payment: { orderId: f.order.id } },
    });
    expect(failed.map((a) => [a.status, a.checkoutUrl])).toEqual([
      ['PENDING', null],
    ]);
    const uncertain = (await f.start().expect(201)).body;
    expect(uncertain.attempt.reference).toBe(failed[0].reference);
    expect(uncertain.checkoutUrl).toBeNull();
    http.mockReset();
    http.mockReturnValueOnce(
      reply({
        partnerCode: 'MOMOTEST',
        orderId: failed[0].reference,
        amount: TOTAL,
        resultCode: 1006,
        transId: 0,
      }),
    );
    await f.reconcile().expect(201);
    momoCreates();
    const retry = (await f.start().expect(201)).body;
    expect(retry.checkoutUrl).toContain(retry.attempt.reference);
    expect(retry.attempt.reference).not.toBe(failed[0].reference);
  });

  it('reconciles a declined MoMo payment by query and then allows cancellation', async () => {
    const f = await unpaid('momo');
    momoCreates();
    const started = (await f.start().expect(201)).body;
    http.mockReset();
    http.mockReturnValueOnce(
      reply({
        partnerCode: 'MOMOTEST',
        orderId: started.attempt.reference,
        amount: TOTAL,
        resultCode: 1006,
        transId: 0,
      }),
    );
    const state = (await f.reconcile().expect(201)).body;
    expect(state).toMatchObject({ paymentStatus: 'FAILED', checkoutUrl: null });
    expect((await f.reconcile().expect(429)).body.error.code).toBe(
      'PAYMENT_QUERY_RATE_LIMITED',
    );
    await f.cancel().expect(201);
    const inv = await db.inventory.findUniqueOrThrow({
      where: { variantId: f.product.variants[0].id },
    });
    expect(inv.quantity).toBe(3);
  });

  it('confirms ZaloPay callbacks signed with key2 only', async () => {
    const f = await unpaid('zalopay');
    http.mockReturnValueOnce(
      reply({
        return_code: 1,
        order_url: 'https://qcgateway.zalopay.vn/openinapp?order=fixture',
      }),
    );
    const started = (await f.start().expect(201)).body;
    expect(started).toMatchObject({
      provider: 'zalopay',
      checkoutUrl: 'https://qcgateway.zalopay.vn/openinapp?order=fixture',
    });
    expect(started.attempt.reference).toMatch(/^\d{6}_[a-f0-9]{24}$/);
    const forged = zaloCallback(started.attempt.reference);
    expect(
      (
        await call('post', 'payments/zalopay/callback')
          .send({ ...forged, mac: sha256(key1, forged.data) })
          .expect(200)
      ).body,
    ).toMatchObject({ return_code: -1 });
    expect(
      (
        await call('post', 'payments/zalopay/callback')
          .send(zaloCallback(started.attempt.reference))
          .expect(200)
      ).body,
    ).toMatchObject({ return_code: 1 });
    expect(
      (await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } }))
        .status,
    ).toBe('PAID');
  });

  it('records and refunds late MoMo collection after switching to COD, even when new MoMo payments are disabled', async () => {
    const f = await unpaid('momo');
    momoCreates();
    const started = (await f.start().expect(201)).body;
    await call('post', 'payments/momo/ipn')
      .send(
        momoIpn(started.attempt.reference, { resultCode: 1006, transId: 0 }),
      )
      .expect(204);
    await call('patch', `payments/orders/${f.order.id}/method`, f.accessToken)
      .send({ paymentMethod: 'cod' })
      .expect(200);
    config.set('MOMO_ENABLED', 'false');
    try {
      const ipn = momoIpn(started.attempt.reference);
      await call('post', 'payments/momo/ipn').send(ipn).expect(204);
      await call('post', 'payments/momo/ipn').send(ipn).expect(204);
      const attempt = await db.paymentAttempt.findUniqueOrThrow({
        where: { reference: started.attempt.reference },
      });
      expect(attempt).toMatchObject({
        provider: 'momo',
        status: 'PAID',
        reviewRequired: true,
        transactionNo: String(ipn.transId),
      });
      expect(
        await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } }),
      ).toMatchObject({
        provider: 'cod',
        status: 'PENDING',
        providerTransactionId: null,
      });
      const state = (
        await call('get', `admin/orders/${f.order.id}/refunds`, admin).expect(
          200,
        )
      ).body;
      expect(state.sources).toEqual([
        expect.objectContaining({
          attemptId: attempt.id,
          primary: false,
          available: String(TOTAL),
          provider: 'momo',
        }),
      ]);
      http.mockReset();
      http.mockImplementationOnce((_url, init) => {
        const body = JSON.parse(String(init!.body));
        return reply({
          partnerCode: 'MOMOTEST',
          orderId: body.orderId,
          resultCode: 0,
          transId: nextTrans(),
          amount: body.amount,
        });
      });
      const dto = {
        requestKey: randomUUID(),
        expectedVersion: state.version,
        expectedAmount: String(TOTAL),
        paymentAttemptId: attempt.id,
      };
      const refund = (
        await call('post', `admin/orders/${f.order.id}/refunds`, admin)
          .send(dto)
          .expect(201)
      ).body;
      expect(refund).toMatchObject({ status: 'SUCCEEDED', provider: 'momo' });
      await call('post', `admin/orders/${f.order.id}/refunds`, admin)
        .send(dto)
        .expect(201);
      expect(http).toHaveBeenCalledTimes(1);
      expect(
        await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } }),
      ).toMatchObject({ provider: 'cod', status: 'PENDING' });
      expect(
        (
          await db.paymentAttempt.findUniqueOrThrow({
            where: { id: attempt.id },
          })
        ).reviewRequired,
      ).toBe(false);
    } finally {
      config.set('MOMO_ENABLED', 'true');
    }
  });

  it('allows only payment managers to reconcile another customer and records the audit', async () => {
    const f = await unpaid('momo');
    momoCreates();
    const started = (await f.start().expect(201)).body;
    const attempt = await db.paymentAttempt.findUniqueOrThrow({
      where: { reference: started.attempt.reference },
    });
    const path = `admin/payments/orders/${f.order.id}/reconcile`;
    await call('post', path, f.accessToken)
      .send({ attemptId: attempt.id })
      .expect(403);
    await call('post', `payments/orders/${f.order.id}/reconcile`, admin).expect(
      404,
    );
    http.mockReset();
    http.mockReturnValueOnce(
      reply({
        partnerCode: 'MOMOTEST',
        orderId: attempt.reference,
        amount: TOTAL,
        resultCode: 1006,
        transId: 0,
      }),
    );
    config.set('MOMO_ENABLED', 'false');
    try {
      expect(
        (
          await call('post', path, admin)
            .send({ attemptId: attempt.id })
            .expect(201)
        ).body.paymentStatus,
      ).toBe('FAILED');
      await call('post', path, admin)
        .send({ attemptId: attempt.id })
        .expect(429);
      expect(
        await db.adminAuditEvent.count({
          where: { targetId: f.order.id, action: 'PAYMENT_RECONCILED' },
        }),
      ).toBe(1);
    } finally {
      config.set('MOMO_ENABLED', 'true');
    }
  });

  it('retains expired payments reported pending, then restores stock once after verified failure', async () => {
    const f = await unpaid('momo');
    momoCreates();
    const started = (await f.start().expect(201)).body;
    const old = new Date('1900-01-01');
    await db.order.update({
      where: { id: f.order.id },
      data: { createdAt: old, updatedAt: old },
    });
    await db.paymentAttempt.update({
      where: { reference: started.attempt.reference },
      data: { expiresAt: old, lastQueryAt: null },
    });
    const respond = (code: number) =>
      http.mockImplementation((_url, init) => {
        const body = JSON.parse(String(init!.body));
        return reply({
          partnerCode: 'MOMOTEST',
          orderId: body.orderId,
          amount: TOTAL,
          resultCode: code,
          transId: 0,
        });
      });
    http.mockReset();
    respond(1000);
    await app.get(PaymentsService).expireUnpaid(f.order.id);
    expect(
      (await db.order.findUniqueOrThrow({ where: { id: f.order.id } })).status,
    ).toBe('PENDING');
    expect(
      (
        await db.inventory.findUniqueOrThrow({
          where: { variantId: f.product.variants[0].id },
        })
      ).quantity,
    ).toBe(2);
    await db.order.update({
      where: { id: f.order.id },
      data: { updatedAt: old },
    });
    await db.paymentAttempt.update({
      where: { reference: started.attempt.reference },
      data: { lastQueryAt: null },
    });
    respond(1006);
    await app.get(PaymentsService).expireUnpaid(f.order.id);
    await app.get(PaymentsService).expireUnpaid(f.order.id);
    expect(
      (await db.order.findUniqueOrThrow({ where: { id: f.order.id } })).status,
    ).toBe('CANCELLED');
    expect(
      (
        await db.inventory.findUniqueOrThrow({
          where: { variantId: f.product.variants[0].id },
        })
      ).quantity,
    ).toBe(3);
    expect(
      await db.inventoryMovement.count({
        where: { orderId: f.order.id, reason: 'CANCEL' },
      }),
    ).toBe(1);
  });

  it('excludes classified test orders from reports while retaining their stock and history', async () => {
    const f = await unpaid('momo');
    const before = (await call('get', 'admin/summary', admin).expect(200)).body;
    const path = `admin/orders/${f.order.id}/classification`;
    await call('patch', path, f.accessToken).send({ isTest: true, expectedVersion: 0 }).expect(403);
    const changed = (await call('patch', path, admin).send({ isTest: true, expectedVersion: 0 }).expect(200)).body;
    expect(changed.isTest).toBe(true);
    expect((await call('get', 'admin/summary', admin).expect(200)).body.orders).toBe(before.orders - 1);
    expect((await call('get', `admin/orders?dataKind=test&q=${f.order.id}`, admin).expect(200)).body.total).toBe(1);
    expect((await call('get', `admin/orders?q=${f.order.id}`, admin).expect(200)).body.total).toBe(0);
    expect((await db.inventory.findUniqueOrThrow({ where: { variantId: f.product.variants[0].id } })).quantity).toBe(2);
    await call('patch', path, admin).send({ isTest: false, expectedVersion: changed.version }).expect(200);
    expect((await call('get', 'admin/summary', admin).expect(200)).body.orders).toBe(before.orders);
  });

  it('refunds a cancelled MoMo payment through the provider', async () => {
    const f = await unpaid('momo');
    momoCreates();
    const started = (await f.start().expect(201)).body;
    const ipn = momoIpn(started.attempt.reference);
    await call('post', 'payments/momo/ipn').send(ipn).expect(204);
    let order = await db.order.findUniqueOrThrow({ where: { id: f.order.id } });
    await call('post', `admin/orders/${f.order.id}/cancel`, admin)
      .send({ expectedVersion: order.version, reason: 'Wallet refund fixture' })
      .expect(201);
    const state = (
      await call('get', `admin/orders/${f.order.id}/refunds`, admin).expect(200)
    ).body;
    expect(state.provider).toBe('momo');
    const source = state.sources[0];
    expect(source).toMatchObject({ available: String(TOTAL), primary: true });
    http.mockReset();
    http.mockImplementationOnce((_url, init) => {
      const body = JSON.parse(String(init!.body)) as Record<string, unknown>;
      return reply({
        partnerCode: 'MOMOTEST',
        orderId: body.orderId,
        resultCode: 0,
        transId: nextTrans(),
        amount: body.amount,
      });
    });
    order = await db.order.findUniqueOrThrow({ where: { id: f.order.id } });
    const refund = (
      await call('post', `admin/orders/${f.order.id}/refunds`, admin)
        .send({
          requestKey: randomUUID(),
          expectedVersion: order.version,
          expectedAmount: source.available,
          paymentAttemptId: source.attemptId,
        })
        .expect(201)
    ).body;
    expect(refund).toMatchObject({ status: 'SUCCEEDED', provider: 'momo' });
    expect(String(http.mock.calls[0][0])).toBe(
      'https://test-payment.momo.vn/v2/gateway/api/refund',
    );
    expect(
      (await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } }))
        .status,
    ).toBe('REFUNDED');
  });

  it('redirects wallet returns to the storefront without changing payment state', async () => {
    const res = await call('get', 'payments/momo/return')
      .query({ orderId: 'x', resultCode: '0' })
      .expect(302);
    expect(res.headers.location).toBe(
      'http://localhost:5173/#/payments/return',
    );
    await call('get', 'payments/zalopay/return').expect(302);
  });

  it('names the order on a wallet return so the storefront can reconcile it', async () => {
    momoCreates();
    const f = await unpaid('momo');
    const state = (await f.start().expect(201)).body;
    const res = await call('get', 'payments/momo/return')
      .query({ orderId: state.attempt.reference, resultCode: '0' })
      .expect(302);
    expect(res.headers.location).toBe(
      `http://localhost:5173/#/payments/return?order=${f.order.id}`,
    );
    // A claimed success in the query string is not proof of payment.
    expect(
      (await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } }))
        .status,
    ).toBe('PENDING');
    // A reported cancel only adds a wording hint; payment state is unchanged.
    const cancelled = await call('get', 'payments/momo/return')
      .query({ orderId: state.attempt.reference, resultCode: '1006' })
      .expect(302);
    expect(cancelled.headers.location).toBe(
      `http://localhost:5173/#/payments/return?order=${f.order.id}&declined=1`,
    );
    expect(
      (await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } }))
        .status,
    ).toBe('PENDING');
    const unknown = await call('get', 'payments/zalopay/return')
      .query({ apptransid: '261121_unknownreference', status: '1' })
      .expect(302);
    expect(unknown.headers.location).toBe(
      'http://localhost:5173/#/payments/return',
    );
  });

  it('moves a pending order to another saved address and records it', async () => {
    const f = await unpaid('momo');
    const second = (
      await call('post', 'users/me/addresses', f.accessToken)
        .send({
          recipient: 'Người nhận mới',
          phone: '0912345678',
          address: '99 Đường Mới, Hà Nội',
          label: 'Công ty',
        })
        .expect(201)
    ).body;
    const moved = (
      await call('patch', `orders/${f.order.id}/address`, f.accessToken)
        .send({ addressId: second.id })
        .expect(200)
    ).body;
    expect(moved.addressSnapshot).toEqual({
      recipient: 'Người nhận mới',
      phone: '0912345678',
      address: '99 Đường Mới, Hà Nội',
    });
    expect(moved.total).toBe(f.order.total);
    const event = await db.orderEvent.findFirstOrThrow({
      where: { orderId: f.order.id },
      orderBy: { version: 'desc' },
    });
    expect(event).toMatchObject({ status: 'PENDING', version: moved.version });
    expect(event.note).toContain('99 Đường Mới');
    // Another customer's address is never accepted.
    const other = await customer();
    const foreign = (
      await call('post', 'users/me/addresses', other.accessToken)
        .send({ recipient: 'Khác', phone: '0987654321', address: '1 Nơi khác' })
        .expect(201)
    ).body;
    await call('patch', `orders/${f.order.id}/address`, f.accessToken)
      .send({ addressId: foreign.id })
      .expect(404);
    await f.cancel().expect(201);
    expect(
      (
        await call('patch', `orders/${f.order.id}/address`, f.accessToken)
          .send({ addressId: second.id })
          .expect(409)
      ).body.error.code,
    ).toBe('ORDER_STATE_CONFLICT');
  });

  it('switches the payment method only once an open link has closed', async () => {
    const f = await unpaid('momo');
    momoCreates();
    const started = (await f.start().expect(201)).body;
    const pending = () =>
      reply({
        partnerCode: 'MOMOTEST',
        orderId: started.attempt.reference,
        amount: TOTAL,
        resultCode: 1000,
        transId: 0,
      });
    const change = (paymentMethod: string) =>
      call('patch', `payments/orders/${f.order.id}/method`, f.accessToken).send(
        { paymentMethod },
      );
    http.mockReset();
    http.mockImplementation(pending);
    expect((await change('cod').expect(409)).body.error.code).toBe(
      'PAYMENT_IN_PROGRESS',
    );
    expect(
      (await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } }))
        .provider,
    ).toBe('momo');
    await db.paymentAttempt.update({
      where: { reference: started.attempt.reference },
      data: { expiresAt: new Date(Date.now() - 1000) },
    });
    await change('cod').expect(409); // Local expiry is not proof of closure.
    http.mockImplementation(() =>
      reply({
        partnerCode: 'MOMOTEST',
        orderId: started.attempt.reference,
        amount: TOTAL,
        resultCode: 1005,
        transId: 0,
      }),
    );
    const switched = (await change('cod').expect(200)).body;
    expect(switched.payment).toMatchObject({
      provider: 'cod',
      status: 'PENDING',
    });
    expect(
      (
        await db.paymentAttempt.findUniqueOrThrow({
          where: { reference: started.attempt.reference },
        })
      ).status,
    ).toBe('CANCELLED');
    const event = await db.orderEvent.findFirstOrThrow({
      where: { orderId: f.order.id },
      orderBy: { version: 'desc' },
    });
    expect(event.note).toBe('Khách đổi phương thức thanh toán: MoMo → COD');
    http.mockReset();
    expect((await change('zalopay').expect(200)).body.payment.provider).toBe(
      'zalopay',
    );
    expect(http).not.toHaveBeenCalled();
    await change('bank').expect(400);
  });

  it('refuses to switch the method of an order the gateway reports as paid', async () => {
    const f = await unpaid('momo');
    momoCreates();
    const started = (await f.start().expect(201)).body;
    http.mockReset();
    http.mockReturnValueOnce(
      reply({
        partnerCode: 'MOMOTEST',
        orderId: started.attempt.reference,
        amount: TOTAL,
        resultCode: 0,
        transId: nextTrans(),
      }),
    );
    const res = await call(
      'patch',
      `payments/orders/${f.order.id}/method`,
      f.accessToken,
    )
      .send({ paymentMethod: 'cod' })
      .expect(409);
    expect(res.body.error.code).toBe('PAYMENT_ALREADY_SETTLED');
    expect(
      (await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } }))
        .status,
    ).toBe('PAID');
  });

  it('stores a map pin with the address and carries it into the order', async () => {
    const f = await unpaid('momo');
    const pin = { latitude: 21.0285, longitude: 105.8542 };
    await call('post', 'users/me/addresses', f.accessToken)
      .send({
        recipient: 'Khách',
        phone: '0912345678',
        address: '79 Đinh Tiên Hoàng, Hà Nội',
        latitude: 21.0285,
      })
      .expect(400);
    const pinned = (
      await call('post', 'users/me/addresses', f.accessToken)
        .send({
          recipient: 'Khách',
          phone: '0912345678',
          address: '79 Đinh Tiên Hoàng, Hà Nội',
          ...pin,
        })
        .expect(201)
    ).body;
    expect(pinned).toMatchObject(pin);
    const moved = (
      await call('patch', `orders/${f.order.id}/address`, f.accessToken)
        .send({ addressId: pinned.id })
        .expect(200)
    ).body;
    expect(moved.addressSnapshot).toMatchObject(pin);
    // Clearing the pin needs both coordinates set to null.
    const cleared = (
      await call('patch', `users/me/addresses/${pinned.id}`, f.accessToken)
        .send({ latitude: null, longitude: null })
        .expect(200)
    ).body;
    expect(cleared).toMatchObject({ latitude: null, longitude: null });
    await call('get', 'geo/suggest?q=Nguyen%20Hue').expect(401);
  });
});
