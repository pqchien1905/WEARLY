import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { OrderStatus, PaymentStatus } from '../src/generated/prisma/client';

describe('Admin order workspace', () => {
  let app: INestApplication,
    db: PrismaService,
    admin: string,
    customer: string,
    staffId: string,
    buyerId: string;
  let categoryId: string, brandId: string, productId: string, variantId: string;
  const suffix = randomUUID(),
    ids: string[] = [];
  const call = (
    method: 'get' | 'post' | 'patch',
    route: string,
    token = admin,
  ) =>
    request(app.getHttpServer())
      [method]('/api/v1/admin/' + route)
      .auth(token, { type: 'bearer' });
  beforeAll(async () => {
    if (!new URL(process.env.TEST_DATABASE_URL!).pathname.endsWith('_test'))
      throw Error('Isolated database required');
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    for (const role of ['ADMIN', 'CUSTOMER'] as const) {
      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({
          name: role,
          email: `${role}-${suffix}@example.test`,
          password: 'Orders-acceptance-2026',
        })
        .expect(201);
      if (role === 'ADMIN') {
        staffId = response.body.user.id;
        admin = response.body.accessToken;
        await db.user.update({ where: { id: staffId }, data: { role } });
      } else {
        buyerId = response.body.user.id;
        customer = response.body.accessToken;
      }
    }
    categoryId = (
      await db.category.create({ data: { slug: suffix, name: suffix } })
    ).id;
    brandId = (await db.brand.create({ data: { slug: suffix, name: suffix } }))
      .id;
    const product = await db.product.create({
      data: {
        slug: suffix,
        name: 'Order QA',
        active: false,
        description: '',
        material: '',
        style: '',
        categoryId,
        brandId,
        variants: {
          create: {
            sku: suffix,
            size: 'M',
            color: 'Đen',
            colorHex: '#000000',
            price: '100000',
            inventory: { create: { quantity: 30 } },
          },
        },
      },
      include: { variants: true },
    });
    productId = product.id;
    variantId = product.variants[0].id;
    const fixtures: [OrderStatus, string, PaymentStatus, string, string][] = [
      ['PENDING', 'cod', 'PENDING', '100000', '2026-10-23T16:59:59.999Z'],
      ['CONFIRMED', 'cod', 'PENDING', '200000', '2026-10-23T17:00:00Z'],
      ['DELIVERED', 'cod', 'PENDING', '300000', '2026-10-24T16:59:59.999Z'],
      ['DELIVERED', 'vnpay', 'PAID', '400000', '2026-10-24T17:00:00Z'],
      ['CANCELLED', 'vnpay', 'REFUNDED', '500000', '2026-10-25T00:00:00Z'],
      ['PENDING', 'free', 'PAID', '0', '2026-10-25T00:00:00Z'],
    ];
    for (const [
      index,
      [status, provider, paymentStatus, total, date],
    ] of fixtures.entries()) {
      const order = await db.order.create({
        data: {
          userId: buyerId,
          status,
          idempotencyKey: randomUUID(),
          requestHash: suffix,
          addressSnapshot: {
            recipient: `Recipient_${index}-${suffix}`,
            phone: '0909876543',
            address: 'Test address',
          },
          subtotal: total,
          shipping: '0',
          total,
          createdAt: new Date(date),
          items: {
            create: {
              variantId,
              name: `Order QA ${suffix}`,
              sku: `SKU_${suffix}`,
              slug: suffix,
              size: 'M',
              color: 'Đen',
              image: '',
              quantity: 1,
              unitPrice: total,
            },
          },
          payment: {
            create: { provider, status: paymentStatus, amount: total },
          },
        },
      });
      ids.push(order.id);
    }
  });
  afterAll(async () => {
    try {
      if (db) {
        await db.adminAuditEvent.deleteMany({
          where: { targetId: { in: ids } },
        });
        await db.mailOutbox.deleteMany({ where: { orderId: { in: ids } } });
        await db.inventoryMovement.deleteMany({
          where: { orderId: { in: ids } },
        });
        await db.orderItem.deleteMany({ where: { orderId: { in: ids } } });
        await db.payment.deleteMany({ where: { orderId: { in: ids } } });
        await db.order.deleteMany({ where: { id: { in: ids } } });
        if (variantId) {
          await db.inventory.deleteMany({ where: { variantId } });
          await db.productVariant.delete({ where: { id: variantId } });
        }
        if (productId) await db.product.delete({ where: { id: productId } });
        if (categoryId) await db.category.delete({ where: { id: categoryId } });
        if (brandId) await db.brand.delete({ where: { id: brandId } });
        await db.user.deleteMany({
          where: { id: { in: [staffId, buyerId].filter(Boolean) } },
        });
      }
    } finally {
      await app?.close();
    }
  });
  const list = (query = '') =>
    call('get', `orders?q=${suffix}&${query}`).expect(200);
  it('uses inclusive Vietnam calendar dates and combines payment filters and status counts', async () => {
    const daily = (await list('from=2026-10-24&to=2026-10-24')).body;
    expect(daily.items.map((x: { id: string }) => x.id)).toEqual([
      ids[2],
      ids[1],
    ]);
    expect(daily.statusCounts).toEqual({ CONFIRMED: 1, DELIVERED: 1 });
    const filtered = (await list('provider=cod&status=PENDING')).body;
    expect(filtered.total).toBe(1);
    expect(filtered.statusCounts).toEqual({
      PENDING: 1,
      CONFIRMED: 1,
      DELIVERED: 1,
    });
    expect(
      (await list('paymentStatus=COD_UNSETTLED')).body.items.map(
        (x: { id: string }) => x.id,
      ),
    ).toEqual([ids[2]]);
    expect(
      (await list('provider=vnpay&paymentStatus=COD_UNSETTLED')).body.total,
    ).toBe(0);
    expect((await list('paymentStatus=REFUNDED')).body.total).toBe(1);
  });
  it('sorts amounts numerically with stable pagination and searches the saved recipient and SKU', async () => {
    const first = (await list('sort=total_desc&limit=2')).body;
    const second = (await list('sort=total_desc&limit=2&page=2')).body;
    expect(first.items.map((x: { total: string }) => x.total)).toEqual([
      '500000',
      '400000',
    ]);
    expect(second.items.map((x: { total: string }) => x.total)).toEqual([
      '300000',
      '200000',
    ]);
    expect((await list('sort=oldest&limit=1')).body.items[0].id).toBe(ids[0]);
    expect((await list('sort=total_asc&limit=1')).body.items[0].id).toBe(
      ids[5],
    );
    expect(
      (await call('get', `orders?q=recipient_1-${suffix}`).expect(200)).body
        .items[0].id,
    ).toBe(ids[1]);
    expect(
      (await call('get', `orders?q=sku_${suffix}`).expect(200)).body.total,
    ).toBe(6);
    expect(
      (await call('get', `orders?q=recipient%25${suffix}`).expect(200)).body
        .total,
    ).toBe(0);
  });
  it('returns a lean list and validates all filter inputs and permissions', async () => {
    const row = (await list()).body.items[0];
    for (const key of ['history', 'returns', 'idempotencyKey', 'requestHash'])
      expect(row[key]).toBeUndefined();
    expect(row.payment.attempts).toBeUndefined();
    expect(row._count.items).toBe(1);
    for (const query of [
      'sort=bad',
      'provider=bank',
      'paymentStatus=bad',
      'from=2026-02-30',
      'from=2026-10-25&to=2026-10-24',
      'to=2026-10-24T00:00:00Z',
      'limit=101',
      'page=0',
    ])
      await call('get', 'orders?' + query).expect(400);
    await call('get', 'orders', customer).expect(403);
    await call('get', `orders/${ids[0]}`, customer).expect(403);
    await call('patch', `orders/${ids[0]}/status`, customer)
      .send({ status: 'CONFIRMED', expectedVersion: 0 })
      .expect(403);
    await call('patch', `orders/${randomUUID()}/status`)
      .send({ status: 'CONFIRMED', expectedVersion: 0 })
      .expect(404);
  });
  it('allows one concurrent confirmation, then ships and delivers without marking COD paid', async () => {
    const transition = (status: string, expectedVersion: number) =>
      call('patch', `orders/${ids[0]}/status`).send({
        status,
        expectedVersion,
      });
    await transition('DELIVERED', 0).expect(409);
    const concurrent = await Promise.all([
      transition('CONFIRMED', 0),
      transition('CONFIRMED', 0),
    ]);
    expect(concurrent.map((r) => r.status).sort()).toEqual([200, 409]);
    expect(
      await db.orderEvent.count({
        where: { orderId: ids[0], status: 'CONFIRMED' },
      }),
    ).toBe(1);
    await transition('SHIPPED', 1).expect(200);
    await transition('DELIVERED', 2).expect(200);
    const delivered = (await call('get', `orders/${ids[0]}`).expect(200)).body;
    expect(delivered).toMatchObject({
      status: 'DELIVERED',
      version: 3,
      payment: { status: 'PENDING' },
      shipment: { status: 'DELIVERED' },
    });
    await call('post', `orders/${ids[0]}/settle-cod`)
      .send({ amount: '99999', reference: 'QA-RECEIPT', expectedVersion: 3 })
      .expect(409);
    const receipt = {
      amount: '100000',
      reference: 'QA-RECEIPT',
      expectedVersion: 3,
    };
    await call('post', `orders/${ids[0]}/settle-cod`).send(receipt).expect(201);
    await call('post', `orders/${ids[0]}/settle-cod`).send(receipt).expect(201);
    expect(
      (await db.payment.findUniqueOrThrow({ where: { orderId: ids[0] } }))
        .status,
    ).toBe('PAID');
    expect(
      await db.adminAuditEvent.count({
        where: { targetId: ids[0], action: 'COD_SETTLED' },
      }),
    ).toBe(1);
  });
  it('rejects missing, cancelled and mismatched payments before changing the order', async () => {
    const update = () =>
      call('patch', `orders/${ids[1]}/status`).send({
        status: 'SHIPPED',
        expectedVersion: 0,
      });
    await db.payment.update({
      where: { orderId: ids[1] },
      data: { status: 'CANCELLED' },
    });
    await update().expect(409);
    await db.payment.update({
      where: { orderId: ids[1] },
      data: { status: 'PENDING', amount: '1' },
    });
    await update().expect(409);
    await db.payment.delete({ where: { orderId: ids[1] } });
    await update().expect(409);
    expect(
      (await db.order.findUniqueOrThrow({ where: { id: ids[1] } })).version,
    ).toBe(0);
  });
});
