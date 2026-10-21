import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import * as audit from '../src/modules/admin/audit';

describe('Returns and authorized cancellation', () => {
  let app: INestApplication,
    db: PrismaService,
    admin: string,
    buyer: string,
    stranger: string,
    actorId: string,
    userId: string,
    variantId: string;
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
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
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
              name: 'Return fixture',
              email: randomUUID() + '@example.test',
              password: 'Returns-password-2026',
            })
            .expect(201)
        ).body,
      );
    [admin, buyer, stranger] = people.map((p) => p.accessToken);
    actorId = people[0].user.id;
    userId = people[1].user.id;
    await db.user.update({ where: { id: actorId }, data: { role: 'ADMIN' } });
    const slug = 'returns-' + randomUUID();
    const p = await db.product.create({
      data: {
        slug,
        name: 'Returns fixture',
        description: '',
        style: '',
        material: '',
        category: { create: { slug, name: slug } },
        brand: { create: { slug, name: slug } },
        variants: {
          create: {
            sku: slug,
            price: '10',
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
  afterAll(async () => {
    if (app) await app.close();
  });
  async function fixture({
    state = 'DELIVERED' as 'DELIVERED' | 'PENDING' | 'CONFIRMED' | 'SHIPPED',
    paid = true,
    age = 0,
    legacy = false,
    provider = 'cod',
  } = {}) {
    const row = await db.order.create({
      data: {
        userId,
        idempotencyKey: randomUUID(),
        requestHash: 'return-fixture',
        status: state,
        addressSnapshot: {},
        subtotal: '30',
        discount: '25',
        couponCode: 'FIXTURE',
        shipping: '0',
        total: '5',
        items: {
          create: {
            variantId,
            name: 'Return fixture',
            sku: 'sku',
            slug: 'slug',
            size: 'M',
            color: 'Black',
            image: '',
            unitPrice: '10',
            quantity: 3,
          },
        },
        payment: {
          create: { provider, amount: '5', status: paid ? 'PAID' : 'PENDING' },
        },
        ...(!legacy && state === 'DELIVERED'
          ? {
              history: {
                create: {
                  status: 'DELIVERED',
                  version: 0,
                  actorId,
                  createdAt: new Date(Date.now() - age),
                },
              },
            }
          : {}),
      },
      include: { items: true, payment: true },
    });
    const payload = {
      requestKey: randomUUID().toUpperCase(),
      reason: 'Không vừa kích thước',
      items: [{ orderItemId: row.items[0].id, quantity: 1 }],
    };
    return { ...row, payload };
  }
  const create = (
    row: { id: string; payload: object },
    patch = {},
    token = buyer,
  ) =>
    call('post', `orders/${row.id}/returns`, token).send({
      ...row.payload,
      ...patch,
    });
  const state = (id: string, token = buyer) =>
    call('get', `orders/${id}/returns`, token);
  const decide = (
    id: string,
    returnId: string,
    status = 'APPROVED',
    version = 0,
    token = admin,
  ) =>
    call('post', `admin/orders/${id}/returns/${returnId}/decision`, token).send(
      { status, expectedVersion: version, note: 'Đã kiểm tra yêu cầu' },
    );
  const receive = (id: string, returnId: string, version = 1) =>
    call('post', `admin/orders/${id}/returns/${returnId}/receive`).send({
      expectedVersion: version,
      note: 'Đã nhận đủ số lượng được duyệt',
    });
  const cancel = (id: string, version = 0, token = admin) =>
    call('post', `admin/orders/${id}/cancel`, token).send({
      expectedVersion: version,
      reason: 'Khách yêu cầu hủy trước khi gửi',
    });
  it('authorizes owner reads/requests and staff decisions with bounded payloads', async () => {
    const row = await fixture();
    await request(app.getHttpServer())
      .get(`/api/v1/orders/${row.id}/returns`)
      .expect(401);
    await state(row.id, stranger).expect(404);
    await create(row, {}, stranger).expect(404);
    for (const patch of [
      { reason: ' ' },
      { reason: 'x'.repeat(301) },
      { requestKey: 'bad' },
      { actorId },
      { items: [] },
      { items: [{ orderItemId: row.items[0].id, quantity: 0 }] },
    ])
      await create(row, patch).expect(400);
    const r = (await create(row).expect(201)).body;
    await decide(row.id, r.id, 'APPROVED', 0, buyer).expect(403);
    await cancel(row.id, 0, buyer).expect(403);
    expect(r.approvedBy).toBeUndefined();
  });
  it('enforces payment, actual delivery date and the seven-day window', async () => {
    for (const options of [
      { paid: false },
      { state: 'PENDING' as const },
      { legacy: true },
      { age: 8 * 86400000 },
    ]) {
      const row = await fixture(options);
      expect(
        (await state(row.id).expect(200)).body.eligibility.canRequest,
      ).toBe(false);
      await create(row).expect(409);
    }
    const row = await fixture();
    expect((await state(row.id).expect(200)).body.eligibility.canRequest).toBe(
      true,
    );
  });
  it('quotes exact discount, snapshots requests and serializes one open case with idempotent replay', async () => {
    const row = await fixture();
    const quote = (
      await call('post', `orders/${row.id}/returns/quote`, buyer)
        .send({ items: row.payload.items })
        .expect(201)
    ).body;
    expect(quote.amount).toBe('1');
    await create(row, { expectedAmount: '2' }).expect(409);
    const results = await Promise.all([create(row), create(row)]);
    expect(results.map((r) => r.status)).toEqual([201, 201]);
    expect(results[0].body.id).toBe(results[1].body.id);
    expect(results[0].body.amount).toBe('1');
    await create(row, { reason: 'Lý do khác' }).expect(409);
    await create(row, { requestKey: randomUUID() }).expect(409);
    await db.productVariant.update({
      where: { id: variantId },
      data: { price: '50000' },
    });
    expect((await create(row).expect(201)).body.amount).toBe('1');
  });
  it('rejects invalid quantities and releases the open case when staff reject it', async () => {
    const row = await fixture();
    for (const items of [
      [{ orderItemId: randomUUID(), quantity: 1 }],
      [{ orderItemId: row.items[0].id, quantity: 4 }],
      [...row.payload.items, ...row.payload.items],
    ])
      await create(row, { items }).expect(400);
    const r = (await create(row).expect(201)).body;
    await decide(row.id, r.id, 'APPROVED', 9).expect(409);
    await decide(row.id, r.id, 'REJECTED').expect(201);
    await receive(row.id, r.id).expect(409);
    expect(
      (await create(row, { requestKey: randomUUID() }).expect(201)).body.amount,
    ).toBe('1');
  });
  it('receives partial stock once; repeated partial receipts exhaust only discounted merchandise', async () => {
    const row = await fixture();
    const before = (
      await db.inventory.findUniqueOrThrow({ where: { variantId } })
    ).quantity;
    const amounts: string[] = [];
    for (let i = 0; i < 3; i++) {
      const r = (await create(row, { requestKey: randomUUID() }).expect(201))
        .body;
      amounts.push(r.amount);
      await receive(row.id, r.id, 0).expect(409);
      await decide(row.id, r.id).expect(201);
      const received = await Promise.all([
        receive(row.id, r.id),
        receive(row.id, r.id),
      ]);
      expect(received.map((r) => r.status)).toEqual([201, 201]);
      expect(received[0].body.status).toBe('RECEIVED');
      const order = await db.order.findUniqueOrThrow({
        where: { id: row.id },
        include: { payment: true },
      });
      expect(order.status).toBe(i === 2 ? 'RETURNED' : 'DELIVERED');
      expect(order.payment!.status).toBe('PAID');
    }
    expect(amounts).toEqual(['1', '2', '2']);
    expect(
      (await db.inventory.findUniqueOrThrow({ where: { variantId } })).quantity,
    ).toBe(before + 3);
    expect(
      await db.inventoryMovement.count({
        where: { orderId: row.id, reason: 'CUSTOMER_RETURN' },
      }),
    ).toBe(3);
    expect((await state(row.id).expect(200)).body.requests).toHaveLength(3);
    expect((await state(row.id).expect(200)).body.eligibility.reason).toBe(
      'NOTHING_LEFT',
    );
    await create(row, { requestKey: randomUUID() }).expect(409);
  });
  it('rolls back receipt and inventory on audit failure', async () => {
    const row = await fixture(),
      r = (await create(row).expect(201)).body;
    await decide(row.id, r.id).expect(201);
    const quantity = (
      await db.inventory.findUniqueOrThrow({ where: { variantId } })
    ).quantity;
    const spy = jest
      .spyOn(audit, 'recordAdminActivity')
      .mockRejectedValueOnce(new Error('Simulated audit failure'));
    try {
      await receive(row.id, r.id).expect(500);
    } finally {
      spy.mockRestore();
    }
    expect((await state(row.id).expect(200)).body.requests[0].status).toBe(
      'APPROVED',
    );
    expect(
      (await db.inventory.findUniqueOrThrow({ where: { variantId } })).quantity,
    ).toBe(quantity);
  });
  it('cancels authorized pre-dispatch orders once and keeps collected money for refund processing', async () => {
    const row = await fixture({ state: 'CONFIRMED', provider: 'vnpay' });
    const quantity = (
      await db.inventory.findUniqueOrThrow({ where: { variantId } })
    ).quantity;
    await call('post', `orders/${row.id}/cancel`, buyer).expect(409);
    await cancel(row.id, 1).expect(409);
    const results = await Promise.all([cancel(row.id), cancel(row.id)]);
    expect(results.map((r) => r.status)).toEqual([201, 201]);
    expect(results[0].body).toMatchObject({
      status: 'CANCELLED',
      payment: { status: 'PAID', amount: '5' },
    });
    expect(
      (await db.inventory.findUniqueOrThrow({ where: { variantId } })).quantity,
    ).toBe(quantity + 3);
    expect(
      await db.adminAuditEvent.count({
        where: { targetId: row.id, action: 'ORDER_CANCELLED' as never },
      }),
    ).toBe(1);
    const owner = await fixture({ state: 'PENDING', provider: 'vnpay' });
    expect(
      (await call('post', `orders/${owner.id}/cancel`, buyer).expect(201)).body
        .payment.status,
    ).toBe('PAID');
    const unpaid = await fixture({ state: 'CONFIRMED', paid: false });
    expect((await cancel(unpaid.id).expect(201)).body.payment.status).toBe(
      'CANCELLED',
    );
    await cancel((await fixture({ state: 'SHIPPED' })).id).expect(409);
  });
  it('blocks cancellation of unresolved gateway attempts, including a later pending attempt on a paid order', async () => {
    const row = await fixture({ state: 'PENDING', provider: 'vnpay' });
    await db.paymentAttempt.create({
      data: {
        paymentId: row.payment!.id,
        amount: '5',
        reference: randomUUID().replaceAll('-', ''),
        ipAddress: '127.0.0.1',
        expiresAt: new Date(Date.now() + 60000),
      },
    });
    await cancel(row.id).expect(409);
    await call('post', `orders/${row.id}/cancel`, buyer).expect(409);
    expect(
      (await db.order.findUniqueOrThrow({ where: { id: row.id } })).status,
    ).toBe('PENDING');
  });
});
