import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { OrderStatus } from '../src/generated/prisma/client';

describe('Explicit COD settlement with PostgreSQL', () => {
  let app: INestApplication, db: PrismaService, admin: string, customer: string;
  const users: string[] = [], orders: string[] = [];
  beforeAll(async () => {
    if (!new URL(process.env.TEST_DATABASE_URL ?? 'http://invalid').pathname.endsWith('_test')) throw new Error('Test DB required');
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    process.env.NODE_ENV = 'test';
    process.env.JWT_ACCESS_SECRET = 'test-access-'.repeat(5);
    process.env.JWT_REFRESH_SECRET = 'test-refresh-'.repeat(5);
    const module = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app); await app.init(); db = app.get(PrismaService);
    for (const role of ['ADMIN', 'CUSTOMER'] as const) {
      const res = await request(app.getHttpServer()).post('/api/v1/auth/register')
        .send({ name: role, email: `settlement-${randomUUID()}@example.test`, password: 'Wearly-settlement-test-2026' }).expect(201);
      users.push(res.body.user.id);
      if (role === 'ADMIN') { admin = res.body.accessToken; await db.user.update({ where: { id: users[0] }, data: { role } }); }
      else customer = res.body.accessToken;
    }
  });
  afterAll(async () => {
    if (db) {
      await db.adminAuditEvent.deleteMany({ where: { actorId: { in: users } } });
      // A payment owns its immutable receipt; no application endpoint deletes it.
      await db.payment.deleteMany({ where: { orderId: { in: orders } } });
      await db.order.deleteMany({ where: { id: { in: orders } } });
      await db.user.deleteMany({ where: { id: { in: users } } });
    }
    if (app) await app.close();
  });
  async function fixture(status: OrderStatus = 'DELIVERED', provider = 'cod') {
    const row = await db.order.create({ data: {
      userId: users[1], idempotencyKey: randomUUID(), requestHash: 'fixture', status,
      addressSnapshot: {}, subtotal: '490000', shipping: '30000', total: '520000',
      payment: { create: { provider, amount: '520000' } },
    } });
    orders.push(row.id); return row.id;
  }
  const body = { amount: '520000', reference: 'COD-LOCAL-001', expectedVersion: 0 };
  const settle = (id: string, auth = admin) => request(app.getHttpServer())
    .post(`/api/v1/admin/orders/${id}/settle-cod`).auth(auth, { type: 'bearer' });
  const detail = (id: string) => request(app.getHttpServer()).get(`/api/v1/admin/orders/${id}`).auth(admin, { type: 'bearer' });
  const summary = () => request(app.getHttpServer()).get('/api/v1/admin/summary').auth(admin, { type: 'bearer' });

  it('requires an authorized actor and validated whole-VND amount/reference/version', async () => {
    const id = await fixture();
    await request(app.getHttpServer()).post(`/api/v1/admin/orders/${id}/settle-cod`).send(body).expect(401);
    await settle(id, customer).send(body).expect(403);
    for (const patch of [
      { amount: '520000.5' }, { amount: '-1' }, { amount: '0' }, { reference: '   ' },
      { reference: 'x'.repeat(101) }, { expectedVersion: -1 }, { actorId: users[1] },
    ]) await settle(id).send({ ...body, ...patch }).expect(400);
    expect((await detail(id).expect(200)).body.payment.status).toBe('PENDING');
  });
  it('refuses incorrect states, provider, amount and stale versions without side effects', async () => {
    for (const state of ['PENDING', 'CONFIRMED', 'SHIPPED', 'CANCELLED'] as const) {
      await settle(await fixture(state)).send(body).expect(409);
    }
    await settle(await fixture('DELIVERED', 'vnpay')).send(body).expect(409);
    const id = await fixture();
    await settle(id).send({ ...body, amount: '519999' }).expect(409);
    await settle(id).send({ ...body, expectedVersion: 1 }).expect(409);
    await settle(randomUUID()).send(body).expect(404);
    const order = (await detail(id).expect(200)).body;
    expect(order.version).toBe(0);
    expect(order.payment.status).toBe('PENDING');
    expect(await db.adminAuditEvent.count({ where: { targetId: id } })).toBe(0);
  });
  it('settles once under concurrent retries and retains actor, amount and reference', async () => {
    const id = await fixture();
    const responses = await Promise.all([settle(id).send(body), settle(id).send(body)]);
    expect(responses.map(r => r.status)).toEqual([201, 201]);
    expect(responses[0].body.payment.settlement).toEqual(responses[1].body.payment.settlement);
    const row = (await detail(id).expect(200)).body;
    expect(row).toMatchObject({ version: 1, status: 'DELIVERED', payment: { status: 'PAID', settlement: {
      actorId: users[0], amount: '520000', reference: 'COD-LOCAL-001',
    } } });
    expect(Date.parse(row.payment.settlement.settledAt)).toBeGreaterThan(Date.now() - 10000);
    await settle(id).send({ ...body, reference: 'different' }).expect(409);
    await settle(id).send({ ...body, amount: '1' }).expect(409);
    const events = await db.adminAuditEvent.findMany({ where: { targetId: id } });
    expect(events.map(e => e.action)).toEqual(['COD_SETTLED']);
    const customerView = await request(app.getHttpServer()).get(`/api/v1/orders/${id}`).auth(customer, { type: 'bearer' }).expect(200);
    expect(customerView.body.payment.status).toBe('PAID');
    expect(customerView.body.payment.settlement).toBeUndefined();
  });
  it('reports received money separately from delivered COD awaiting collection', async () => {
    const before = (await summary().expect(200)).body;
    const id = await fixture();
    const waiting = (await summary().expect(200)).body;
    expect(BigInt(waiting.codAwaitingSettlementVnd) - BigInt(before.codAwaitingSettlementVnd)).toBe(520000n);
    expect(waiting.paidRevenueVnd).toBe(before.paidRevenueVnd);
    await settle(id).send(body).expect(201);
    const after = (await summary().expect(200)).body;
    expect(BigInt(after.paidRevenueVnd) - BigInt(before.paidRevenueVnd)).toBe(520000n);
    expect(after.paidOrders - before.paidOrders).toBe(1);
    expect(after.codAwaitingSettlementVnd).toBe(before.codAwaitingSettlementVnd);
  });
  it('rolls back payment, version and receipt if the audit insert fails', async () => {
    const id = await fixture();
    // Force a genuine DB audit failure, after the other writes, for this one order.
    await db.$executeRawUnsafe(`ALTER TABLE "AdminAuditEvent" ADD CONSTRAINT "settlement_test_failure" CHECK ("targetId" <> '${id}'::uuid)`);
    try {
      const response = await settle(id).send(body);
      expect(response.status).toBeGreaterThanOrEqual(400);
      const row = (await detail(id).expect(200)).body;
      expect(row.version).toBe(0); expect(row.payment.status).toBe('PENDING');
      expect(row.payment.settlement).toBeNull();
    } finally { await db.$executeRaw`ALTER TABLE "AdminAuditEvent" DROP CONSTRAINT "settlement_test_failure"`; }
  });
});
