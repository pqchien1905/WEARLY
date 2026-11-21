import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Database collections, publication and staff editing', () => {
  let app: INestApplication, db: PrismaService;
  let token: string, userId: string, categoryId: string, brandId: string;
  let collectionId: string;
  const prefix = 'collection-' + randomUUID();
  const ids: string[] = [];
  const style = prefix + '-style';
  const get = (route: string) =>
    request(app.getHttpServer()).get('/api/v1/' + route);
  const admin = (method: 'get' | 'post' | 'patch', route = '', body?: object) =>
    request(app.getHttpServer())
      [method]('/api/v1/admin/collections' + route)
      .auth(token, { type: 'bearer' })
      .send(body);
  const input = (suffix: string) => ({
    slug: prefix + suffix,
    style: style + suffix,
    title: 'Bộ sưu tập ' + suffix,
    description: '',
  });
  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    const [database] = await db.$queryRaw<
      { name: string }[]
    >`SELECT current_database() AS name`;
    expect(database.name.endsWith('_test')).toBe(true);
    const account = await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        name: 'Collections QA',
        email: prefix + '@example.test',
        password: randomUUID(),
      })
      .expect(201);
    userId = account.body.user.id;
    token = account.body.accessToken;
    categoryId = (
      await db.category.create({ data: { name: prefix, slug: prefix } })
    ).id;
    brandId = (await db.brand.create({ data: { name: prefix, slug: prefix } }))
      .id;
    // All fixtures stay in the isolated test database; production receives no test products.
    for (let i = 0; i < 17; i++) {
      const p = await db.product.create({
        data: {
          slug: prefix + '-' + i,
          name: prefix + '-' + i.toString().padStart(2, '0'),
          description: '',
          material: '',
          style: i === 16 ? style + '-other' : style,
          active: i !== 14,
          categoryId,
          brandId,
          ...(i !== 13
            ? {
                images: {
                  create: { url: 'assets/images/shirt.jpg', alt: prefix + i },
                },
              }
            : {}),
          variants: {
            create: {
              sku: prefix + i,
              active: i !== 15,
              size: 'M',
              color: 'Đen',
              colorHex: '#000000',
              price: 100000 + i * 1000,
              inventory: { create: { quantity: i === 0 ? 0 : 3 } },
            },
          },
        },
      });
      ids.push(p.id);
    }
  });
  afterAll(async () => {
    if (db) {
      await db.storeCollection.deleteMany({
        where: { slug: { startsWith: prefix } },
      });
      await db.inventory.deleteMany({
        where: { variant: { productId: { in: ids } } },
      });
      await db.productVariant.deleteMany({ where: { productId: { in: ids } } });
      await db.product.deleteMany({ where: { id: { in: ids } } });
      if (categoryId) await db.category.delete({ where: { id: categoryId } });
      if (brandId) await db.brand.delete({ where: { id: brandId } });
      if (userId) {
        await db.adminAuditEvent.deleteMany({ where: { actorId: userId } });
        await db.refreshToken.deleteMany({ where: { userId } });
        await db.user.delete({ where: { id: userId } });
      }
    }
    await app?.close();
  });
  it('requires content permission for reads and writes', async () => {
    await get('admin/collections').expect(401);
    for (const role of ['CUSTOMER', 'WAREHOUSE'] as const) {
      await db.user.update({ where: { id: userId }, data: { role } });
      await admin('get').expect(403);
      await admin('post', '', input('')).expect(403);
    }
    for (const role of ['MANAGER', 'ADMIN'] as const) {
      await db.user.update({ where: { id: userId }, data: { role } });
      await admin('get').expect(200);
    }
  });
  it('rejects missing, hidden, incomplete or unrelated cover products and malformed fields', async () => {
    for (const coverProductId of [randomUUID(), ...ids.slice(13)]) {
      const response = await admin('post', '', {
        ...input(''),
        coverProductId,
      }).expect(400);
      expect(response.body.error.code).toBe('INVALID_COLLECTION_COVER');
    }
    for (const fields of [
      { title: '  ' },
      { style: null },
      { active: null },
      { slug: '../bad' },
      { position: -1 },
      { position: 1.5 },
      { arbitrary: true },
    ]) {
      await admin('post', '', { ...input(''), ...fields }).expect(400);
    }
    expect(await db.storeCollection.count({ where: { slug: prefix } })).toBe(0);
    expect(await db.adminAuditEvent.count({ where: { actorId: userId } })).toBe(
      0,
    );
  });
  it('persists metadata and cover with an audit entry without modifying products or stock', async () => {
    const before = await db.product.findMany({
      where: { categoryId },
      include: { images: true, variants: { include: { inventory: true } } },
      orderBy: { id: 'asc' },
    });
    const response = await admin('post', '', {
      ...input(''),
      coverProductId: ids[0],
    }).expect(201);
    collectionId = response.body.id;
    expect(response.body.version).toBe(1);
    const detail = await get('collections/' + prefix).expect(200);
    expect(detail.body.collection).toMatchObject({
      id: collectionId,
      productCount: 13,
      cover: { productId: ids[0], url: 'assets/images/shirt.jpg' },
    });
    expect(detail.body.collection.version).toBeUndefined();
    expect(
      await db.product.findMany({
        where: { categoryId },
        include: { images: true, variants: { include: { inventory: true } } },
        orderBy: { id: 'asc' },
      }),
    ).toEqual(before);
    const event = await db.adminAuditEvent.findFirstOrThrow({
      where: { actorId: userId, action: 'COLLECTION_CREATED' },
    });
    expect(event.targetId).toBe(collectionId);
  });
  it('paginates the whole collection without repeated products and keeps the membership filter', async () => {
    const first = await get(
      'collections/' + prefix + '?limit=12&sort=name&style=' + style + '-other',
    ).expect(200);
    const second = await get(
      'collections/' + prefix + '?limit=12&page=2&sort=name',
    ).expect(200);
    expect(first.body.total).toBe(13);
    expect(first.body.items.map((p: { id: string }) => p.id)).toEqual(
      ids.slice(0, 12),
    );
    expect(second.body.items.map((p: { id: string }) => p.id)).toEqual([
      ids[12],
    ]);
    const stocked = await get(
      'collections/' + prefix + '?limit=100&inStock=true&sort=price-desc',
    ).expect(200);
    expect(stocked.body.total).toBe(12);
    expect(stocked.body.items.map((p: { id: string }) => p.id)).toEqual(
      ids.slice(1, 13).reverse(),
    );
    const empty = await get('collections/' + prefix + '?page=999').expect(200);
    expect(empty.body.total).toBe(13);
    expect(empty.body.items).toEqual([]);
    await get('collections/' + prefix + '?page=0').expect(400);
    await get('collections/' + prefix + '?sort=invalid').expect(400);
  });
  it('hides empty and disabled collections publicly, but exposes them to staff', async () => {
    await admin('post', '', input('-empty')).expect(201);
    await admin('post', '', { ...input('-other'), active: false }).expect(201);
    const listed = await get('collections?limit=100').expect(200);
    const ours = listed.body.items.filter((c: { slug: string }) =>
      c.slug.startsWith(prefix),
    );
    expect(ours.map((c: { slug: string }) => c.slug)).toEqual([prefix]);
    const staff = await admin('get', '?limit=100').expect(200);
    expect(
      staff.body.items.filter((c: { slug: string }) =>
        c.slug.startsWith(prefix),
      ),
    ).toHaveLength(3);
    expect(
      (await get('collections/' + prefix + '-empty').expect(200)).body.total,
    ).toBe(0);
    await get('collections/' + prefix + '-other').expect(404);
    await get('collections/' + prefix + '-unknown').expect(404);
  });
  it('rejects concurrent duplicates and rolls back conflicting edits', async () => {
    const concurrent = await Promise.all([
      admin('post', '', input('-new')),
      admin('post', '', input('-new')),
    ]);
    expect(concurrent.map((r) => r.status).sort()).toEqual([201, 409]);
    expect(concurrent.find((r) => r.status === 409)?.body.error.code).toBe(
      'DUPLICATE_COLLECTION',
    );
    await admin('post', '', { ...input('-duplicate'), style }).expect(409);
    const before = await db.storeCollection.findUniqueOrThrow({
      where: { id: collectionId },
    });
    await admin('patch', '/' + collectionId, {
      expectedVersion: 1,
      style: style + '-empty',
      coverProductId: null,
    }).expect(409);
    expect(
      await db.storeCollection.findUniqueOrThrow({
        where: { id: collectionId },
      }),
    ).toEqual(before);
  });
  it('allows only one concurrent edit and records only the successful update', async () => {
    for (const fields of [
      { title: null },
      { expectedVersion: null },
      { slug: 'renamed' },
    ]) {
      await admin('patch', '/' + collectionId, {
        expectedVersion: 1,
        ...fields,
      }).expect(400);
    }
    const replies = await Promise.all(
      ['First', 'Second'].map((title) =>
        admin('patch', '/' + collectionId, { expectedVersion: 1, title }),
      ),
    );
    expect(replies.map((r) => r.status).sort()).toEqual([200, 409]);
    expect(replies.find((r) => r.status === 409)?.body.error.code).toBe(
      'COLLECTION_CHANGED',
    );
    expect(
      await db.adminAuditEvent.count({
        where: { actorId: userId, action: 'COLLECTION_UPDATED' },
      }),
    ).toBe(1);
    expect(
      (
        await db.storeCollection.findUniqueOrThrow({
          where: { id: collectionId },
        })
      ).version,
    ).toBe(2);
    await admin('patch', '/' + randomUUID(), {
      expectedVersion: 1,
      title: 'Missing',
    }).expect(404);
  });
  it('replaces an archived cover with another published member and permits metadata edits', async () => {
    await db.product.update({ where: { id: ids[0] }, data: { active: false } });
    const detail = (await get('collections/' + prefix).expect(200)).body;
    expect(detail.collection.productCount).toBe(12);
    expect(ids.slice(1, 13)).toContain(detail.collection.cover.productId);
    await admin('patch', '/' + collectionId, {
      expectedVersion: 2,
      title: 'Updated after archive',
    }).expect(200);
    await admin('patch', '/' + collectionId, {
      expectedVersion: 3,
      coverProductId: ids[0],
    }).expect(400);
    await admin('patch', '/' + collectionId, {
      expectedVersion: 3,
      coverProductId: null,
      active: false,
    }).expect(200);
    await get('collections/' + prefix).expect(404);
    expect(
      (await get('collections?limit=100').expect(200)).body.items.some(
        (c: { id: string }) => c.id === collectionId,
      ),
    ).toBe(false);
  });
});
