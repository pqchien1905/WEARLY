import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { AdminService } from '../src/modules/admin/admin.service';

describe('Administration with PostgreSQL', () => {
  let app: INestApplication, db: PrismaService, token: string, customer: string;
  let productId: string, skuId: string, inventoryId: string, orderId: string;
  const suffix = randomUUID();
  let categoryId: string, brandId: string;
  const users: string[] = [];
  const taxonomies: { kind: 'categories' | 'brands'; id: string }[] = [];
  const extraProducts: string[] = [];
  const call = (method: 'get' | 'post' | 'patch', path: string, auth = token) =>
    request(app.getHttpServer())
      [method]('/api/v1/' + path)
      .auth(auth, { type: 'bearer' });
  it('restricts persistent activity history to administrators and bounds pagination', async () => {
    await request(app.getHttpServer()).get('/api/v1/admin/audit').expect(401);
    await call('get', 'admin/audit', customer).expect(403);
    await call('get', 'admin/audit?page=0').expect(400);
    await call('get', 'admin/audit?limit=101').expect(400);
    const result = await call('get', 'admin/audit?limit=1').expect(200);
    expect(result.body).toMatchObject({ page: 1, limit: 1 });
    expect(Array.isArray(result.body.items)).toBe(true);
    expect(typeof result.body.total).toBe('number');
  });
  it('rejects missing related records without replacing the existing gallery', async () => {
    const before = await db.product.findUniqueOrThrow({
      where: { id: productId }, include: { images: true },
    });
    const response = await call('patch', `admin/products/${productId}`)
      .send({
        categoryId: randomUUID(),
        images: [{ url: 'https://example.com/replacement.jpg', alt: 'New' }],
      })
      .expect(400);
    expect(response.body.error).toMatchObject({
      code: 'INVALID_REFERENCE', retryable: false,
    });
    const after = await db.product.findUniqueOrThrow({
      where: { id: productId }, include: { images: true },
    });
    expect(after.categoryId).toBe(before.categoryId);
    expect(after.images).toEqual(before.images);
    await call('post', 'admin/products')
      .send({
        slug: 'invalid-' + suffix, name: 'Invalid relation', description: '',
        material: '', style: '', categoryId, brandId: randomUUID(),
      })
      .expect(400);
    await call('post', 'admin/skus')
      .send({
        productId: randomUUID(), sku: 'invalid-' + suffix, size: 'M',
        color: 'Black', colorHex: '#000000', price: '490000',
      })
      .expect(400);
    expect(await db.product.count({ where: { slug: 'invalid-' + suffix } })).toBe(0);
    expect(await db.productVariant.count({ where: { sku: 'invalid-' + suffix } })).toBe(0);
  });
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
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    for (const role of ['ADMIN', 'CUSTOMER'] as const) {
      const r = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({
          name: role,
          email: `${role}-${suffix}@example.test`,
          password: 'Wearly-admin-test-2026',
        })
        .expect(201);
      users.push(r.body.user.id);
      if (role === 'ADMIN') {
        token = r.body.accessToken;
        await db.user.update({ where: { id: r.body.user.id }, data: { role } });
      } else customer = r.body.accessToken;
    }
    categoryId = (
      await db.category.create({
        data: { slug: 'admin-' + suffix, name: 'Admin test' },
      })
    ).id;
    brandId = (
      await db.brand.create({
        data: { slug: 'admin-' + suffix, name: 'Admin test' },
      })
    ).id;
    const p = await db.product.create({
      data: {
        slug: 'admin-' + suffix,
        name: 'Admin test',
        description: '',
        material: 'Cotton',
        style: '',
        categoryId,
        brandId,
        images: {
          create: [
            { url: 'https://example.com/one.jpg', alt: 'One', position: 0 },
            { url: 'https://example.com/two.jpg', alt: 'Two', position: 1 },
          ],
        },
        variants: {
          create: {
            sku: 'admin-' + suffix,
            size: 'M',
            color: 'Black',
            colorHex: '#000000',
            price: '490000',
            active: false,
            inventory: { create: { quantity: 3 } },
          },
        },
      },
      include: { variants: { include: { inventory: true } } },
    });
    productId = p.id;
    skuId = p.variants[0].id;
    inventoryId = p.variants[0].inventory!.id;
  });
  afterAll(async () => {
    if (db) {
      await db.adminAuditEvent.deleteMany({ where: { actorId: { in: users } } });
      await db.inventory.deleteMany({ where: { variant: { productId: { in: extraProducts } } } });
      await db.productVariant.deleteMany({ where: { productId: { in: extraProducts } } });
      await db.product.deleteMany({ where: { id: { in: extraProducts } } });
      if (inventoryId)
        await db.inventoryMovement.deleteMany({ where: { inventoryId } });
      if (orderId) {
        await db.payment.deleteMany({ where: { orderId } });
        await db.orderItem.deleteMany({ where: { orderId } });
        await db.order.delete({ where: { id: orderId } });
      }
      await db.user.deleteMany({ where: { id: { in: users } } });
      if (inventoryId)
        await db.inventory.delete({ where: { id: inventoryId } });
      if (skuId) await db.productVariant.delete({ where: { id: skuId } });
      if (productId) await db.product.delete({ where: { id: productId } });
      if (categoryId) await db.category.delete({ where: { id: categoryId } });
      if (brandId) await db.brand.delete({ where: { id: brandId } });
      for (const row of taxonomies) {
        if (row.kind === 'categories')
          await db.category.delete({ where: { id: row.id } });
        else await db.brand.delete({ where: { id: row.id } });
      }
    }
    if (app) await app.close();
  });
  for (const kind of ['categories', 'brands'] as const) {
    it(`protects, validates, creates and safely renames ${kind}`, async () => {
      const path = `admin/${kind}`;
      for (const [method, route] of [
        ['get', path],
        ['post', path],
        ['patch', `${path}/${randomUUID()}`],
      ] as const) {
        await request(app.getHttpServer())
          [method]('/api/v1/' + route)
          .expect(401);
        await call(method, route, customer).expect(403);
      }
      const first = await call('get', path + '?limit=1').expect(200);
      expect(first.body).toMatchObject({ page: 1, limit: 1 });
      expect(first.body.total).toBeGreaterThan(0);
      expect(first.body.items[0]._count.products).toEqual(expect.any(Number));
      for (const body of [
        { name: ' ', slug: 'valid' },
        { name: 'Valid', slug: 'Invalid Slug' },
        { name: 'Valid', slug: 'a'.repeat(101) },
      ]) {
        await call('post', path).send(body).expect(400);
      }
      const slug = `taxonomy-${suffix}`;
      const created = await call('post', path)
        .send({ name: '  New name  ', slug })
        .expect(201);
      const id = created.body.id;
      taxonomies.push({ kind, id });
      expect(created.body).toMatchObject({ name: 'New name', slug });
      await call('post', path).send({ name: 'Duplicate', slug }).expect(409);
      await call('patch', `${path}/${id}`)
        .send({ name: ' ', expectedName: 'New name' })
        .expect(400);
      await call('patch', `${path}/${id}`)
        .send({ name: 'New', expectedName: 'New name', slug: 'changed' })
        .expect(400);
      await call('patch', `${path}/${id}`).send({ name: 'New' }).expect(400);
      await call('patch', `${path}/${randomUUID()}`)
        .send({ name: 'New', expectedName: 'Old' })
        .expect(404);
      const results = await Promise.all(
        ['First rename', 'Second rename'].map((name) =>
          call('patch', `${path}/${id}`).send({
            name,
            expectedName: 'New name',
          }),
        ),
      );
      expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
      const winner = results.find((r) => r.status === 200)!.body;
      expect(winner).toMatchObject({ id, slug });
      const publicList = await request(app.getHttpServer())
        .get('/api/v1/' + kind)
        .expect(200);
      // Empty taxonomies remain manageable, but do not clutter storefront filters.
      expect(publicList.body).not.toContainEqual(
        expect.objectContaining({ id, slug, name: winner.name }),
      );
      // Existing products retain IDs and slug links when their taxonomy is renamed.
      const existingId = kind === 'categories' ? categoryId : brandId;
      await call('patch', `${path}/${existingId}`)
        .send({ name: 'Renamed existing', expectedName: 'Admin test' })
        .expect(200);
      const product = await call('get', `admin/products/${productId}`).expect(
        200,
      );
      expect(
        product.body[kind === 'categories' ? 'category' : 'brand'],
      ).toMatchObject({
        id: existingId,
        slug: 'admin-' + suffix,
        name: 'Renamed existing',
      });
      const list = await call('get', path + '?limit=1&page=2').expect(200);
      const refreshedFirst = await call('get', path + '?limit=1').expect(200);
      expect(list.body.total).toBe(first.body.total + 1);
      expect(list.body.items[0].id).not.toBe(refreshedFirst.body.items[0].id);
    });
  }
  it('protects every admin read and returns full totals without credentials', async () => {
    for (const path of [
      'admin/summary',
      `admin/products/${productId}`,
      'admin/users',
    ]) {
      await request(app.getHttpServer())
        .get('/api/v1/' + path)
        .expect(401);
      await call('get', path, customer).expect(403);
    }
    const result = await call('get', 'admin/summary').expect(200);
    expect(result.body.products).toBe(await db.product.count());
    const days = result.body.dailySales as {
      day: string;
      orders: number;
      total: string;
    }[];
    expect(days).toHaveLength(14);
    expect(days.map((d) => d.day)).toEqual(
      [...days.map((d) => d.day)].sort(),
    );
    for (const d of days) {
      expect(d.day).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      expect(d.total).toMatch(/^\d+$/);
      expect(Number.isInteger(d.orders)).toBe(true);
    }
    expect(result.body.customers).toBe(
      await db.user.count({ where: { role: 'CUSTOMER' } }),
    );
    const list = await call('get', 'admin/users?limit=1').expect(200);
    expect(list.body.items).toHaveLength(1);
    expect(list.body.total).toBeGreaterThan(1);
    expect(list.body.items[0].passwordHash).toBeUndefined();
  });
  it('separates staff login and keeps independent sessions alive after counterpart logout', async () => {
    const credentials = {
      username: (await db.user.findUniqueOrThrow({ where: { id: users[0] } })).username,
      password: 'Wearly-admin-test-2026',
    };
    const before = await db.refreshToken.count({ where: { userId: users[1] } });
    await call('post', 'auth/admin/login')
      .send({ ...credentials, username: (await db.user.findUniqueOrThrow({ where: { id: users[1] } })).username })
      .expect(403);
    expect(await db.refreshToken.count({ where: { userId: users[1] } })).toBe(
      before,
    );
    await call('post', 'auth/admin/login')
      .send({ ...credentials, password: 'Incorrect-password-2026' })
      .expect(401);
    const staff = await call('post', 'auth/admin/login')
      .send(credentials)
      .expect(201);
    const shopper = await call('post', 'auth/login')
      .send({ email: `customer-${suffix}@example.test`, password: credentials.password })
      .expect(201);
    expect(staff.body.user.role).toBe('ADMIN');
    expect(staff.body.refreshToken).not.toBe(shopper.body.refreshToken);
    await call('post', 'auth/logout', staff.body.accessToken).expect(201);
    await call('get', 'auth/me', staff.body.accessToken).expect(401);
    await call('get', 'auth/me', shopper.body.accessToken).expect(200);
    const staffAgain = await call('post', 'auth/admin/login')
      .send(credentials)
      .expect(201);
    await call('post', 'auth/logout', shopper.body.accessToken).expect(201);
    await call('get', 'admin/summary', staffAgain.body.accessToken).expect(200);
  });
  it('retains disabled variants in private details and hides them publicly', async () => {
    const detail = await call('get', `admin/products/${productId}`).expect(200);
    expect(detail.body.variants[0]).toMatchObject({
      id: skuId,
      active: false,
      price: '490000',
    });
    const list = await call('get', 'admin/products?limit=100').expect(200);
    expect(
      list.body.items.find((p: { id: string }) => p.id === productId).variants,
    ).toHaveLength(1);
    // A product with no active variants is absent from the public catalog.
    await call('get', 'products/admin-' + suffix).expect(404);
    await call('get', 'admin/products/' + randomUUID()).expect(404);
  });
  it('preserves galleries on metadata edits and replaces galleries atomically', async () => {
    await call('patch', `admin/products/${productId}`)
      .send({ name: 'Renamed' })
      .expect(200);
    expect(await db.productImage.count({ where: { productId } })).toBe(2);
    await call('patch', `admin/products/${productId}`)
      .send({ images: [{ url: 'javascript:alert(1)', alt: 'bad' }] })
      .expect(400);
    expect(await db.productImage.count({ where: { productId } })).toBe(2);
    const updated = await call('patch', `admin/products/${productId}`)
      .send({ images: [{ url: 'assets/images/catalog/test.jpg', alt: 'New' }] })
      .expect(200);
    expect(updated.body.images).toHaveLength(1);
    expect(updated.body.images[0]).toMatchObject({ alt: 'New', position: 0 });
    await call('patch', `admin/products/${productId}`)
      .send({ images: null })
      .expect(400);
  });
  it('rejects stale stock writes without adding another movement', async () => {
    const body = { delta: 2, expectedVersion: 0, reason: 'Counted stock' };
    await call('post', `admin/inventory/${inventoryId}/adjust`)
      .send(body)
      .expect(201);
    await call('post', `admin/inventory/${inventoryId}/adjust`)
      .send(body)
      .expect(409);
    expect(
      (await db.inventory.findUniqueOrThrow({ where: { id: inventoryId } }))
        .quantity,
    ).toBe(5);
    expect(await db.inventoryMovement.count({ where: { inventoryId } })).toBe(
      1,
    );
    expect(await db.adminAuditEvent.count({
      where: { targetId: inventoryId, actorId: users[0], action: 'INVENTORY_ADJUSTED' },
    })).toBe(1);
  });
  it('loads another customer order and only advances legal versions, leaving COD unpaid', async () => {
    await db.productVariant.update({
      where: { id: skuId },
      data: { active: true },
    });
    const address = await call('post', 'users/me/addresses', customer)
      .send({
        recipient: 'Admin test',
        phone: '0901234567',
        address: '12 Test Street',
        label: 'Test',
      })
      .expect(201);
    await call('post', 'cart/items', customer)
      .send({ sku: 'admin-' + suffix, quantity: 1 })
      .expect(201);
    const order = await call('post', 'orders', customer)
      .set('Idempotency-Key', randomUUID())
      .send({
        addressId: address.body.id,
        shippingMethod: 'standard',
        expectedSubtotal: '490000',
      })
      .expect(201);
    orderId = order.body.id;
    await call('get', `admin/orders/${orderId}`, customer).expect(403);
    const detail = await call('get', `admin/orders/${orderId}`).expect(200);
    expect(detail.body.total).toBe('520000');
    await call('patch', `admin/orders/${orderId}/status`)
      .send({ status: 'DELIVERED', expectedVersion: 0 })
      .expect(409);
    for (const [version, status] of [
      'CONFIRMED',
      'SHIPPED',
      'DELIVERED',
    ].entries()) {
      const r = await call('patch', `admin/orders/${orderId}/status`)
        .send({ status, expectedVersion: version })
        .expect(200);
      expect(r.body.payment.status).toBe('PENDING');
      await call('patch', `admin/orders/${orderId}/status`)
        .send({ status, expectedVersion: version })
        .expect(409);
    }
    expect(await db.adminAuditEvent.count({
      where: { targetId: orderId, actorId: users[0], action: 'ORDER_STATUS_CHANGED' },
    })).toBe(3);
  });
  it('records authenticated actors and only successful catalog mutations, without request data', async () => {
    const created = await call('post', 'admin/products').send({
      slug: 'audit-' + suffix, name: 'Audit product', description: 'Private draft description',
      material: 'Cotton', style: '', categoryId, brandId,
    }).expect(201);
    extraProducts.push(created.body.id);
    const sku = await call('post', 'admin/skus').send({
      productId: created.body.id, sku: 'audit-' + suffix, size: 'S',
      color: 'White', colorHex: '#FFFFFF', price: '100000',
    }).expect(201);
    await call('patch', `admin/skus/${sku.body.id}`).send({ price: '120000' }).expect(200);
    await call('patch', `admin/products/${created.body.id}`).send({
      name: 'Audit edited', actorId: users[1],
    }).expect(400);
    await call('patch', `admin/products/${created.body.id}`).send({ name: 'Audit edited' }).expect(200);
    const events = await db.adminAuditEvent.findMany({
      where: { targetId: { in: [created.body.id, sku.body.id] } },
    });
    expect(events.map(e => e.action).sort()).toEqual([
      'PRODUCT_CREATED', 'PRODUCT_UPDATED', 'SKU_CREATED', 'SKU_UPDATED',
    ]);
    expect(events.every(e => e.actorId === users[0])).toBe(true);
    // Concurrent taxonomy renames have one winner; rejected writes have no events.
    for (const { kind, id } of taxonomies) {
      const actions = await db.adminAuditEvent.findMany({ where: { targetId: id } });
      expect(actions.map(e => e.action).sort()).toEqual(kind === 'categories'
        ? ['CATEGORY_CREATED', 'CATEGORY_RENAMED']
        : ['BRAND_CREATED', 'BRAND_RENAMED']);
    }
    const history = await call('get', 'admin/audit?limit=100').expect(200);
    const own = history.body.items.filter((e: { actorId: string }) => e.actorId === users[0]);
    expect(own.length).toBeGreaterThanOrEqual(4);
    for (const row of own) {
      expect(Object.keys(row).sort()).toEqual(['action', 'actorId', 'createdAt', 'details', 'id', 'targetId']);
    }
    expect(JSON.stringify(history.body)).not.toContain('Private draft description');
    const first = await call('get', 'admin/audit?limit=1').expect(200);
    const second = await call('get', 'admin/audit?limit=1&page=2').expect(200);
    expect(first.body.items[0].id).toBe(history.body.items[0].id);
    expect(second.body.items[0].id).toBe(history.body.items[1].id);
    expect(second.body.total).toBe(first.body.total);
  });
  it('rolls back product metadata and gallery if the audit insert fails', async () => {
    const before = await db.product.findUniqueOrThrow({
      where: { id: productId }, include: { images: true },
    });
    const eventCount = await db.adminAuditEvent.count({ where: { targetId: productId } });
    // Invalid internal UUID reaches the real PostgreSQL audit insertion, after
    // the product write. HTTP callers cannot select the authenticated actor.
    await expect(app.get(AdminService).updateProduct('invalid-actor', productId, {
      name: 'Must roll back',
      images: [{ url: 'https://example.com/rollback.jpg', alt: 'Rollback' }],
    })).rejects.toThrow();
    const after = await db.product.findUniqueOrThrow({
      where: { id: productId }, include: { images: true },
    });
    expect(after).toEqual(before);
    expect(await db.adminAuditEvent.count({ where: { targetId: productId } })).toBe(eventCount);
  });
});
