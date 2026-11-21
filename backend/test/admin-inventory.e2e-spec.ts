import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import * as audit from '../src/modules/admin/audit';

describe('Inventory workspace with PostgreSQL', () => {
  let app: INestApplication,
    db: PrismaService,
    categoryId: string,
    brandId: string,
    productId: string;
  const marker = randomUUID(),
    users: string[] = [],
    tokens: Record<string, string> = {},
    stocks: string[] = [],
    variants: string[] = [];
  const call = (method: 'get' | 'post', path: string, role = 'ADMIN') =>
    request(app.getHttpServer())
      [method]('/api/v1/admin/' + path)
      .auth(tokens[role], { type: 'bearer' });
  const adjustment = (
    id: string,
    delta: number,
    expectedVersion: number,
    role = 'ADMIN',
    reason = 'Kiểm tra kho',
  ) =>
    call('post', `inventory/${id}/adjust`, role).send({
      delta,
      expectedVersion,
      reason,
    });
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
    for (const role of [
      'ADMIN',
      'MANAGER',
      'WAREHOUSE',
      'SUPPORT',
      'CUSTOMER',
    ] as const) {
      const r = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({
          name: role,
          email: `inventory-${role}-${marker}@example.test`,
          password: 'Inventory-test-2026',
        })
        .expect(201);
      users.push(r.body.user.id);
      tokens[role] = r.body.accessToken;
      if (role !== 'CUSTOMER')
        await db.user.update({ where: { id: r.body.user.id }, data: { role } });
    }
    categoryId = (
      await db.category.create({
        data: { slug: marker, name: 'Kho ' + marker },
      })
    ).id;
    brandId = (await db.brand.create({ data: { slug: marker, name: marker } }))
      .id;
    productId = (
      await db.product.create({
        data: {
          slug: marker,
          name: 'Áo kho ' + marker,
          description: 'Fixture',
          material: 'Cotton',
          style: 'Casual',
          categoryId,
          brandId,
          images: { create: { url: 'assets/images/shirt.jpg', alt: 'Áo' } },
        },
      })
    ).id;
    for (let i = 0; i < 4; i++) {
      const v = await db.productVariant.create({
        data: {
          productId,
          sku: `${marker}_${i}`,
          color: 'Trắng',
          colorHex: '#ffffff',
          size: String(i),
          price: '500000',
          active: i !== 2,
          ...(i < 3
            ? { inventory: { create: { quantity: [0, 3, 12][i] } } }
            : {}),
        },
        include: { inventory: true },
      });
      variants.push(v.id);
      if (v.inventory) stocks.push(v.inventory.id);
    }
  });
  afterAll(async () => {
    try {
      if (db) {
        await db.adminAuditEvent.deleteMany({
          where: { actorId: { in: users } },
        });
        await db.inventoryMovement.deleteMany({
          where: { inventory: { variant: { productId } } },
        });
        const orders = (
          await db.order.findMany({
            where: { userId: { in: users } },
            select: { id: true },
          })
        ).map((o) => o.id);
        await db.mailOutbox.deleteMany({ where: { orderId: { in: orders } } });
        await db.orderItem.deleteMany({ where: { orderId: { in: orders } } });
        await db.payment.deleteMany({ where: { orderId: { in: orders } } });
        await db.order.deleteMany({ where: { id: { in: orders } } });
        await db.cartItem.deleteMany({ where: { variant: { productId } } });
        await db.inventory.deleteMany({ where: { variant: { productId } } });
        await db.productVariant.deleteMany({ where: { productId } });
        await db.product.delete({ where: { id: productId } });
        await db.category.delete({ where: { id: categoryId } });
        await db.brand.delete({ where: { id: brandId } });
        await db.user.deleteMany({ where: { id: { in: users } } });
      }
    } finally {
      await app?.close();
    }
  });
  it('filters real variants, literal search, quantities, visibility, missing records and stable pages', async () => {
    const list = async (q: Record<string, string> = {}) =>
      (
        await call('get', 'inventory', 'WAREHOUSE')
          .query({ productId, ...q })
          .expect(200)
      ).body;
    expect((await list()).total).toBe(3);
    expect((await list({ limit: '1' })).summary).toEqual({
      units: 15,
      lowStock: 1,
      outOfStock: 1,
    });
    const clamped = await list({ limit: '1', page: '999', sort: 'attention' });
    expect(clamped.page).toBe(3);
    expect(clamped.items[0].id).toBe(stocks[2]);
    expect((await list({ visibility: 'hidden' })).summary.units).toBe(12);
    expect((await list({ record: 'missing' })).summary).toEqual({
      units: 0,
      lowStock: 0,
      outOfStock: 0,
    });
    expect((await list({ q: 'no-such-' + marker, page: '999' })).page).toBe(1);
    expect((await list({ q: 'ao kho' })).total).toBe(3);
    expect((await list({ q: '%' })).total).toBe(0);
    expect((await list({ q: marker + '_1' })).items[0].id).toBe(stocks[1]);
    expect((await list({ categoryId, status: 'low' })).items[0].id).toBe(
      stocks[1],
    );
    expect((await list({ status: 'in_stock' })).total).toBe(1); // legacy status links are active only
    expect((await list({ status: 'in_stock', visibility: 'all' })).total).toBe(
      2,
    );
    expect((await list({ visibility: 'hidden' })).items[0].id).toBe(stocks[2]);
    expect(
      (await list({ minQuantity: '4', maxQuantity: '20' })).items[0].id,
    ).toBe(stocks[2]);
    expect((await list({ record: 'missing' })).items[0]).toMatchObject({
      id: null,
      quantity: null,
      variantId: variants[3],
    });
    const first = await list({ sort: 'quantity_desc', limit: '1' }),
      second = await list({ sort: 'quantity_desc', limit: '1', page: '2' });
    expect(first.items[0].id).toBe(stocks[2]);
    expect(second.items[0].id).toBe(stocks[1]);
    for (const q of [
      { minQuantity: '10', maxQuantity: '1' },
      { minQuantity: '-1' },
      { maxQuantity: '2147483648' },
      { categoryId: 'bad' },
      { record: 'missing', status: 'out' },
      { sort: 'price_desc' },
      { status: 'wat' },
    ])
      await call('get', 'inventory').query(q).expect(400);
  });
  it('calculates real summary and enforces read/write permissions and missing IDs', async () => {
    const s = (await call('get', 'inventory/summary', 'WAREHOUSE').expect(200))
      .body;
    expect(s.skus).toBe(await db.inventory.count());
    expect(s.units).toBe(
      (await db.inventory.aggregate({ _sum: { quantity: true } }))._sum
        .quantity ?? 0,
    );
    expect(s.missing).toBe(
      await db.productVariant.count({ where: { inventory: null } }),
    );
    expect(s.lowStockThreshold).toBe(5);
    for (const role of ['SUPPORT', 'CUSTOMER']) {
      await call('get', 'inventory', role).expect(403);
      await adjustment(stocks[0], 1, 0, role).expect(403);
    }
    await request(app.getHttpServer())
      .get('/api/v1/admin/inventory')
      .expect(401);
    await call('get', 'inventory/' + randomUUID()).expect(404);
    await call('get', 'inventory/' + randomUUID() + '/movements').expect(404);
    await adjustment(randomUUID(), 1, 0).expect(404);
    for (const body of [
      { delta: 0, reason: 'Valid' },
      { delta: 1.5, reason: 'Valid' },
      { delta: 1, reason: '   ' },
      { delta: 1000001, reason: 'Valid' },
      { delta: '2', reason: 'Valid' },
    ])
      await call('post', `inventory/${stocks[0]}/adjust`)
        .send({ ...body, expectedVersion: 0 })
        .expect(400);
  });
  it('allows exactly one concurrent adjustment and protects retry, negative stock, overflow and audit consistency', async () => {
    const id = stocks[1];
    const result = await Promise.all([
      adjustment(id, 2, 0, 'ADMIN'),
      adjustment(id, -1, 0, 'WAREHOUSE'),
    ]);
    expect(result.map((r) => r.status).sort()).toEqual([201, 409]);
    const current = await db.inventory.findUniqueOrThrow({ where: { id } });
    expect(current.version).toBe(1);
    expect(
      await db.inventoryMovement.count({ where: { inventoryId: id } }),
    ).toBe(1);
    await adjustment(id, 1, 0).expect(409);
    await adjustment(id, -current.quantity - 1, current.version).expect(409);
    const history = (await call('get', `inventory/${id}/movements`).expect(200))
      .body;
    expect(history.items[0].adjustment).toMatchObject({
      before: 3,
      after: current.quantity,
    });
    expect(['ADMIN', 'WAREHOUSE']).toContain(history.items[0].adjustment.actor);
    await db.inventory.update({
      where: { id: stocks[2] },
      data: { quantity: 2147483647 },
    });
    await adjustment(stocks[2], 1, 0).expect(409);
    expect(
      (await db.inventory.findUniqueOrThrow({ where: { id: stocks[2] } }))
        .quantity,
    ).toBe(2147483647);
  });
  it('rolls back stock and movement when the audit write fails', async () => {
    const before = await db.inventory.findUniqueOrThrow({
      where: { id: stocks[0] },
    });
    const spy = jest
      .spyOn(audit, 'recordAdminActivity')
      .mockRejectedValueOnce(new Error('Fixture audit failure'));
    try {
      await adjustment(before.id, 4, before.version).expect(500);
    } finally {
      spy.mockRestore();
    }
    expect(
      await db.inventory.findUniqueOrThrow({ where: { id: before.id } }),
    ).toEqual(before);
    expect(
      await db.inventoryMovement.count({ where: { inventoryId: before.id } }),
    ).toBe(0);
  });
  it('initializes missing inventory idempotently without resetting existing stock', async () => {
    const path = `inventory/variants/${variants[3]}/initialize`;
    const responses = await Promise.all([
      call('post', path, 'WAREHOUSE').expect(201),
      call('post', path).expect(201),
    ]);
    expect(responses[0].body.id).toBe(responses[1].body.id);
    expect(responses[0].body.quantity).toBe(0);
    const id = responses[0].body.id;
    await adjustment(id, 4, 0).expect(201);
    expect((await call('post', path).expect(201)).body.quantity).toBe(4);
    expect(
      await db.inventoryMovement.count({ where: { inventoryId: id } }),
    ).toBe(1);
    await call('post', `inventory/variants/${randomUUID()}/initialize`).expect(
      404,
    );
  });
  it('paginates and filters immutable history, preserves unknown old balances and synchronizes products', async () => {
    const id = stocks[0];
    await adjustment(id, 5, 0, 'WAREHOUSE', '  Nhập kho thực tế  ').expect(201);
    await adjustment(id, -2, 1, 'MANAGER', 'Xuất kho kiểm tra').expect(201);
    const old = await db.inventoryMovement.create({
      data: {
        inventoryId: id,
        delta: 1,
        reason: 'LEGACY',
        createdAt: new Date('2026-01-01T18:00:00Z'),
      },
    });
    // Fixture opening balance, deliberately no fabricated actor or before/after.
    await db.inventory.update({
      where: { id },
      data: { quantity: { increment: 1 }, version: { increment: 1 } },
    });
    const history = async (q: Record<string, string>) =>
      (
        await call('get', `inventory/${id}/movements`, 'WAREHOUSE')
          .query(q)
          .expect(200)
      ).body;
    expect((await history({ type: 'admin' })).total).toBe(2);
    expect((await history({ type: 'out' })).total).toBe(1);
    const dated = await history({ from: '2026-01-02', to: '2026-01-02' });
    expect(dated.items[0]).toMatchObject({ id: old.id, adjustment: null });
    expect(dated.summary).toEqual({ incoming: 1, outgoing: 0, net: 1 });
    const last = await history({ type: 'admin', limit: '1', page: '999' });
    expect(last.page).toBe(2);
    expect(last.items).toHaveLength(1);
    expect(last.summary).toEqual({ incoming: 5, outgoing: 2, net: 3 });
    expect((await history({ type: 'out' })).summary).toEqual({
      incoming: 0,
      outgoing: 2,
      net: -2,
    });
    expect((await history({ limit: '1', page: '2' })).items).toHaveLength(1);
    for (const q of [
      { from: '2026-02-30' },
      { from: '2026-02-02', to: '2026-01-01' },
      { type: 'invalid' },
    ])
      await call('get', `inventory/${id}/movements`).query(q).expect(400);
    const product = (await call('get', 'products/' + productId).expect(200))
      .body;
    expect(
      product.variants.find((v: { id: string }) => v.id === variants[0])
        .inventory.quantity,
    ).toBe(4);
    const publicProduct = (
      await request(app.getHttpServer())
        .get('/api/v1/products/' + marker)
        .expect(200)
    ).body;
    expect(
      publicProduct.variants.find((v: { id: string }) => v.id === variants[0])
        .available,
    ).toBe(4);
  });
  it('checkout and cancellation preserve manual stock changes and restore only once', async () => {
    const customer = (path: string) =>
      request(app.getHttpServer())
        .post('/api/v1/' + path)
        .auth(tokens.CUSTOMER, { type: 'bearer' });
    const address = (
      await customer('users/me/addresses')
        .send({
          recipient: 'Fixture',
          phone: '0901234567',
          address: 'Địa chỉ kiểm thử',
          label: 'Nhà',
          isDefault: true,
        })
        .expect(201)
    ).body;
    const before = await db.inventory.findUniqueOrThrow({
      where: { id: stocks[0] },
    });
    await customer('cart/items')
      .send({ sku: marker + '_0', quantity: 1 })
      .expect(201);
    const order = (
      await customer('orders')
        .set('Idempotency-Key', randomUUID())
        .send({
          addressId: address.id,
          shippingMethod: 'standard',
          expectedSubtotal: '500000',
        })
        .expect(201)
    ).body;
    let current = await db.inventory.findUniqueOrThrow({
      where: { id: before.id },
    });
    expect(current.quantity).toBe(before.quantity - 1);
    await adjustment(before.id, 2, current.version).expect(201);
    await customer(`orders/${order.id}/cancel`)
      .send({ expectedVersion: order.version, reason: 'Hủy đơn kiểm thử' })
      .expect(201);
    await customer(`orders/${order.id}/cancel`)
      .send({ expectedVersion: order.version, reason: 'Gửi lại thao tác hủy' })
      .expect(201);
    current = await db.inventory.findUniqueOrThrow({
      where: { id: before.id },
    });
    expect(current.quantity).toBe(before.quantity + 2);
    expect(
      await db.inventoryMovement.count({
        where: { inventoryId: before.id, orderId: order.id, reason: 'CANCEL' },
      }),
    ).toBe(1);
    const history = (
      await call('get', `inventory/${before.id}/movements`)
        .query({ type: 'cancel' })
        .expect(200)
    ).body;
    expect(history.items[0].order).toEqual({ id: order.id, code: order.code });
    expect(history.items[0].adjustment).toBeNull();
  });

  it('validates operation direction and records distinct receipt, issue and count history atomically', async () => {
    const variant = await db.productVariant.create({
      data: {
        productId,
        sku: marker + '-operations',
        color: 'Đen',
        colorHex: '#000000',
        size: 'XL',
        price: '500000',
        inventory: { create: { quantity: 8 } },
      },
      include: { inventory: true },
    });
    const id = variant.inventory!.id;
    for (const [operation, delta] of [
      ['in', -1],
      ['out', 1],
      ['delete', 1],
      [null, 1],
    ]) {
      await call('post', `inventory/${id}/adjust`)
        .send({
          delta,
          operation,
          expectedVersion: 0,
          reason: 'Kiểm tra loại thao tác',
        })
        .expect(400);
    }
    let version = 0;
    for (const [operation, delta] of [
      ['in', 2],
      ['out', -3],
      ['count', -1],
    ]) {
      await call('post', `inventory/${id}/adjust`, 'WAREHOUSE')
        .send({
          delta,
          operation,
          expectedVersion: version++,
          reason: 'Đối soát kho thực tế',
        })
        .expect(201);
    }
    const current = await db.inventory.findUniqueOrThrow({ where: { id } });
    expect(current).toMatchObject({ quantity: 6, version: 3 });
    const history = (await call('get', `inventory/${id}/movements`).expect(200))
      .body;
    expect(history.summary).toEqual({ incoming: 2, outgoing: 4, net: -2 });
    expect(
      history.items.map(
        (m: { adjustment: { operation: string } }) => m.adjustment.operation,
      ),
    ).toEqual(['count', 'out', 'in']);
    expect(history.items[0].adjustment).toMatchObject({
      before: 7,
      after: 6,
      actor: 'WAREHOUSE',
    });
    // Existing clients can still submit an untyped, versioned adjustment.
    await adjustment(id, 1, 3).expect(201);
    const legacy = (await call('get', `inventory/${id}/movements`).expect(200))
      .body;
    expect(legacy.items[0].adjustment.operation).toBe('delta');
    const warehouseId = users[2];
    await db.user.update({
      where: { id: warehouseId },
      data: { active: false },
    });
    try {
      const denied = await adjustment(id, 1, 4, 'WAREHOUSE');
      expect([401, 403]).toContain(denied.status);
      expect(
        (await db.inventory.findUniqueOrThrow({ where: { id } })).quantity,
      ).toBe(7);
    } finally {
      await db.user.update({
        where: { id: warehouseId },
        data: { active: true },
      });
    }
  });
});
