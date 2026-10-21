import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import * as audit from '../src/modules/admin/audit';

describe('Persistent local shipment tracking', () => {
  let app: INestApplication,
    db: PrismaService,
    admin: string,
    buyer: string,
    stranger: string,
    userId: string,
    actorId: string,
    variantId: string;
  const call = (
    method: 'get' | 'post' | 'patch',
    path: string,
    token = admin,
  ) =>
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
              name: 'Shipment fixture',
              email: randomUUID() + '@example.test',
              password: 'Shipment-password-2026',
            })
            .expect(201)
        ).body,
      );
    [admin, buyer, stranger] = people.map((p) => p.accessToken);
    actorId = people[0].user.id;
    userId = people[1].user.id;
    await db.user.update({ where: { id: actorId }, data: { role: 'ADMIN' } });
    const slug = 'shipment-' + randomUUID();
    const product = await db.product.create({
      data: {
        slug,
        name: 'Tracking fixture',
        description: '',
        material: '',
        style: '',
        category: { create: { slug, name: slug } },
        brand: { create: { slug, name: slug } },
        variants: {
          create: {
            sku: slug,
            size: 'M',
            color: 'Black',
            colorHex: '#000000',
            price: '100000',
            inventory: { create: { quantity: 100 } },
          },
        },
      },
      include: { variants: true },
    });
    variantId = product.variants[0].id;
  });
  afterAll(async () => {
    if (app) await app.close();
  });
  async function fixture(provider = 'cod', paid = false) {
    return db.order.create({
      data: {
        userId,
        idempotencyKey: randomUUID(),
        requestHash: 'shipment-fixture',
        status: 'PENDING',
        addressSnapshot: {
          recipient: 'Fixture',
          phone: '0901234567',
          address: 'Test',
        },
        subtotal: '100000',
        shipping: '30000',
        total: '130000',
        items: {
          create: {
            variantId,
            name: 'Tracking fixture',
            sku: 'sku',
            slug: 'slug',
            size: 'M',
            color: 'Black',
            image: '',
            unitPrice: '100000',
            quantity: 1,
          },
        },
        payment: {
          create: {
            provider,
            amount: '130000',
            status: paid ? 'PAID' : 'PENDING',
          },
        },
      },
    });
  }
  const status = (id: string, state: string, expectedVersion: number) =>
    call('patch', `admin/orders/${id}/status`).send({
      status: state,
      expectedVersion,
    });
  const event = (
    id: string,
    state: string,
    expectedVersion: number,
    patch = {},
    token = admin,
  ) =>
    call('post', `admin/orders/${id}/shipment-events`, token).send({
      eventKey: randomUUID().toUpperCase(),
      status: state,
      expectedVersion,
      note: 'Visible customer note',
      ...patch,
    });
  const detail = (id: string) => call('get', `admin/orders/${id}`).expect(200);
  it('records real checkout and cancellation times without inventing legacy events', async () => {
    const sku = (
      await db.productVariant.findUniqueOrThrow({ where: { id: variantId } })
    ).sku;
    const address = (
      await call('post', 'users/me/addresses', buyer)
        .send({
          recipient: 'Test',
          phone: '0901234567',
          address: '12 Test Street',
          label: 'Home',
        })
        .expect(201)
    ).body;
    await call('post', 'cart/items', buyer)
      .send({ sku, quantity: 1 })
      .expect(201);
    const row = (
      await call('post', 'orders', buyer)
        .set('Idempotency-Key', randomUUID())
        .send({
          addressId: address.id,
          expectedSubtotal: '100000',
          shippingMethod: 'standard',
        })
        .expect(201)
    ).body;
    expect(row.history.map((e: { status: string }) => e.status)).toEqual([
      'PENDING',
    ]);
    const cancelled = (
      await call('post', `orders/${row.id}/cancel`, buyer).expect(201)
    ).body;
    expect(cancelled.history.map((e: { status: string }) => e.status)).toEqual([
      'PENDING',
      'CANCELLED',
    ]);
    expect(cancelled.shipment).toBeNull();
    const notices = await db.mailOutbox.findMany({
      where: { orderId: row.id },
      orderBy: { createdAt: 'asc' },
    });
    expect(notices.map((m) => m.eventKey)).toEqual([
      `order:${row.id}:0`,
      `order:${row.id}:1`,
    ]);
    expect(notices[0].body).toContain('tiếp nhận');
    expect(notices[1].body).toContain('hủy');
    const legacy = await fixture();
    await db.order.update({
      where: { id: legacy.id },
      data: { status: 'SHIPPED' },
    });
    const delivered = (await status(legacy.id, 'DELIVERED', 0).expect(200))
      .body;
    expect(delivered.shipment).toBeNull();
    expect(delivered.history.map((e: { status: string }) => e.status)).toEqual([
      'DELIVERED',
    ]);
  });
  async function shipped(provider = 'cod', paid = false) {
    const order = await fixture(provider, paid);
    await status(order.id, 'CONFIRMED', 0).expect(200);
    return (await status(order.id, 'SHIPPED', 1).expect(200)).body;
  }
  it('requires admin mutation, validates events and restricts customer tracking to its owner', async () => {
    const row = await shipped();
    await request(app.getHttpServer())
      .post(`/api/v1/admin/orders/${row.id}/shipment-events`)
      .send({})
      .expect(401);
    await event(row.id, 'OUT_FOR_DELIVERY', 2, {}, buyer).expect(403);
    for (const patch of [
      { status: 'FAKE' },
      { eventKey: 'bad' },
      { expectedVersion: -1 },
      { note: 'x'.repeat(301) },
      { actorId: userId },
    ])
      await event(row.id, 'OUT_FOR_DELIVERY', 2, patch).expect(400);
    await call('get', `orders/${row.id}`, stranger).expect(404);
    const own = (await call('get', `orders/${row.id}`, buyer).expect(200)).body;
    expect(own.shipment.carrier).toBe('local_simulator');
    expect(own.shipment.events[0].actorId).toBeUndefined();
    expect(own.history[0].actorId).toBeUndefined();
  });
  it('creates one persistent code and ordered history; delivery does not collect COD', async () => {
    let row = await shipped();
    expect(row.shipment).toMatchObject({
      carrier: 'local_simulator',
      status: 'IN_TRANSIT',
    });
    expect(row.shipment.trackingCode).toMatch(/^LOCAL-[0-9A-F-]{36}$/);
    expect(row.history.map((h: { status: string }) => h.status)).toEqual([
      'CONFIRMED',
      'SHIPPED',
    ]);
    expect(row.shipment.events[0].actorId).toBe(actorId);
    const code = row.shipment.trackingCode;
    row = (await event(row.id, 'OUT_FOR_DELIVERY', 2).expect(201)).body;
    row = (await status(row.id, 'DELIVERED', row.version).expect(200)).body;
    expect(row.shipment.trackingCode).toBe(code);
    expect(
      row.shipment.events.map((e: { status: string }) => e.status),
    ).toEqual(['IN_TRANSIT', 'OUT_FOR_DELIVERY', 'DELIVERED']);
    expect(row.payment.status).toBe('PENDING');
    expect(row.payment.settlement).toBeNull();
    const deliveredMail = await db.mailOutbox.findUnique({
      where: { eventKey: `order:${row.id}:${row.version}` },
    });
    expect(deliveredMail?.body).toContain(
      'Thu tiền và hoàn tiền được xác nhận riêng',
    );
    await event(row.id, 'IN_TRANSIT', row.version).expect(409);
  });
  it('retries failed delivery and rejects skipped transitions or stale versions', async () => {
    let row = await shipped();
    await event(row.id, 'RETURNED', 2).expect(409);
    await event(row.id, 'OUT_FOR_DELIVERY', 1).expect(409);
    row = (await event(row.id, 'DELIVERY_FAILED', 2).expect(201)).body;
    expect(row.status).toBe('SHIPPED');
    expect(row.payment.status).toBe('PENDING');
    await status(row.id, 'DELIVERED', row.version).expect(409);
    row = (await event(row.id, 'IN_TRANSIT', row.version).expect(201)).body;
    row = (await event(row.id, 'DELIVERED', row.version).expect(201)).body;
    expect(row.status).toBe('DELIVERED');
  });
  it('replays a concurrent return once, restores inventory and retains shipped coupon usage', async () => {
    let row = await shipped();
    const c = await db.coupon.create({
      data: {
        code: 'T' + randomUUID().replaceAll('-', '').slice(0, 20),
        amount: '1',
      },
    });
    // Existing zero-discount fixture remains financially unchanged; usage models an earlier coupon reservation.
    await db.$executeRaw`INSERT INTO "CouponRedemption" (id,"couponId","orderId","userId",discount) VALUES (${randomUUID()}::uuid,${c.id}::uuid,${row.id}::uuid,${userId}::uuid,0)`;
    row = (await event(row.id, 'DELIVERY_FAILED', 2).expect(201)).body;
    const quantity = (
      await db.inventory.findUniqueOrThrow({ where: { variantId } })
    ).quantity;
    const patch = {
      eventKey: randomUUID().toUpperCase(),
      note: 'Returned sealed parcel',
    };
    const results = await Promise.all([
      event(row.id, 'RETURNED', row.version, patch),
      event(row.id, 'RETURNED', row.version, patch),
    ]);
    expect(results.map((r) => r.status)).toEqual([201, 201]);
    const final = (await detail(row.id)).body;
    expect(final.status).toBe('RETURNED');
    expect(final.payment.status).toBe('CANCELLED');
    expect(
      final.shipment.events.filter(
        (e: { status: string }) => e.status === 'RETURNED',
      ),
    ).toHaveLength(1);
    expect(
      (await db.inventory.findUniqueOrThrow({ where: { variantId } })).quantity,
    ).toBe(quantity + 1);
    expect(
      await db.inventoryMovement.count({
        where: { orderId: row.id, reason: 'SHIPMENT_RETURN' },
      }),
    ).toBe(1);
    expect(
      (
        await db.$queryRaw<
          Array<{ releasedAt: Date | null }>
        >`SELECT "releasedAt" FROM "CouponRedemption" WHERE "orderId"=${row.id}::uuid`
      )[0].releasedAt,
    ).toBeNull();
    await event(row.id, 'RETURNED', row.version, {
      ...patch,
      note: 'changed',
    }).expect(409);
  });
  it('does not fabricate refunds for prepaid returned parcels and gates unpaid VNPay', async () => {
    const unpaid = await fixture('vnpay');
    await status(unpaid.id, 'CONFIRMED', 0).expect(409);
    let row = await shipped('vnpay', true);
    row = (await event(row.id, 'DELIVERY_FAILED', 2).expect(201)).body;
    row = (await event(row.id, 'RETURNED', row.version).expect(201)).body;
    expect(row.payment).toMatchObject({ status: 'PAID', amount: '130000' });
  });
  it('rolls back return events, status and inventory if the audit write fails', async () => {
    let row = await shipped();
    row = (await event(row.id, 'DELIVERY_FAILED', 2).expect(201)).body;
    const before = (
      await db.inventory.findUniqueOrThrow({ where: { variantId } })
    ).quantity;
    const spy = jest
      .spyOn(audit, 'recordAdminActivity')
      .mockRejectedValueOnce(new Error('Simulated audit failure'));
    try {
      await event(row.id, 'RETURNED', row.version).expect(500);
    } finally {
      spy.mockRestore();
    }
    const after = (await detail(row.id)).body;
    expect(after.version).toBe(row.version);
    expect(after.shipment.status).toBe('DELIVERY_FAILED');
    expect(
      (await db.inventory.findUniqueOrThrow({ where: { variantId } })).quantity,
    ).toBe(before);
  });
});
