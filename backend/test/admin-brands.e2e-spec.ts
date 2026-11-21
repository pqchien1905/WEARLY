import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import * as audit from '../src/modules/admin/audit';

describe('Brands workspace with PostgreSQL', () => {
  let app: INestApplication,
    db: PrismaService,
    categoryId: string,
    productId: string;
  const marker = `brands-${randomUUID()}`,
    users: string[] = [],
    ids: string[] = [];
  const tokens: Record<string, string> = {};
  const call = (
    method: 'get' | 'post' | 'patch' | 'delete',
    path: string,
    role = 'ADMIN',
  ) =>
    request(app.getHttpServer())
      [method]('/api/v1/' + path)
      .auth(tokens[role], { type: 'bearer' });
  const list = async (query = {}) =>
    (
      await call('get', 'admin/brands')
        .query({ q: marker, ...query })
        .expect(200)
    ).body;
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
          email: `${role}-${marker}@example.test`,
          password: 'Brands-test-2026',
        })
        .expect(201);
      users.push(r.body.user.id);
      tokens[role] = r.body.accessToken;
      if (role !== 'CUSTOMER')
        await db.user.update({ where: { id: r.body.user.id }, data: { role } });
    }
    for (let i = 0; i < 23; i++)
      ids.push(
        (
          await db.brand.create({
            data: {
              slug: `${marker}-${i}`,
              name: `Áo Đầm ${String(i).padStart(2, '0')} ${marker}`,
            },
          })
        ).id,
      );
    categoryId = (
      await db.category.create({ data: { name: marker, slug: marker } })
    ).id;
    productId = (
      await db.product.create({
        data: {
          slug: marker,
          name: marker,
          brandId: ids[0],
          categoryId,
          description: '',
          material: '',
          style: '',
          images: { create: { url: 'assets/images/shirt.jpg', alt: 'Áo' } },
          variants: {
            create: {
              sku: marker,
              size: 'M',
              color: 'Trắng',
              colorHex: '#ffffff',
              price: '120000',
              inventory: { create: { quantity: 7 } },
            },
          },
        },
      })
    ).id;
  });
  afterAll(async () => {
    try {
      if (db) {
        await db.adminAuditEvent.deleteMany({
          where: { actorId: { in: users } },
        });
        if (productId) {
          await db.inventory.deleteMany({ where: { variant: { productId } } });
          await db.productVariant.deleteMany({ where: { productId } });
          await db.product.delete({ where: { id: productId } });
        }
        await db.brand.deleteMany({ where: { id: { in: ids } } });
        if (categoryId) await db.category.delete({ where: { id: categoryId } });
        await db.user.deleteMany({ where: { id: { in: users } } });
      }
    } finally {
      await app?.close();
    }
  });

  it('searches Vietnamese, literal wildcard characters, filters, sorts and paginates at the database', async () => {
    const first = await list({ limit: 20 });
    expect(first.total).toBe(23);
    expect(first.items).toHaveLength(20);
    expect(first.items[0]).toMatchObject({
      id: ids[0],
      _count: { products: 1 },
      publishedProducts: 1,
    });
    const second = await list({ limit: 20, page: 2 });
    expect(second.items).toHaveLength(3);
    expect(
      second.items.some((r: { id: string }) =>
        first.items.some((f: { id: string }) => f.id === r.id),
      ),
    ).toBe(false);
    expect((await list({ q: `ao dam 00 ${marker}` })).items[0].id).toBe(ids[0]);
    expect((await list({ q: ids[0] })).items[0].id).toBe(ids[0]);
    expect((await list({ q: ids[0].toUpperCase() })).items[0].id).toBe(ids[0]);
    for (const literal of ['%', '_', '\\'])
      expect((await list({ q: marker + literal })).total).toBe(0);
    expect((await list({ coverage: 'empty' })).total).toBe(22);
    expect((await list({ coverage: 'populated' })).total).toBe(1);
    expect((await list({ coverage: 'published' })).total).toBe(1);
    expect((await list({ coverage: 'unpublished' })).total).toBe(22);
    expect((await list({ sort: 'products_desc' })).items[0].id).toBe(ids[0]);
    expect((await list({ sort: 'name_desc' })).items[0].id).toBe(ids[22]);
    const last = await list({ page: 999, limit: 20 });
    expect(last.page).toBe(2);
    expect(last.items).toHaveLength(3);
  });
  it('returns exact summary and detail matching public visibility and all products', async () => {
    const summary = (await call('get', 'admin/brands/summary').expect(200))
      .body;
    expect(summary.total).toBe(await db.brand.count());
    expect(summary.products).toBe(await db.product.count());
    expect(summary.empty).toBe(
      await db.brand.count({ where: { products: { none: {} } } }),
    );
    const publicList = (
      await request(app.getHttpServer()).get('/api/v1/brands').expect(200)
    ).body;
    expect(summary.published).toBe(publicList.length);
    expect(publicList.some((c: { id: string }) => c.id === ids[0])).toBe(true);
    expect(publicList.some((c: { id: string }) => c.id === ids[1])).toBe(false);
    const detail = (await call('get', `admin/brands/${ids[0]}`).expect(200))
      .body;
    expect(detail).toMatchObject({
      id: ids[0],
      _count: { products: 1 },
      publishedProducts: 1,
    });
    expect(detail.recentProducts).toEqual([
      expect.objectContaining({
        id: productId,
        published: true,
        active: true,
        images: [{ url: 'assets/images/shirt.jpg', alt: 'Áo' }],
      }),
    ]);
    await db.product.update({
      where: { id: productId },
      data: { active: false },
    });
    expect((await list({ coverage: 'published' })).total).toBe(0);
    expect((await list({ coverage: 'populated' })).total).toBe(1);
    expect(
      (await call('get', `admin/brands/${ids[0]}`).expect(200)).body
        .recentProducts[0].published,
    ).toBe(false);
    await db.product.update({
      where: { id: productId },
      data: { active: true },
    });
  });
  it('filters products and inventory by brand without relying on a product search', async () => {
    const inventory = await call('get', 'admin/inventory')
      .query({ brandId: ids[0] })
      .expect(200);
    expect(inventory.body.total).toBe(1);
    expect(inventory.body.items[0].variant.product.brand.id).toBe(ids[0]);
    expect(
      (
        await call('get', 'admin/inventory')
          .query({ brandId: ids[1] })
          .expect(200)
      ).body.total,
    ).toBe(0);
    await call('get', 'admin/inventory')
      .query({ brandId: 'invalid' })
      .expect(400);
    const products = await call('get', 'admin/products')
      .query({ brandId: ids[0] })
      .expect(200);
    expect(products.body.total).toBe(1);
    const brand = await db.brand.findUniqueOrThrow({ where: { id: ids[0] } });
    const published = await request(app.getHttpServer())
      .get('/api/v1/products')
      .query({ brand: brand.slug })
      .expect(200);
    expect(published.body.total).toBe(1);
    expect(published.body.items[0].id).toBe(productId);
    const variant = await db.productVariant.findFirstOrThrow({
      where: { productId },
    });
    try {
      await db.productVariant.update({
        where: { id: variant.id },
        data: { active: false },
      });
      const hidden = (await call('get', `admin/brands/${ids[0]}`).expect(200))
        .body;
      expect(hidden._count.products).toBe(1);
      expect(hidden.publishedProducts).toBe(0);
      expect(hidden.recentProducts[0].published).toBe(false);
      expect(
        (
          await request(app.getHttpServer())
            .get('/api/v1/products')
            .query({ brand: brand.slug })
            .expect(200)
        ).body.total,
      ).toBe(0);
    } finally {
      await db.productVariant.update({
        where: { id: variant.id },
        data: { active: true },
      });
    }
  });
  it('validates inputs, creates a unique slug once, permits same name under distinct slugs', async () => {
    for (const body of [
      { name: '  ', slug: marker },
      { name: 'Áo', slug: 'Đầm' },
      { name: 'Áo', slug: 'a--b' },
      { name: 'x'.repeat(101), slug: marker },
      { name: 'Áo', slug: marker, parentId: ids[0] },
    ])
      await call('post', 'admin/brands').send(body).expect(400);
    const responses = await Promise.all(
      ['ADMIN', 'MANAGER'].map((role) =>
        call('post', 'admin/brands', role).send({
          name: '  Đầm & Áo  ',
          slug: marker,
        }),
      ),
    );
    expect(responses.map((r) => r.status).sort()).toEqual([201, 409]);
    const created = responses.find((r) => r.status === 201)!.body;
    ids.push(created.id);
    expect(created.name).toBe('Đầm & Áo');
    expect(responses.find((r) => r.status === 409)!.body.error.code).toBe(
      'TAXONOMY_SLUG_EXISTS',
    );
    const sameName = (
      await call('post', 'admin/brands')
        .send({ name: 'Đầm & Áo', slug: marker + '-other' })
        .expect(201)
    ).body;
    ids.push(sameName.id);
    expect(await db.brand.count({ where: { slug: marker } })).toBe(1);
  });
  it('rejects stale and ABA edits, duplicate submission and preserves immutable slug', async () => {
    const before = await db.brand.findUniqueOrThrow({
      where: { id: ids[2] },
    });
    const path = `admin/brands/${before.id}`;
    const responses = await Promise.all(
      ['ADMIN', 'MANAGER'].map((role, i) =>
        call('patch', path, role).send({
          name: `Đổi tên ${i}`,
          expectedName: before.name,
          expectedUpdatedAt: before.updatedAt.toISOString(),
        }),
      ),
    );
    expect(responses.map((r) => r.status).sort()).toEqual([200, 409]);
    const winner = responses.find((r) => r.status === 200)!.body;
    await call('patch', path)
      .send({
        name: before.name,
        expectedName: winner.name,
        expectedUpdatedAt: winner.updatedAt,
      })
      .expect(200);
    await call('patch', path)
      .send({
        name: 'Stale edit',
        expectedName: before.name,
        expectedUpdatedAt: before.updatedAt.toISOString(),
      })
      .expect(409);
    await call('patch', path)
      .send({ name: 'Slug edit', expectedName: before.name, slug: 'changed' })
      .expect(400);
    expect(
      (await db.brand.findUniqueOrThrow({ where: { id: before.id } })).slug,
    ).toBe(before.slug);
    const count = await db.adminAuditEvent.count({
      where: { targetId: before.id },
    });
    await call('patch', path)
      .send({ name: before.name, expectedName: before.name })
      .expect(200);
    expect(
      await db.adminAuditEvent.count({ where: { targetId: before.id } }),
    ).toBe(count);
  });
  it('renames consistently in products, inventory and storefront without modifying stock or links', async () => {
    const before = await db.brand.findUniqueOrThrow({
      where: { id: ids[0] },
    });
    const stock = await db.inventory.findFirstOrThrow({
      where: { variant: { productId } },
    });
    const name = `Thương hiệu đổi tên ${marker}`;
    await call('patch', `admin/brands/${before.id}`)
      .send({
        name,
        expectedName: before.name,
        expectedUpdatedAt: before.updatedAt.toISOString(),
      })
      .expect(200);
    const product = (
      await call('get', `admin/products/${productId}`).expect(200)
    ).body;
    expect(product.brand).toMatchObject({
      id: before.id,
      name,
      slug: before.slug,
    });
    const inventory = (
      await call('get', 'admin/inventory')
        .query({ brandId: before.id, productId })
        .expect(200)
    ).body;
    expect(inventory.items[0].variant.product.brand.name).toBe(name);
    expect(await db.inventory.findUnique({ where: { id: stock.id } })).toEqual(
      stock,
    );
    const publicList = (
      await request(app.getHttpServer()).get('/api/v1/brands').expect(200)
    ).body;
    expect(publicList).toContainEqual(
      expect.objectContaining({ id: before.id, slug: before.slug, name }),
    );
    expect(
      (
        await request(app.getHttpServer())
          .get('/api/v1/products')
          .query({ brand: before.slug, q: marker })
          .expect(200)
      ).body.items[0].id,
    ).toBe(productId);
    // Even hidden products keep their brand until explicitly reassigned.
    const current = await db.brand.findUniqueOrThrow({
      where: { id: before.id },
    });
    await db.product.update({
      where: { id: productId },
      data: { active: false },
    });
    const blocked = await call('delete', `admin/brands/${before.id}`)
      .send({ expectedUpdatedAt: current.updatedAt.toISOString() })
      .expect(409);
    expect(blocked.body.error.code).toBe('BRAND_IN_USE');
    await db.product.update({
      where: { id: productId },
      data: { active: true },
    });
    await call('patch', `admin/brands/${before.id}`)
      .send({ name, expectedName: name, active: false })
      .expect(400);
    expect(
      (await db.product.findUniqueOrThrow({ where: { id: productId } }))
        .brandId,
    ).toBe(before.id);
  });
  it('enforces role/auth, missing records and query validation on server', async () => {
    for (const path of [
      'admin/brands',
      'admin/brands/summary',
      `admin/brands/${ids[0]}`,
    ]) {
      await request(app.getHttpServer())
        .get('/api/v1/' + path)
        .expect(401);
      for (const role of ['CUSTOMER', 'WAREHOUSE', 'SUPPORT'])
        await call('get', path, role).expect(403);
      await call('get', path, 'MANAGER').expect(200);
    }
    for (const role of ['CUSTOMER', 'WAREHOUSE', 'SUPPORT']) {
      await call('post', 'admin/brands', role)
        .send({ name: 'No', slug: 'no' })
        .expect(403);
      await call('patch', `admin/brands/${ids[0]}`, role)
        .send({ name: 'No', expectedName: 'No' })
        .expect(403);
      await call('delete', `admin/brands/${ids[0]}`, role)
        .send({ expectedUpdatedAt: new Date().toISOString() })
        .expect(403);
    }
    for (const query of [
      { q: 'x'.repeat(101) },
      { page: 0 },
      { limit: 101 },
      { sort: 'name;DELETE' },
      { coverage: 'active' },
    ])
      await call('get', 'admin/brands').query(query).expect(400);
    await call('get', `admin/brands/${randomUUID()}`).expect(404);
    await call('get', 'admin/brands/invalid').expect(400);
  });
  it('rolls back rename when audit cannot be recorded', async () => {
    const before = await db.brand.findUniqueOrThrow({
      where: { id: ids[3] },
    });
    const spy = jest
      .spyOn(audit, 'recordAdminActivity')
      .mockRejectedValueOnce(new Error('Test audit unavailable'));
    try {
      await call('patch', `admin/brands/${before.id}`)
        .send({ name: 'Not committed', expectedName: before.name })
        .expect(500);
    } finally {
      spy.mockRestore();
    }
    expect(
      await db.brand.findUniqueOrThrow({ where: { id: before.id } }),
    ).toEqual(before);
  });

  it('deletes only a confirmed empty brand, rejects stale versions and retains its audit', async () => {
    const row = await db.brand.findUniqueOrThrow({ where: { id: ids[4] } });
    const path = `admin/brands/${row.id}`;
    for (const body of [
      {},
      { expectedUpdatedAt: null },
      { expectedUpdatedAt: 'bad' },
      { expectedUpdatedAt: row.updatedAt.toISOString(), force: true },
    ]) {
      await call('delete', path).send(body).expect(400);
    }
    await call('delete', path)
      .send({ expectedUpdatedAt: new Date(0).toISOString() })
      .expect(409);
    expect(await db.brand.findUnique({ where: { id: row.id } })).not.toBeNull();
    const response = await call('delete', path, 'MANAGER')
      .send({ expectedUpdatedAt: row.updatedAt.toISOString() })
      .expect(200);
    expect(response.body).toEqual({ id: row.id, deleted: true });
    expect(await db.brand.findUnique({ where: { id: row.id } })).toBeNull();
    const event = await db.adminAuditEvent.findFirstOrThrow({
      where: { targetId: row.id, action: 'BRAND_DELETED' },
    });
    expect(event.actorId).toBe(users[1]);
    expect(event.details).toEqual({ before: { slug: row.slug }, after: {} });
    await call('delete', path)
      .send({ expectedUpdatedAt: row.updatedAt.toISOString() })
      .expect(404);
    expect(
      await db.adminAuditEvent.count({
        where: { targetId: row.id, action: 'BRAND_DELETED' },
      }),
    ).toBe(1);
  });

  it('rolls back brand deletion when audit fails and arbitrates concurrent deletes', async () => {
    const row = await db.brand.findUniqueOrThrow({ where: { id: ids[5] } });
    const path = `admin/brands/${row.id}`;
    const body = { expectedUpdatedAt: row.updatedAt.toISOString() };
    const spy = jest
      .spyOn(audit, 'recordAdminActivity')
      .mockRejectedValueOnce(new Error('Audit unavailable'));
    try {
      await call('delete', path).send(body).expect(500);
    } finally {
      spy.mockRestore();
    }
    expect(await db.brand.findUnique({ where: { id: row.id } })).toEqual(row);
    const result = await Promise.all(
      ['ADMIN', 'MANAGER'].map((role) => call('delete', path, role).send(body)),
    );
    expect(result.map((r) => r.status).sort()).toEqual([200, 404]);
    expect(
      await db.adminAuditEvent.count({
        where: { targetId: row.id, action: 'BRAND_DELETED' },
      }),
    ).toBe(1);
  });

  it('cannot remove a brand while a product is concurrently attached', async () => {
    const row = await db.brand.findUniqueOrThrow({ where: { id: ids[6] } });
    const [removed, created] = await Promise.allSettled([
      call('delete', `admin/brands/${row.id}`).send({
        expectedUpdatedAt: row.updatedAt.toISOString(),
      }),
      db.product.create({
        data: {
          name: marker + '-race',
          slug: marker + '-race',
          brandId: row.id,
          categoryId,
          description: '',
          material: '',
          style: '',
        },
      }),
    ]);
    try {
      expect(removed.status).toBe('fulfilled');
      if (removed.status !== 'fulfilled') throw removed.reason;
      expect([200, 409]).toContain(removed.value.status);
      if (removed.value.status === 200) {
        expect(created.status).toBe('rejected');
        expect(await db.product.count({ where: { brandId: row.id } })).toBe(0);
      } else {
        expect(created.status).toBe('fulfilled');
        expect(
          await db.brand.findUnique({ where: { id: row.id } }),
        ).not.toBeNull();
      }
    } finally {
      if (created.status === 'fulfilled')
        await db.product.delete({ where: { id: created.value.id } });
    }
  });
});
