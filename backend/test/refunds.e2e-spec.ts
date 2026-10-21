import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID, createHmac } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { VnpayProvider } from '../src/integrations/payments/vnpay.provider';
import * as audit from '../src/modules/admin/audit';

describe('Explicit source-scoped refunds', () => {
  let app: INestApplication,
    db: PrismaService,
    admin: string,
    buyer: string,
    stranger: string,
    actorId: string,
    userId: string,
    variantId: string;
  const secret = 'refund-fixture-secret';
  const runNumber = BigInt(Date.now()) * 100n;
  let sequence = 10;
  const numberFor = (n: number) => (runNumber + BigInt(n)).toString();
  const nextNumber = () => numberFor(sequence++);
  const gateway = new VnpayProvider(
    new ConfigService({
      VNPAY_ENABLED: 'true',
      VNPAY_TMN_CODE: 'TEST0001',
      VNPAY_HASH_SECRET: secret,
    }),
    async () => {
      throw Error('No real provider calls in E2E');
    },
  );
  const send = jest.spyOn(gateway, 'refund'),
    query = jest.spyOn(gateway, 'queryRefund');
  const call = (method: 'get' | 'post', path: string, token = admin) =>
    request(app.getHttpServer())
      [method]('/api/v1/' + path)
      .auth(token, { type: 'bearer' });
  beforeAll(async () => {
    if (
      !new URL(
        process.env.TEST_DATABASE_URL ?? 'http://invalid',
      ).pathname.endsWith('_test')
    )
      throw Error('Test DB required');
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    process.env.NODE_ENV = 'test';
    process.env.JWT_ACCESS_SECRET = 'test-access-'.repeat(5);
    process.env.JWT_REFRESH_SECRET = 'test-refresh-'.repeat(5);
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(VnpayProvider)
      .useValue(gateway)
      .compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    const people = [];
    for (let i = 0; i < 3; i++)
      people.push(
        (
          await call('post', 'auth/register', '')
            .send({
              name: 'Refund fixture',
              email: randomUUID() + '@example.test',
              password: 'Refunds-password-2026',
            })
            .expect(201)
        ).body,
      );
    [admin, buyer, stranger] = people.map((p) => p.accessToken);
    actorId = people[0].user.id;
    userId = people[1].user.id;
    await db.user.update({ where: { id: actorId }, data: { role: 'ADMIN' } });
    const slug = 'refunds-' + randomUUID();
    const p = await db.product.create({
      data: {
        slug,
        name: slug,
        description: '',
        style: '',
        material: '',
        category: { create: { slug, name: slug } },
        brand: { create: { slug, name: slug } },
        variants: {
          create: {
            sku: slug,
            price: '100',
            color: 'Black',
            colorHex: '#000000',
            size: 'M',
            inventory: { create: { quantity: 100 } },
          },
        },
      },
      include: { variants: true },
    });
    variantId = p.variants[0].id;
  });
  beforeEach(() => {
    send.mockReset();
    query.mockReset();
    send.mockResolvedValue({
      status: 'SUCCEEDED',
      transactionNo: nextNumber(),
    });
  });
  afterAll(async () => {
    if (app) await app.close();
  });
  async function fixture(provider = 'cod', cancelled = true) {
    const number = nextNumber();
    return db.order.create({
      data: {
        userId,
        idempotencyKey: randomUUID(),
        requestHash: 'refund-fixture',
        status: cancelled ? 'CANCELLED' : 'DELIVERED',
        addressSnapshot: {},
        subtotal: '200',
        shipping: '30',
        total: '230',
        items: {
          create: {
            variantId,
            name: 'Refund fixture',
            sku: 'sku',
            slug: 'slug',
            size: 'M',
            color: 'Black',
            image: '',
            unitPrice: '100',
            quantity: 2,
          },
        },
        history: {
          create: {
            status: cancelled ? 'CANCELLED' : 'DELIVERED',
            actorId,
            version: 0,
          },
        },
        payment: {
          create: {
            provider,
            status: 'PAID',
            amount: '230',
            ...(provider === 'cod'
              ? {
                  settlement: {
                    create: { actorId, amount: '230', reference: randomUUID() },
                  },
                }
              : {
                  providerTransactionId: number,
                  attempts: {
                    create: {
                      reference: randomUUID().replaceAll('-', ''),
                      amount: '230',
                      status: 'PAID',
                      transactionNo: number,
                      ipAddress: '127.0.0.1',
                      expiresAt: new Date(Date.now() + 900000),
                    },
                  },
                }),
          },
        },
      },
      include: { payment: { include: { attempts: true } }, items: true },
    });
  }
  const state = (id: string, token = admin) =>
    call('get', `admin/orders/${id}/refunds`, token);
  const create = (id: string, body: object, token = admin) =>
    call('post', `admin/orders/${id}/refunds`, token).send(body);
  function payload(row: Awaited<ReturnType<typeof fixture>>, patch = {}) {
    return {
      requestKey: randomUUID().toUpperCase(),
      expectedVersion: 0,
      expectedAmount: '230',
      ...(row.payment!.provider === 'cod'
        ? { reference: randomUUID() }
        : { paymentAttemptId: row.payment!.attempts[0].id }),
      ...patch,
    };
  }
  async function received(row: Awaited<ReturnType<typeof fixture>>) {
    const r = (
      await call('post', `orders/${row.id}/returns`, buyer)
        .send({
          requestKey: randomUUID(),
          reason: 'Không vừa kích thước',
          items: [{ orderItemId: row.items[0].id, quantity: 1 }],
        })
        .expect(201)
    ).body;
    await call('post', `admin/orders/${row.id}/returns/${r.id}/decision`)
      .send({ status: 'APPROVED', expectedVersion: 0 })
      .expect(201);
    await call('post', `admin/orders/${row.id}/returns/${r.id}/receive`)
      .send({ expectedVersion: 1 })
      .expect(201);
  }
  it('authorizes owner history and admin execution; bounds versions, amounts and sources', async () => {
    const row = await fixture(),
      body = payload(row);
    await call('get', `orders/${row.id}/refunds`, stranger).expect(404);
    await state(row.id, buyer).expect(403);
    await create(row.id, body, buyer).expect(403);
    await create(row.id, { ...body, expectedAmount: '231' }).expect(409);
    await create(row.id, { ...body, expectedVersion: 1 }).expect(409);
    await create(row.id, { ...body, expectedAmount: '1.1' }).expect(400);
    await create(row.id, { ...body, paymentAttemptId: randomUUID() }).expect(
      409,
    );
    const p = (await call('get', `orders/${row.id}/refunds`, buyer).expect(200))
      .body;
    expect(p.sources).toBeUndefined();
    expect(p.refunded).toBe('0');
  });
  it('records COD receipt once under concurrent replay and preserves stock', async () => {
    const row = await fixture(),
      body = payload(row);
    const before = (await call('get', 'admin/summary').expect(200)).body;
    const stock = (
      await db.inventory.findUniqueOrThrow({ where: { variantId } })
    ).quantity;
    const result = await Promise.all([
      create(row.id, body),
      create(row.id, body),
    ]);
    expect(result.map((r) => r.status)).toEqual([201, 201]);
    expect(result[0].body.id).toBe(result[1].body.id);
    expect(result[0].body.status).toBe('SUCCEEDED');
    const notices = await db.mailOutbox.findMany({
      where: { orderId: row.id },
    });
    expect(notices).toHaveLength(1);
    expect(notices[0].eventKey).toBe('refund:' + result[0].body.id);
    expect(notices[0].body).toContain('230 VND');
    await create(row.id, { ...body, reference: 'changed' }).expect(409);
    await create(row.id, payload(row, { expectedVersion: 1 })).expect(409);
    expect(
      (await db.payment.findUniqueOrThrow({ where: { id: row.payment!.id } }))
        .status,
    ).toBe('REFUNDED');
    expect(
      (await db.inventory.findUniqueOrThrow({ where: { variantId } })).quantity,
    ).toBe(stock);
    const history = (
      await call('get', `orders/${row.id}/refunds`, buyer).expect(200)
    ).body;
    expect(history.refunded).toBe('230');
    expect(history.refunds).toHaveLength(1);
    expect(history.refunds[0].actorId).toBeUndefined();
    expect(history.refunds[0].payloadHash).toBeUndefined();
    const other = await fixture();
    await create(
      other.id,
      payload(other, { reference: 'reference' in body ? body.reference : '' }),
    ).expect(409);
    expect(send).not.toHaveBeenCalled();
    const after = (await call('get', 'admin/summary').expect(200)).body;
    expect(BigInt(after.refundedVnd) - BigInt(before.refundedVnd)).toBe(230n);
    // The other fixture above adds a second collection of230; the first refund removes230.
    expect(BigInt(after.netCollectedVnd) - BigInt(before.netCollectedVnd)).toBe(
      0n,
    );
  });
  it('rolls back COD receipt and payment when audit fails', async () => {
    const row = await fixture(),
      body = payload(row),
      spy = jest
        .spyOn(audit, 'recordAdminActivity')
        .mockRejectedValueOnce(Error('audit failure'));
    try {
      await create(row.id, body).expect(500);
    } finally {
      spy.mockRestore();
    }
    expect((await state(row.id).expect(200)).body.refunds).toHaveLength(0);
    expect(
      (await db.payment.findUniqueOrThrow({ where: { id: row.payment!.id } }))
        .status,
    ).toBe('PAID');
    await create(row.id, body).expect(201);
  });
  it('supports sequential partial returns after refund and retains shipping', async () => {
    const row = await fixture('cod', false);
    await create(row.id, payload(row)).expect(409);
    await received(row);
    let s = (await state(row.id).expect(200)).body;
    await create(
      row.id,
      payload(row, { expectedVersion: s.version, expectedAmount: '100' }),
    ).expect(201);
    expect(
      (await db.payment.findUniqueOrThrow({ where: { id: row.payment!.id } }))
        .status,
    ).toBe('PARTIALLY_REFUNDED');
    await received(row);
    s = (await state(row.id).expect(200)).body;
    await create(
      row.id,
      payload(row, { expectedVersion: s.version, expectedAmount: '100' }),
    ).expect(201);
    s = (await state(row.id).expect(200)).body;
    expect(s.sources[0]).toMatchObject({
      available: '0',
      entitled: '200',
      refunded: '200',
      collected: '230',
    });
    expect(s.paymentStatus).toBe('PARTIALLY_REFUNDED');
    expect(s.refunded).toBe('200');
  });
  it('never resends a persisted VNPay refund after lost response or concurrent retry', async () => {
    const row = await fixture('vnpay'),
      body = payload(row);
    send.mockRejectedValueOnce(Error('Lost response after provider accepted'));
    const results = await Promise.all([
      create(row.id, body),
      create(row.id, body),
    ]);
    expect(results.map((r) => r.status)).toEqual([201, 201]);
    expect(send).toHaveBeenCalledTimes(1);
    const s = (await state(row.id).expect(200)).body;
    expect(s.refunds[0].status).toBe('REVIEW');
    expect(
      await db.mailOutbox.count({
        where: { orderId: row.id, eventKey: { startsWith: 'refund:' } },
      }),
    ).toBe(0);
    expect(s.sources[0].available).toBe('0');
    await create(row.id, body).expect(201);
    expect(send).toHaveBeenCalledTimes(1);
    await create(row.id, payload(row, { expectedVersion: s.version })).expect(
      409,
    );
    const id = s.refunds[0].id;
    await call('post', `admin/orders/${row.id}/refunds/${id}/query`)
      .send({})
      .expect(409);
    query.mockResolvedValueOnce({
      status: 'SUCCEEDED',
      transactionNo: numberFor(1),
    });
    await call('post', `admin/orders/${row.id}/refunds/${id}/query`)
      .send({ transactionNo: numberFor(1) })
      .expect(201);
    expect((await state(row.id).expect(200)).body.paymentStatus).toBe(
      'REFUNDED',
    );
    await call('post', `admin/orders/${row.id}/refunds/${id}/query`)
      .send({})
      .expect(201);
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('holds processing/unknown outcomes and releases only a verified rejection', async () => {
    const row = await fixture('vnpay');
    send.mockResolvedValueOnce({
      status: 'PROCESSING',
      transactionNo: numberFor(2),
    });
    const r = (await create(row.id, payload(row)).expect(201)).body;
    expect((await state(row.id).expect(200)).body.paymentStatus).toBe('PAID');
    query.mockRejectedValueOnce(Error('Network unavailable'));
    await call('post', `admin/orders/${row.id}/refunds/${r.id}/query`)
      .send({})
      .expect(201);
    let s = (await state(row.id).expect(200)).body;
    expect(s.sources[0].available).toBe('0');
    await call('post', `admin/orders/${row.id}/refunds/${r.id}/query`)
      .send({})
      .expect(429);
    await db.$executeRaw`UPDATE "Refund" SET "lastQueryAt"=NULL WHERE id=${r.id}::uuid`;
    query.mockResolvedValueOnce({
      status: 'FAILED',
      transactionNo: numberFor(2),
    });
    await call('post', `admin/orders/${row.id}/refunds/${r.id}/query`)
      .send({})
      .expect(201);
    s = (await state(row.id).expect(200)).body;
    expect(s.sources[0].available).toBe('230');
    await create(row.id, payload(row, { expectedVersion: s.version })).expect(
      201,
    );
    expect(send).toHaveBeenCalledTimes(2);
  });
  it('keeps partial primary payment status when a late second payment arrives and refunds the extra separately', async () => {
    const row = await fixture('vnpay', false);
    await received(row);
    let s = (await state(row.id).expect(200)).body;
    send.mockResolvedValueOnce({
      status: 'SUCCEEDED',
      transactionNo: numberFor(3),
    });
    await create(
      row.id,
      payload(row, { expectedVersion: s.version, expectedAmount: '100' }),
    ).expect(201);
    const extra = await db.paymentAttempt.create({
      data: {
        paymentId: row.payment!.id,
        reference: randomUUID().replaceAll('-', ''),
        amount: '230',
        ipAddress: '127.0.0.1',
        expiresAt: new Date(Date.now() + 900000),
      },
    });
    const fields: Record<string, string> = {
      vnp_TmnCode: 'TEST0001',
      vnp_TxnRef: extra.reference,
      vnp_Amount: '23000',
      vnp_TransactionNo: numberFor(6),
      vnp_ResponseCode: '00',
      vnp_TransactionStatus: '00',
    };
    const params = new URLSearchParams();
    Object.keys(fields)
      .sort()
      .forEach((k) => params.set(k, fields[k]));
    params.set(
      'vnp_SecureHash',
      createHmac('sha512', secret).update(params.toString()).digest('hex'),
    );
    const callback = await request(app.getHttpServer())
      .get('/api/v1/payments/vnpay/ipn?' + params.toString())
      .expect(200);
    expect(callback.body.RspCode).toBe('00');
    s = (await state(row.id).expect(200)).body;
    expect(s.paymentStatus).toBe('PARTIALLY_REFUNDED');
    expect(
      s.sources.find((v: { attemptId: string }) => v.attemptId === extra.id)
        .available,
    ).toBe('230');
    send.mockResolvedValueOnce({
      status: 'SUCCEEDED',
      transactionNo: numberFor(4),
    });
    await create(
      row.id,
      payload(row, { expectedVersion: s.version, paymentAttemptId: extra.id }),
    ).expect(201);
    s = (await state(row.id).expect(200)).body;
    expect(s.paymentStatus).toBe('PARTIALLY_REFUNDED');
    expect(s.refunded).toBe('330');
  });
  it('does not accept a reused provider refund number for a second source', async () => {
    const first = await fixture('vnpay');
    send.mockResolvedValueOnce({
      status: 'SUCCEEDED',
      transactionNo: numberFor(5),
    });
    await create(first.id, payload(first)).expect(201);
    const next = await fixture('vnpay');
    send.mockResolvedValueOnce({
      status: 'SUCCEEDED',
      transactionNo: numberFor(5),
    });
    const r = (await create(next.id, payload(next)).expect(201)).body;
    expect(r.status).toBe('REVIEW');
    expect((await state(next.id).expect(200)).body.paymentStatus).toBe('PAID');
  });
  it('blocks a second unresolved refund of the same source after a new partial return', async () => {
    const row = await fixture('vnpay', false);
    await received(row);
    let s = (await state(row.id).expect(200)).body;
    send.mockRejectedValueOnce(Error('Lost response'));
    await create(
      row.id,
      payload(row, { expectedVersion: s.version, expectedAmount: '100' }),
    ).expect(201);
    await received(row);
    s = (await state(row.id).expect(200)).body;
    await create(
      row.id,
      payload(row, { expectedVersion: s.version, expectedAmount: '100' }),
    ).expect(409);
    expect(send).toHaveBeenCalledTimes(1);
    expect(s.sources[0].pending).toBe(true);
    expect(s.refunds[0].attemptId).toBe(row.payment!.attempts[0].id);
    expect(s.refunds[0].providerRequestId).toMatch(/^[a-f0-9]{32}$/);
    const customer = (
      await call('get', `orders/${row.id}/refunds`, buyer).expect(200)
    ).body;
    expect(customer.refunds[0].providerRequestId).toBeUndefined();
    expect(customer.refunds[0].attemptId).toBeUndefined();
  });
  it('separates legacy refunded amounts without inventing receipts or inflating verified balance', async () => {
    const before = (await call('get', 'admin/summary').expect(200)).body;
    const row = await fixture();
    await db.payment.update({
      where: { id: row.payment!.id },
      data: { status: 'REFUNDED' },
    });
    const after = (await call('get', 'admin/summary').expect(200)).body;
    expect(BigInt(after.paidRevenueVnd) - BigInt(before.paidRevenueVnd)).toBe(
      230n,
    );
    expect(BigInt(after.refundedVnd) - BigInt(before.refundedVnd)).toBe(0n);
    expect(BigInt(after.netCollectedVnd) - BigInt(before.netCollectedVnd)).toBe(
      0n,
    );
    expect(
      BigInt(after.legacyRefundUnverifiedVnd) -
        BigInt(before.legacyRefundUnverifiedVnd),
    ).toBe(230n);
    expect((await state(row.id).expect(200)).body.sources).toHaveLength(0);
  });
});
