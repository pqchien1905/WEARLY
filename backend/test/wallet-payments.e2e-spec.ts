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
  let app: INestApplication, db: PrismaService, config: ConfigService, admin: string;
  const http = jest.fn<ReturnType<typeof fetch>, Parameters<typeof fetch>>();
  const call = (method: 'get' | 'post' | 'patch', path: string, token?: string) => {
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
      ZALOPAY_RETURN_URL: 'http://localhost:3000/api/v1/payments/zalopay/return',
      ZALOPAY_CALLBACK_URL: 'http://localhost:3000/api/v1/payments/zalopay/callback',
    }).forEach(([k, v]) => config.set(k, v));
    const a = await customer();
    await db.user.update({ where: { id: a.user.id }, data: { role: 'ADMIN' } });
    admin = (
      await call('post', 'auth/admin/login')
        .send({ username: a.user.username, password: 'Wallet-Test-password-2026' })
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
        .send({ recipient: 'Customer', phone: '0901234567', address: '12 Test Street', label: 'Home', isDefault: true })
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
    await call('post', 'cart/items', c.accessToken).send({ sku, quantity: 1 }).expect(201);
    const body = { addressId: address.id, shippingMethod: 'standard', expectedSubtotal: '490000', paymentMethod };
    const key = randomUUID();
    return {
      ...c,
      product,
      body,
      key,
      create: () => call('post', 'orders', c.accessToken).set('Idempotency-Key', key).send(body),
    };
  }
  async function unpaid(paymentMethod: 'momo' | 'zalopay') {
    const f = await fixture(paymentMethod),
      order = (await f.create().expect(201)).body;
    return {
      ...f,
      order,
      start: () => call('post', `payments/orders/${order.id}/start`, f.accessToken),
      reconcile: () => call('post', `payments/orders/${order.id}/reconcile`, f.accessToken),
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
        payUrl: 'https://test-payment.momo.vn/v2/gateway/pay?t=' + String(body.orderId),
      });
    });
  }
  const confirm = (order: { id: string }, version: number) =>
    call('patch', `admin/orders/${order.id}/status`, admin).send({ status: 'CONFIRMED', expectedVersion: version });

  it('reports wallet availability and keeps stock when a wallet is disabled', async () => {
    expect((await call('get', 'payments/methods').expect(200)).body).toMatchObject({
      cod: true,
      momo: true,
      zalopay: true,
      sandbox: true,
    });
    const f = await fixture('momo');
    config.set('MOMO_ENABLED', 'false');
    try {
      expect((await call('get', 'payments/methods').expect(200)).body.momo).toBe(false);
      expect((await f.create().expect(503)).body.error.code).toBe('PAYMENT_UNAVAILABLE');
      const inv = await db.inventory.findUniqueOrThrow({ where: { variantId: f.product.variants[0].id } });
      expect(inv.quantity).toBe(3);
    } finally {
      config.set('MOMO_ENABLED', 'true');
    }
    const order = (await f.create().expect(201)).body;
    expect(order.payment).toMatchObject({ provider: 'momo', status: 'PENDING' });
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
    expect(first.checkoutUrl).toBe('https://test-payment.momo.vn/v2/gateway/pay?t=' + first.attempt.reference);
    expect(http).toHaveBeenCalledTimes(1);
    const again = (await f.start().expect(201)).body;
    expect(again.attempt.reference).toBe(first.attempt.reference);
    expect(http).toHaveBeenCalledTimes(1);
    // Unpaid online orders cannot be confirmed or cancelled before verification.
    expect((await confirm(f.order, f.order.version).expect(409)).body.error.code).toBe('PAYMENT_REQUIRED');
    expect((await f.cancel().expect(409)).body.error.code).toBe('PAYMENT_RECONCILIATION_REQUIRED');
    // Forged and mismatched notifications change nothing.
    await call('post', 'payments/momo/ipn').send({ ...momoIpn(first.attempt.reference), signature: 'f'.repeat(64) }).expect(400);
    await call('post', 'payments/momo/ipn').send(momoIpn(first.attempt.reference, { amount: 1000 })).expect(204);
    expect((await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } })).status).toBe('PENDING');
    const ipn = momoIpn(first.attempt.reference);
    await call('post', 'payments/momo/ipn').send(ipn).expect(204);
    await call('post', 'payments/momo/ipn').send(ipn).expect(204);
    const payment = await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id }, include: { attempts: true } });
    expect(payment).toMatchObject({ status: 'PAID', providerTransactionId: String(ipn.transId) });
    expect(payment.attempts).toHaveLength(1);
    const order = await db.order.findUniqueOrThrow({ where: { id: f.order.id } });
    await confirm(order, order.version).expect(200);
    expect(
      await db.mailOutbox.count({ where: { orderId: f.order.id, eventKey: 'momo-paid:' + payment.attempts[0].id } }),
    ).toBe(1);
  });

  it('cancels an unissued attempt when MoMo is unavailable and lets the customer retry', async () => {
    const f = await unpaid('momo');
    http.mockRejectedValueOnce(new Error('network'));
    expect((await f.start().expect(503)).body.error.code).toBe('PAYMENT_PROVIDER_UNAVAILABLE');
    const failed = await db.paymentAttempt.findMany({ where: { payment: { orderId: f.order.id } } });
    expect(failed.map((a) => [a.status, a.checkoutUrl])).toEqual([['CANCELLED', null]]);
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
      reply({ partnerCode: 'MOMOTEST', orderId: started.attempt.reference, amount: TOTAL, resultCode: 1006, transId: 0 }),
    );
    const state = (await f.reconcile().expect(201)).body;
    expect(state).toMatchObject({ paymentStatus: 'FAILED', checkoutUrl: null });
    expect((await f.reconcile().expect(429)).body.error.code).toBe('PAYMENT_QUERY_RATE_LIMITED');
    await f.cancel().expect(201);
    const inv = await db.inventory.findUniqueOrThrow({ where: { variantId: f.product.variants[0].id } });
    expect(inv.quantity).toBe(3);
  });

  it('confirms ZaloPay callbacks signed with key2 only', async () => {
    const f = await unpaid('zalopay');
    http.mockReturnValueOnce(reply({ return_code: 1, order_url: 'https://qcgateway.zalopay.vn/openinapp?order=fixture' }));
    const started = (await f.start().expect(201)).body;
    expect(started).toMatchObject({ provider: 'zalopay', checkoutUrl: 'https://qcgateway.zalopay.vn/openinapp?order=fixture' });
    expect(started.attempt.reference).toMatch(/^\d{6}_[a-f0-9]{24}$/);
    const forged = zaloCallback(started.attempt.reference);
    expect(
      (await call('post', 'payments/zalopay/callback').send({ ...forged, mac: sha256(key1, forged.data) }).expect(200)).body,
    ).toMatchObject({ return_code: -1 });
    expect(
      (await call('post', 'payments/zalopay/callback').send(zaloCallback(started.attempt.reference)).expect(200)).body,
    ).toMatchObject({ return_code: 1 });
    expect((await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } })).status).toBe('PAID');
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
    const state = (await call('get', `admin/orders/${f.order.id}/refunds`, admin).expect(200)).body;
    expect(state.provider).toBe('momo');
    const source = state.sources[0];
    expect(source).toMatchObject({ available: String(TOTAL), primary: true });
    http.mockReset();
    http.mockImplementationOnce((_url, init) => {
      const body = JSON.parse(String(init!.body)) as Record<string, unknown>;
      return reply({ partnerCode: 'MOMOTEST', orderId: body.orderId, resultCode: 0, transId: nextTrans(), amount: body.amount });
    });
    order = await db.order.findUniqueOrThrow({ where: { id: f.order.id } });
    const refund = (
      await call('post', `admin/orders/${f.order.id}/refunds`, admin)
        .send({ requestKey: randomUUID(), expectedVersion: order.version, expectedAmount: source.available, paymentAttemptId: source.attemptId })
        .expect(201)
    ).body;
    expect(refund).toMatchObject({ status: 'SUCCEEDED', provider: 'momo' });
    expect(String(http.mock.calls[0][0])).toBe('https://test-payment.momo.vn/v2/gateway/api/refund');
    expect((await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } })).status).toBe('REFUNDED');
  });

  it('redirects wallet returns to the storefront without changing payment state', async () => {
    const res = await call('get', 'payments/momo/return').query({ orderId: 'x', resultCode: '0' }).expect(302);
    expect(res.headers.location).toBe('http://localhost:5173/#/payments/return');
    await call('get', 'payments/zalopay/return').expect(302);
  });
});
