import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Admin search and overview with PostgreSQL', () => {
  let app: INestApplication, db: PrismaService, token: string, shopper: string;
  let categoryId: string, brandId: string, adminId: string, customerId: string;
  const suffix = randomUUID();
  const products: string[] = [],
    orders: string[] = [];
  const get = (path: string, auth = token) =>
    request(app.getHttpServer())
      .get('/api/v1/admin/' + path)
      .auth(auth, { type: 'bearer' });

  beforeAll(async () => {
    if (!new URL(process.env.TEST_DATABASE_URL!).pathname.endsWith('_test'))
      throw Error('Isolated test database required');
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    const register = async (name: string) =>
      (
        await request(app.getHttpServer())
          .post('/api/v1/auth/register')
          .send({
            email: `${name}-${suffix}@example.test`,
            name: `${name}-${suffix}`,
            password: 'Admin-search-tests-2026',
          })
          .expect(201)
      ).body;
    const admin = await register('staff');
    adminId = admin.user.id;
    token = admin.accessToken;
    await db.user.update({ where: { id: adminId }, data: { role: 'ADMIN' } });
    const customer = await register('buyer');
    customerId = customer.user.id;
    shopper = customer.accessToken;
    categoryId = (
      await db.category.create({
        data: { name: `Category-${suffix}`, slug: `search-${suffix}` },
      })
    ).id;
    brandId = (
      await db.brand.create({
        data: { name: `Brand-${suffix}`, slug: `search-${suffix}` },
      })
    ).id;
    for (const [index, quantity] of [0, 3, 8, 0].entries()) {
      const product = await db.product.create({
        data: {
          name: `Search_${index}-${suffix}`,
          slug: `search-${index}-${suffix}`,
          categoryId,
          brandId,
          description: '',
          material: 'Cotton',
          style: 'Tối giản',
          active: index !== 3,
          variants: {
            create: {
              sku: `SKU_${index}-${suffix}`,
              size: 'M',
              color: 'Black',
              colorHex: '#000000',
              price: '490000',
              inventory: { create: { quantity } },
            },
          },
        },
      });
      products.push(product.id);
    }
    for (const status of ['PENDING', 'DELIVERED'] as const) {
      const order = await db.order.create({
        data: {
          userId: customerId,
          status,
          idempotencyKey: randomUUID(),
          requestHash: suffix,
          addressSnapshot: { recipient: 'Test buyer' },
          subtotal: '490000',
          shipping: '30000',
          total: '520000',
        },
      });
      orders.push(order.id);
    }
  });
  afterAll(async () => {
    if (db) {
      await db.order.deleteMany({ where: { id: { in: orders } } });
      await db.inventory.deleteMany({
        where: { variant: { productId: { in: products } } },
      });
      await db.productVariant.deleteMany({
        where: { productId: { in: products } },
      });
      await db.product.deleteMany({ where: { id: { in: products } } });
      if (categoryId) await db.category.delete({ where: { id: categoryId } });
      if (brandId) await db.brand.delete({ where: { id: brandId } });
      await db.user.deleteMany({
        where: { id: { in: [adminId, customerId].filter(Boolean) } },
      });
    }
    await app?.close();
  });
  it('searches the whole catalog with stable pagination, case-insensitive SKU and combined filters', async () => {
    const first = (await get(`products?q=${suffix}&limit=2`).expect(200)).body;
    const second = (
      await get(`products?q=${suffix}&limit=2&page=2`).expect(200)
    ).body;
    expect(first.total).toBe(4);
    expect(second.total).toBe(4);
    expect(
      new Set(
        [...first.items, ...second.items].map((row: { id: string }) => row.id),
      ).size,
    ).toBe(4);
    const active = (await get(`products?q=${suffix}&status=active`).expect(200))
      .body;
    expect(active.total).toBe(3);
    expect(active.items.every((row: { active: boolean }) => row.active)).toBe(
      true,
    );
    expect(
      (await get(`products?q=sku_1-${suffix}`).expect(200)).body.items.map(
        (row: { id: string }) => row.id,
      ),
    ).toEqual([products[1]]);
    expect(
      (await get(`products?q=${encodeURIComponent('%' + suffix)}`).expect(200))
        .body.total,
    ).toBe(0);
    expect(
      (await get(`products?q=Brand-${suffix}`).expect(200)).body.total,
    ).toBe(4);
  });
  it('uses matching stock thresholds and excludes hidden products from alerts', async () => {
    for (const [filter, expected] of [
      ['out', 0],
      ['low', 3],
    ] as const) {
      const result = (
        await get(`inventory?q=${suffix}&status=${filter}`).expect(200)
      ).body;
      expect(result.total).toBe(1);
      expect(result.items[0].quantity).toBe(expected);
    }
    expect(
      (await get(`inventory?q=${suffix}&status=in_stock`).expect(200)).body
        .total,
    ).toBe(2);
    expect((await get(`inventory?q=${suffix}`).expect(200)).body.total).toBe(4);
  });
  it('searches order codes, customers and status together without exposing staff or secrets', async () => {
    const order = await db.order.findUniqueOrThrow({
      where: { id: orders[0] },
    });
    expect(
      (
        await get(`orders?q=${order.code}&status=PENDING`).expect(200)
      ).body.items.map((row: { id: string }) => row.id),
    ).toEqual([order.id]);
    expect(
      (await get(`orders?q=buyer-${suffix}&status=DELIVERED`).expect(200)).body
        .total,
    ).toBe(1);
    const customers = (await get(`users?q=${suffix}`).expect(200)).body;
    expect(customers.total).toBe(1);
    expect(customers.items[0].id).toBe(customerId);
    expect(customers.items[0].passwordHash).toBeUndefined();
    expect(customers.items[0].refreshTokens).toBeUndefined();
    expect(customers.items[0].active).toBe(true);
    expect((await get(`users?q=staff-${suffix}`).expect(200)).body.total).toBe(
      0,
    );
  });
  it('validates filters and preserves authorization', async () => {
    await get('products?status=PENDING').expect(400);
    await get('orders?status=INVALID').expect(400);
    await get('products?q=' + 'x'.repeat(101)).expect(400);
    await get('inventory?page=0').expect(400);
    await get('summary', shopper).expect(403);
    await get('products', shopper).expect(403);
    await request(app.getHttpServer()).get('/api/v1/admin/summary').expect(401);
  });
  it('returns real order distribution, recent orders and stock alerts from a consistent snapshot', async () => {
    const summary = (await get('summary').expect(200)).body;
    expect(
      Object.values<number>(summary.orderStatuses).reduce((a, b) => a + b, 0),
    ).toBe(summary.orders);
    expect(summary.activeProducts).toBe(
      await db.product.count({ where: { active: true } }),
    );
    expect(summary.lowStockVariants).toBe(
      await db.inventory.count({
        where: {
          quantity: { gt: 0, lte: 5 },
          variant: { active: true, product: { active: true } },
        },
      }),
    );
    expect(summary.outOfStockVariants).toBe(
      await db.inventory.count({
        where: {
          quantity: 0,
          variant: { active: true, product: { active: true } },
        },
      }),
    );
    const recent = await db.order.findMany({
      take: 5,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    });
    expect(summary.recentOrders.map((row: { id: string }) => row.id)).toEqual(
      recent.map((row: { id: string }) => row.id),
    );
    expect(
      summary.recentOrders.every(
        (row: { user: Record<string, unknown> }) =>
          row.user && !('email' in row.user),
      ),
    ).toBe(true);
    expect(Number.isNaN(Date.parse(summary.generatedAt))).toBe(false);
    expect(typeof summary.paidRevenueVnd).toBe('string');
  });
});
