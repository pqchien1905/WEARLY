import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { CollectionsService } from '../src/modules/products/collections.service';
import * as audit from '../src/modules/admin/audit';

describe('Admin collections workspace on PostgreSQL', () => {
  let app: INestApplication,
    db: PrismaService,
    categoryId: string,
    brandId: string;
  const marker = 'collections-' + randomUUID(),
    users: string[] = [],
    ids: string[] = [],
    products: string[] = [];
  const tokens: Record<string, string> = {};
  const call = (
    method: 'get' | 'post' | 'patch' | 'delete',
    path = '',
    role = 'ADMIN',
  ) =>
    request(app.getHttpServer())
      [method]('/api/v1/admin/collections' + path)
      .auth(tokens[role], { type: 'bearer' });
  const list = async (query = {}) =>
    (
      await call('get')
        .query({ q: marker, ...query })
        .expect(200)
    ).body;
  beforeAll(async () => {
    if (!new URL(process.env.TEST_DATABASE_URL!).pathname.endsWith('_test'))
      throw Error('Isolated test DB required');
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
          email: `${role}-${marker}@example.test`,
          password: 'Collections-test-2026',
        })
        .expect(201);
      users.push(r.body.user.id);
      tokens[role] = r.body.accessToken;
      if (role !== 'CUSTOMER')
        await db.user.update({ where: { id: r.body.user.id }, data: { role } });
    }
    categoryId = (
      await db.category.create({ data: { name: marker, slug: marker } })
    ).id;
    brandId = (await db.brand.create({ data: { name: marker, slug: marker } }))
      .id;
    for (let i = 0; i < 23; i++)
      ids.push(
        (
          await db.storeCollection.create({
            data: {
              slug: `${marker}-${i}`,
              title: `Áo Đầm ${String(i).padStart(2, '0')} ${marker}`,
              style: `${marker}-${i}`,
              description: '',
              position: i,
              active: i !== 1,
            },
          })
        ).id,
      );
    for (let i = 0; i < 3; i++)
      products.push(
        (
          await db.product.create({
            data: {
              slug: `${marker}-p${i}`,
              name: `Áo Đầm ${i}`,
              style: `${marker}-0`,
              categoryId,
              brandId,
              active: i < 2,
              description: '',
              material: '',
              images: { create: { url: 'assets/images/shirt.jpg', alt: 'Áo' } },
              variants: {
                create: {
                  sku: `${marker}-${i}`,
                  size: 'M',
                  color: 'Đen',
                  colorHex: '#000000',
                  price: 120000,
                  inventory: { create: { quantity: 7 } },
                },
              },
            },
          })
        ).id,
      );
    await db.storeCollection.update({
      where: { id: ids[0] },
      data: { coverProductId: products[0] },
    });
  });
  afterAll(async () => {
    try {
      if (db) {
        await db.adminAuditEvent.deleteMany({
          where: { actorId: { in: users } },
        });
        await db.storeCollection.deleteMany({
          where: { slug: { startsWith: marker } },
        });
        await db.inventory.deleteMany({
          where: { variant: { productId: { in: products } } },
        });
        await db.productVariant.deleteMany({
          where: { productId: { in: products } },
        });
        await db.product.deleteMany({ where: { id: { in: products } } });
        if (categoryId) await db.category.delete({ where: { id: categoryId } });
        if (brandId) await db.brand.delete({ where: { id: brandId } });
        await db.user.deleteMany({ where: { id: { in: users } } });
      }
    } finally {
      await app?.close();
    }
  });

  it('searches Vietnamese and literal characters, filters and clamps pagination', async () => {
    const first = await list();
    expect(first.total).toBe(23);
    expect(first.items).toHaveLength(10);
    expect(first.items[0]).toMatchObject({
      id: ids[0],
      productCount: 2,
      totalProducts: 3,
      published: true,
      coverFallback: false,
      cover: { productId: products[0] },
    });
    expect(await list({ page: 999 })).toMatchObject({ page: 3, total: 23 });
    expect((await list({ q: `ao dam 00 ${marker}` })).items[0].id).toBe(ids[0]);
    expect((await list({ q: ids[0].toUpperCase() })).items[0].id).toBe(ids[0]);
    for (const q of [marker + '%', marker + '_', marker + '\\'])
      expect((await list({ q })).total).toBe(0);
    expect((await list({ status: 'published' })).total).toBe(1);
    expect((await list({ status: 'hidden' })).total).toBe(1);
    expect((await list({ status: 'waiting' })).total).toBe(21);
    expect((await list({ sort: 'title_desc' })).items[0].id).toBe(ids[22]);
    expect((await list({ sort: 'products_desc' })).items[0].id).toBe(ids[0]);
  });
  it('returns summary, detailed membership and paginated cover choices without hidden products', async () => {
    const summary = (await call('get', '/summary').expect(200)).body;
    expect(summary.total).toBe(await db.storeCollection.count());
    expect(summary.total).toBe(
      summary.published + summary.hidden + summary.waiting,
    );
    const detail = (await call('get', '/' + ids[0]).expect(200)).body;
    expect(detail.totalProducts).toBe(3);
    expect(detail.recentProducts).toHaveLength(3);
    expect(
      detail.recentProducts.filter((p: { published: boolean }) => p.published),
    ).toHaveLength(2);
    const cover = (
      await call('get', '/covers')
        .query({ style: marker + '-0', limit: 1 })
        .expect(200)
    ).body;
    const next = (
      await call('get', '/covers')
        .query({ style: marker + '-0', limit: 1, page: 2 })
        .expect(200)
    ).body;
    expect(cover.total).toBe(2);
    expect(next.items[0].id).not.toBe(cover.items[0].id);
    const search = (
      await call('get', '/covers')
        .query({ style: marker + '-0', q: 'ao dam 1' })
        .expect(200)
    ).body;
    expect(search.items.map((p: { id: string }) => p.id)).toEqual([
      products[1],
    ]);
    expect((await call('get', '/styles').expect(200)).body.styles).toContain(
      marker + '-22',
    );
    const all = await request(app.getHttpServer())
      .get('/api/v1/admin/products')
      .auth(tokens.ADMIN, { type: 'bearer' })
      .query({ style: marker + '-0' })
      .expect(200);
    expect(all.body.total).toBe(3);
  });
  it('uses the same ordered image in admin, picker and storefront', async () => {
    const added = await db.productImage.create({
      data: {
        productId: products[0],
        url: 'assets/images/shirt.jpg',
        alt: 'Second image',
        position: 1,
      },
    });
    try {
      const expected = await db.productImage.findFirstOrThrow({
        where: { productId: products[0] },
        orderBy: [{ position: 'asc' }, { id: 'asc' }],
      });
      const detail = (await call('get', '/' + ids[0]).expect(200)).body;
      const publicPage = (
        await request(app.getHttpServer())
          .get('/api/v1/collections/' + marker + '-0')
          .expect(200)
      ).body;
      const picker = (
        await call('get', '/covers')
          .query({ style: marker + '-0', q: 'ao dam 0' })
          .expect(200)
      ).body;
      expect(detail.cover.alt).toBe(expected.alt);
      expect(publicPage.collection.cover.alt).toBe(expected.alt);
      expect(picker.items[0].images[0].alt).toBe(expected.alt);
    } finally {
      await db.productImage.delete({ where: { id: added.id } });
    }
  });
  it('uses a real fallback cover when the selected product is hidden', async () => {
    await db.product.update({
      where: { id: products[0] },
      data: { active: false },
    });
    try {
      const detail = (await call('get', '/' + ids[0]).expect(200)).body;
      expect(detail).toMatchObject({
        coverProductId: products[0],
        coverFallback: true,
        cover: { productId: products[1] },
        productCount: 1,
        totalProducts: 3,
      });
    } finally {
      await db.product.update({
        where: { id: products[0] },
        data: { active: true },
      });
    }
  });
  it('validates queries and permissions on every new endpoint', async () => {
    for (const path of [
      '',
      '/summary',
      '/styles',
      '/' + ids[0],
      '/covers?style=' + marker + '-0',
    ]) {
      await request(app.getHttpServer())
        .get('/api/v1/admin/collections' + path)
        .expect(401);
      for (const role of ['CUSTOMER', 'WAREHOUSE', 'SUPPORT'])
        await call('get', path, role).expect(403);
      await call('get', path, 'MANAGER').expect(200);
    }
    for (const query of [
      { q: 'x'.repeat(101) },
      { page: 0 },
      { limit: 101 },
      { status: 'active' },
      { sort: 'drop table' },
    ])
      await call('get').query(query).expect(400);
    await call('get', '/covers').expect(400);
    await call('get', '/covers')
      .query({ style: 'x'.repeat(101) })
      .expect(400);
    await call('get', '/invalid').expect(400);
    await call('get', '/' + randomUUID()).expect(404);
    for (const role of ['CUSTOMER', 'WAREHOUSE', 'SUPPORT'])
      await call('delete', '/' + ids[0], role)
        .send({ expectedVersion: 1 })
        .expect(403);
  });
  it('rechecks content permission inside writes, even after guard authorization', async () => {
    const service = app.get(CollectionsService);
    for (const actor of users.slice(2))
      await expect(
        service.create(actor, {
          title: 'Blocked',
          slug: marker + '-blocked',
          style: marker + '-blocked',
          description: '',
        }),
      ).rejects.toMatchObject({ status: 403 });
    await db.user.update({ where: { id: users[1] }, data: { active: false } });
    try {
      await expect(
        service.update(users[1], ids[0], {
          expectedVersion: 1,
          title: 'Blocked',
        }),
      ).rejects.toMatchObject({ status: 403 });
      await expect(service.remove(users[1], ids[0], 1)).rejects.toMatchObject({
        status: 403,
      });
    } finally {
      await db.user.update({ where: { id: users[1] }, data: { active: true } });
    }
  });
  it('toggles publication and rejects stale versions without changing products', async () => {
    await call('patch', '/' + ids[0])
      .send({ expectedVersion: 1, active: false })
      .expect(200);
    expect((await call('get', '/' + ids[0]).expect(200)).body.published).toBe(
      false,
    );
    await request(app.getHttpServer())
      .get('/api/v1/collections/' + marker + '-0')
      .expect(404);
    await call('patch', '/' + ids[0])
      .send({ expectedVersion: 1, active: true })
      .expect(409);
    await call('patch', '/' + ids[0])
      .send({ expectedVersion: 2, active: true })
      .expect(200);
    expect(
      (
        await request(app.getHttpServer())
          .get('/api/v1/collections/' + marker + '-0')
          .expect(200)
      ).body.total,
    ).toBe(2);
  });
  it('requires a valid deletion version and rolls back failed audits', async () => {
    for (const body of [
      {},
      { expectedVersion: null },
      { expectedVersion: 0 },
      { expectedVersion: 1.5 },
      { expectedVersion: 1, force: true },
    ])
      await call('delete', '/' + ids[2])
        .send(body)
        .expect(400);
    await call('delete', '/' + ids[2])
      .send({ expectedVersion: 9 })
      .expect(409);
    const before = await db.storeCollection.findUnique({
      where: { id: ids[2] },
    });
    const spy = jest
      .spyOn(audit, 'recordAdminActivity')
      .mockRejectedValueOnce(new Error('Audit unavailable'));
    try {
      await call('delete', '/' + ids[2])
        .send({ expectedVersion: 1 })
        .expect(500);
    } finally {
      spy.mockRestore();
    }
    expect(
      await db.storeCollection.findUnique({ where: { id: ids[2] } }),
    ).toEqual(before);
  });
  it('arbitrates concurrent deletes with exactly one audit', async () => {
    const result = await Promise.all(
      ['ADMIN', 'MANAGER'].map((role) =>
        call('delete', '/' + ids[3], role).send({ expectedVersion: 1 }),
      ),
    );
    expect(result.map((r) => r.status).sort()).toEqual([200, 404]);
    expect(
      await db.adminAuditEvent.count({
        where: { action: 'COLLECTION_DELETED', targetId: ids[3] },
      }),
    ).toBe(1);
  });
  it('deletes the collection page while preserving products, stock and immutable audit', async () => {
    const before = await db.product.findMany({
      where: { id: { in: products } },
      orderBy: { id: 'asc' },
      include: { variants: { include: { inventory: true } } },
    });
    await call('delete', '/' + ids[0], 'MANAGER')
      .send({ expectedVersion: 3 })
      .expect(200);
    await call('get', '/' + ids[0]).expect(404);
    await request(app.getHttpServer())
      .get('/api/v1/collections/' + marker + '-0')
      .expect(404);
    expect(
      await db.product.findMany({
        where: { id: { in: products } },
        orderBy: { id: 'asc' },
        include: { variants: { include: { inventory: true } } },
      }),
    ).toEqual(before);
    const event = await db.adminAuditEvent.findFirstOrThrow({
      where: { targetId: ids[0], action: 'COLLECTION_DELETED' },
    });
    expect(event.actorId).toBe(users[1]);
    expect(event.details).toMatchObject({
      before: { slug: marker + '-0', version: 3 },
    });
  });
});
