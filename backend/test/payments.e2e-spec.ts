import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import request from 'supertest';
import { createHmac, randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

const secret = 'sandbox-fixture-secret-not-a-credential';
const signature = (s: string) =>
  createHmac('sha512', secret).update(s).digest('hex');
function ipn(
  reference: string,
  patch: Record<string, string> = {},
): Record<string, string> {
  const body: Record<string, string> = {
    vnp_TmnCode: 'TEST0001',
    vnp_TxnRef: reference,
    vnp_Amount: '52000000',
    vnp_TransactionNo: String(Math.floor(Math.random() * 1e12) + 1),
    vnp_ResponseCode: '00',
    vnp_TransactionStatus: '00',
    ...patch,
  };
  const query = new URLSearchParams();
  Object.keys(body)
    .sort()
    .forEach((key) => query.set(key, body[key]));
  return { ...body, vnp_SecureHash: signature(query.toString()) };
}
function queryReply(reference: string, patch: Record<string, string> = {}) {
  const fields = [
    'vnp_ResponseId',
    'vnp_Command',
    'vnp_ResponseCode',
    'vnp_Message',
    'vnp_TmnCode',
    'vnp_TxnRef',
    'vnp_Amount',
    'vnp_BankCode',
    'vnp_PayDate',
    'vnp_TransactionNo',
    'vnp_TransactionType',
    'vnp_TransactionStatus',
    'vnp_OrderInfo',
    'vnp_PromotionCode',
    'vnp_PromotionAmount',
  ];
  const body: Record<string, string> = {
    vnp_ResponseId: randomUUID().replaceAll('-', ''),
    vnp_Command: 'querydr',
    vnp_ResponseCode: '00',
    vnp_Message: 'Success',
    vnp_TmnCode: 'TEST0001',
    vnp_TxnRef: reference,
    vnp_Amount: '52000000',
    vnp_BankCode: 'NCB',
    vnp_PayDate: '20261021120000',
    vnp_TransactionNo: String(Math.floor(Math.random() * 1e12) + 1),
    vnp_TransactionType: '01',
    vnp_TransactionStatus: '00',
    vnp_OrderInfo: 'Test',
    vnp_PromotionCode: '',
    vnp_PromotionAmount: '',
    ...patch,
  };
  return {
    ...body,
    vnp_SecureHash: signature(fields.map((k) => body[k]).join('|')),
  };
}
describe('VNPay sandbox workflow with PostgreSQL and signed transport fixtures', () => {
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
      .overrideProvider('VNPAY_HTTP')
      .useValue(http)
      .compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    config = app.get(ConfigService);
    Object.entries({
      VNPAY_ENABLED: 'true',
      VNPAY_TMN_CODE: 'TEST0001',
      VNPAY_HASH_SECRET: secret,
      VNPAY_RETURN_URL: 'http://localhost:3000/api/v1/payments/vnpay/return',
      VNPAY_WEB_RETURN_URL: 'http://localhost:5173/#/payments/return',
    }).forEach(([k, v]) => config.set(k, v));
    const a = await customer();
    await db.user.update({ where: { id: a.user.id }, data: { role: 'ADMIN' } });
    admin = (
      await call('post', 'auth/login')
        .send({ email: a.user.email, password: 'Payment-Test-password-2026' })
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
          name: 'Payment fixture',
          email: randomUUID() + '@example.test',
          password: 'Payment-Test-password-2026',
        })
        .expect(201)
    ).body;
  }
  async function fixture() {
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
      where: { slug: 'payments-test' },
      create: { slug: 'payments-test', name: 'Payments test' },
      update: {},
    });
    const brand = await db.brand.upsert({
      where: { slug: 'payments-test' },
      create: { slug: 'payments-test', name: 'Payments test' },
      update: {},
    });
    const sku = 'payments-' + randomUUID();
    const product = await db.product.create({
      data: {
        slug: sku,
        name: 'Payment fixture',
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
      include: { variants: { include: { inventory: true } } },
    });
    await call('post', 'cart/items', c.accessToken)
      .send({ sku, quantity: 1 })
      .expect(201);
    const body = {
      addressId: address.id,
      shippingMethod: 'standard',
      expectedSubtotal: '490000',
      paymentMethod: 'vnpay',
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
  async function unpaid() {
    const f = await fixture(),
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
  const callback = (body: Record<string, string>) =>
    call('get', 'payments/vnpay/ipn').query(body).expect(200);
  it('leaves COD usable and stock/cart untouched when sandbox is disabled', async () => {
    const f = await fixture();
    config.set('VNPAY_ENABLED', 'false');
    try {
      expect(
        (await call('get', 'payments/methods').expect(200)).body,
      ).toMatchObject({ cod: true, vnpay: false, sandbox: true });
      expect((await f.create().expect(503)).body.error.code).toBe(
        'PAYMENT_UNAVAILABLE',
      );
      expect(
        (
          await db.inventory.findUniqueOrThrow({
            where: { variantId: f.product.variants[0].id },
          })
        ).quantity,
      ).toBe(3);
      expect(
        (await call('get', 'cart', f.accessToken).expect(200)).body.items,
      ).toHaveLength(1);
      await call('post', 'orders', f.accessToken)
        .set('Idempotency-Key', f.key)
        .send({ ...f.body, paymentMethod: 'cod' })
        .expect(201);
    } finally {
      config.set('VNPAY_ENABLED', 'true');
    }
  });
  it('includes the payment method in idempotency and enforces ownership', async () => {
    const f = await unpaid(),
      other = await customer();
    expect(f.order.payment).toMatchObject({
      provider: 'vnpay',
      status: 'PENDING',
    });
    expect((await f.create().expect(201)).body.id).toBe(f.order.id);
    await call('post', 'orders', f.accessToken)
      .set('Idempotency-Key', f.key)
      .send({ ...f.body, paymentMethod: 'cod' })
      .expect(409);
    for (const action of ['start', 'reconcile']) {
      await call('post', `payments/orders/${f.order.id}/${action}`).expect(401);
      await call(
        'post',
        `payments/orders/${f.order.id}/${action}`,
        other.accessToken,
      ).expect(404);
      await call(
        'post',
        `payments/orders/${f.order.id}/${action}`,
        admin,
      ).expect(404);
    }
  });
  it('reuses one attempt under concurrency and blocks cancellation/admin confirmation while unpaid', async () => {
    const f = await unpaid();
    const starts = await Promise.all([f.start(), f.start(), f.start()]);
    expect(starts.map((r) => r.status)).toEqual([201, 201, 201]);
    expect(new Set(starts.map((r) => r.body.attempt.reference)).size).toBe(1);
    const link = new URL(starts[0].body.checkoutUrl);
    expect(link.hostname).toBe('sandbox.vnpayment.vn');
    expect(link.searchParams.get('vnp_Amount')).toBe('52000000');
    await f.cancel().expect(409);
    await call('patch', `admin/orders/${f.order.id}/status`, admin)
      .send({ status: 'CONFIRMED', expectedVersion: 0 })
      .expect(409);
    expect(
      (
        await db.inventory.findUniqueOrThrow({
          where: { variantId: f.product.variants[0].id },
        })
      ).quantity,
    ).toBe(2);
  });
  it('rejects forged/wrong-amount callbacks; browser return never settles; replay settles once', async () => {
    const f = await unpaid(),
      state = (await f.start().expect(201)).body,
      signed = ipn(state.attempt.reference);
    expect(
      (await callback({ ...signed, vnp_Amount: '100' })).body.RspCode,
    ).toBe('97');
    expect(
      (await callback(ipn(state.attempt.reference, { vnp_Amount: '100' }))).body
        .RspCode,
    ).toBe('04');
    expect(
      (await callback(ipn(randomUUID().replaceAll('-', '')))).body.RspCode,
    ).toBe('01');
    await call('get', 'payments/vnpay/return')
      .query({ ...signed, vnp_SecureHash: 'bad' })
      .expect(400);
    const returned = await call('get', 'payments/vnpay/return')
      .query(signed)
      .expect(302);
    expect(returned.headers.location).toBe(
      'http://localhost:5173/#/payments/return',
    );
    expect(
      (await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } }))
        .status,
    ).toBe('PENDING');
    const result = await Promise.all([callback(signed), callback(signed)]);
    expect(result.map((r) => r.body.RspCode).sort()).toEqual(['00', '02']);
    const order = await db.order.findUniqueOrThrow({
      where: { id: f.order.id },
      include: { payment: true },
    });
    expect(order.payment).toMatchObject({
      status: 'PAID',
      providerTransactionId: signed.vnp_TransactionNo,
    });
    expect(order.version).toBe(1);
    expect((await f.start().expect(201)).body.checkoutUrl).toBeNull();
    await call('patch', `admin/orders/${f.order.id}/status`, admin)
      .send({ status: 'CONFIRMED', expectedVersion: 1 })
      .expect(200);
    await f.cancel().expect(409);
    expect(
      await db.inventoryMovement.count({ where: { orderId: f.order.id } }),
    ).toBe(1);
  });
  it('supports failed-payment retry, retains late/double success for admin review', async () => {
    const f = await unpaid(),
      a = (await f.start().expect(201)).body.attempt;
    await callback(
      ipn(a.reference, {
        vnp_ResponseCode: '24',
        vnp_TransactionStatus: '02',
        vnp_TransactionNo: '0',
      }),
    );
    const b = (await f.start().expect(201)).body.attempt;
    expect(b.reference).not.toBe(a.reference);
    await callback(ipn(b.reference));
    await callback(ipn(a.reference));
    const rows = await db.$queryRaw<
      Array<{ status: string; reviewRequired: boolean }>
    >`SELECT a.status, a."reviewRequired" FROM "PaymentAttempt" a JOIN "Payment" p ON p.id=a."paymentId" WHERE p."orderId"=${f.order.id}::uuid`;
    expect(rows.filter((r) => r.status === 'PAID')).toHaveLength(2);
    expect(rows.filter((r) => r.reviewRequired)).toHaveLength(1);
    expect(
      await db.inventoryMovement.count({ where: { orderId: f.order.id } }),
    ).toBe(1);
  });
  it('reconciles signed provider results for loopback operation and rejects forged responses', async () => {
    const f = await unpaid(),
      a = (await f.start().expect(201)).body.attempt;
    http.mockImplementationOnce(async () =>
      Response.json({ ...queryReply(a.reference), vnp_Amount: '100' }),
    );
    await f.reconcile().expect(503);
    expect(
      (await db.payment.findUniqueOrThrow({ where: { orderId: f.order.id } }))
        .status,
    ).toBe('PENDING');
    await db.$executeRaw`UPDATE "PaymentAttempt" SET "lastQueryAt"=NULL WHERE reference=${a.reference}`;
    http.mockImplementationOnce(async () =>
      Response.json(queryReply(a.reference)),
    );
    expect((await f.reconcile().expect(201)).body.paymentStatus).toBe('PAID');
    expect(http).toHaveBeenCalledTimes(2);
  });
  it('still queries an outstanding attempt when an earlier attempt succeeds late', async () => {
    const f = await unpaid(),
      a = (await f.start().expect(201)).body.attempt;
    await callback(
      ipn(a.reference, {
        vnp_ResponseCode: '24',
        vnp_TransactionStatus: '02',
        vnp_TransactionNo: '0',
      }),
    );
    const b = (await f.start().expect(201)).body.attempt;
    await callback(ipn(a.reference));
    http.mockImplementationOnce(async () =>
      Response.json(queryReply(b.reference)),
    );
    const result = (await f.reconcile().expect(201)).body;
    expect(http).toHaveBeenCalledTimes(1);
    expect(result.reviewRequired).toBe(true);
    const orders = (
      await call('get', 'admin/orders?limit=100', admin).expect(200)
    ).body.items;
    expect(
      orders.find((o: { id: string }) => o.id === f.order.id).payment.attempts,
    ).toHaveLength(2);
  });
  it('requires verified expiry before retry/cancel and records a later success without restoring stock twice', async () => {
    const f = await unpaid(),
      a = (await f.start().expect(201)).body.attempt;
    await db.$executeRaw`UPDATE "PaymentAttempt" SET "expiresAt"=NOW()-INTERVAL '1 minute' WHERE reference=${a.reference}`;
    await f.start().expect(409);
    await f.cancel().expect(409);
    http.mockImplementationOnce(async () =>
      Response.json(queryReply(a.reference, { vnp_ResponseCode: '91' })),
    );
    expect((await f.reconcile().expect(201)).body.attempt.status).toBe(
      'CANCELLED',
    );
    await f.cancel().expect(201);
    await callback(ipn(a.reference));
    const order = await db.order.findUniqueOrThrow({
      where: { id: f.order.id },
      include: { payment: true },
    });
    expect(order.status).toBe('CANCELLED');
    expect(order.payment!.status).toBe('PAID');
    const rows = await db.$queryRaw<
      Array<{ reviewRequired: boolean }>
    >`SELECT "reviewRequired" FROM "PaymentAttempt" WHERE reference=${a.reference}`;
    expect(rows[0].reviewRequired).toBe(true);
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
  it('rejects transaction reuse across orders and payment/cancel races cannot lose money', async () => {
    const f = await unpaid(),
      g = await unpaid();
    const a = (await f.start().expect(201)).body.attempt,
      b = (await g.start().expect(201)).body.attempt;
    const first = ipn(a.reference);
    await callback(first);
    expect(
      (
        await callback(
          ipn(b.reference, { vnp_TransactionNo: first.vnp_TransactionNo }),
        )
      ).body.RspCode,
    ).toBe('99');
    expect(
      (await db.payment.findUniqueOrThrow({ where: { orderId: g.order.id } }))
        .status,
    ).toBe('PENDING');
    const paid = ipn(b.reference);
    const [cancel, payment] = await Promise.all([g.cancel(), callback(paid)]);
    expect([201, 409]).toContain(cancel.status);
    expect(payment.body.RspCode).toBe('00');
    expect(
      (await db.payment.findUniqueOrThrow({ where: { orderId: g.order.id } }))
        .status,
    ).toBe('PAID');
    expect((await db.order.findUniqueOrThrow({ where: { id: g.order.id } })).status).toBe(cancel.status === 201 ? 'CANCELLED' : 'PENDING');
    expect(await db.inventoryMovement.count({ where: { orderId: g.order.id, reason: 'CANCEL' } })).toBe(cancel.status === 201 ? 1 : 0);
  });
});
