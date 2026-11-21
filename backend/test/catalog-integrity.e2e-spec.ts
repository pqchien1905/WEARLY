import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Catalog identity and real database search', () => {
  let app: INestApplication, db: PrismaService;
  let token: string, userId: string, categoryId: string, brandId: string;
  const prefix = 'integrity-' + randomUUID();
  const call = (method: 'post' | 'patch', route: string, body: object) =>
    request(app.getHttpServer())
      [method]('/api/v1/' + route)
      .auth(token, { type: 'bearer' })
      .send(body);
  const input = (suffix: string, name: string, active = true) => ({
    slug: prefix + '-' + suffix,
    name,
    active,
    categoryId,
    brandId,
    description: '',
    material: '',
    style: '',
    images: [{ url: 'assets/images/shirt.jpg', alt: name }],
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
        name: 'Catalog QA',
        email: prefix + '@example.test',
        password: randomUUID(),
      })
      .expect(201);
    userId = account.body.user.id;
    token = account.body.accessToken;
    await db.user.update({ where: { id: userId }, data: { role: 'ADMIN' } });
    categoryId = (
      await db.category.create({ data: { name: prefix, slug: prefix } })
    ).id;
    brandId = (await db.brand.create({ data: { name: prefix, slug: prefix } }))
      .id;
  });
  afterAll(async () => {
    if (categoryId) {
      const products = await db.product.findMany({
        where: { categoryId },
        select: { id: true },
      });
      const ids = products.map((p) => p.id);
      await db.inventory.deleteMany({
        where: { variant: { productId: { in: ids } } },
      });
      await db.productVariant.deleteMany({ where: { productId: { in: ids } } });
      await db.product.deleteMany({ where: { id: { in: ids } } });
      await db.category.delete({ where: { id: categoryId } });
    }
    if (brandId) await db.brand.delete({ where: { id: brandId } });
    if (userId) {
      await db.adminAuditEvent.deleteMany({ where: { actorId: userId } });
      await db.refreshToken.deleteMany({ where: { userId } });
      await db.user.delete({ where: { id: userId } });
    }
    await app?.close();
  });
  it('rejects blank names and concurrent duplicate names despite case, Unicode and spaces', async () => {
    await call('post', 'admin/products', input('blank', ' \t ')).expect(400);
    const name = 'Áo Sơ Mi ' + prefix;
    const responses = await Promise.all([
      call('post', 'admin/products', input('first', name)),
      call(
        'post',
        'admin/products',
        input('second', ('  áo  sơ\tmi ' + prefix + '  ').normalize('NFD')),
      ),
    ]);
    expect(responses.map((r) => r.status).sort()).toEqual([201, 409]);
    expect(responses.find((r) => r.status === 409)?.body.error.code).toBe(
      'DUPLICATE_PRODUCT',
    );
    expect(await db.product.count({ where: { categoryId } })).toBe(1);
    expect(
      await db.adminAuditEvent.count({
        where: { actorId: userId, action: 'PRODUCT_CREATED' },
      }),
    ).toBe(1);
  });
  it('rolls back a conflicting rename and prevents reactivating an archived duplicate', async () => {
    const existing = await db.product.findFirstOrThrow({
      where: { categoryId },
    });
    const second = await call(
      'post',
      'admin/products',
      input('other', 'Another ' + prefix),
    ).expect(201);
    const id = second.body.id;
    const before = await db.product.findUniqueOrThrow({
      where: { id },
      include: { images: true },
    });
    await call('patch', 'admin/products/' + id, {
      name: existing.name,
      images: [],
    }).expect(409);
    expect(
      await db.product.findUniqueOrThrow({
        where: { id },
        include: { images: true },
      }),
    ).toEqual(before);
    await call('patch', 'admin/products/' + id, {
      name: existing.name,
      active: false,
    }).expect(200);
    const conflict = await call('patch', 'admin/products/' + id, {
      active: true,
    }).expect(409);
    expect(conflict.body.error.code).toBe('DUPLICATE_PRODUCT');
    expect((await db.product.findUniqueOrThrow({ where: { id } })).active).toBe(
      false,
    );
    await call('patch', 'admin/products/' + id, {
      name: 'New name ' + prefix,
      active: true,
    }).expect(200);
  });
  it('searches Vietnamese with or without accents and treats wildcard characters literally', async () => {
    const product = await call(
      'post',
      'admin/products',
      input('search', 'Áo sơ mi Đỏ 100% ' + prefix),
    ).expect(201);
    await db.productVariant.create({
      data: {
        productId: product.body.id,
        sku: prefix,
        size: 'M',
        color: 'Đỏ',
        colorHex: '#A00000',
        price: '150000',
        inventory: { create: { quantity: 2 } },
      },
    });
    const search = (q: string) =>
      request(app.getHttpServer())
        .get('/api/v1/products')
        .query({ category: prefix, q });
    for (const q of [
      'ao so mi do',
      'ÁO SƠ MI ĐỎ'.normalize('NFD'),
      '  áo   sơ mi đỏ  ',
      '100%',
    ]) {
      const result = await search(q).expect(200);
      expect(result.body.items.map((p: { id: string }) => p.id)).toEqual([
        product.body.id,
      ]);
    }
    for (const q of ['_', 'absent%', "' OR 1=1 --"])
      expect((await search(q).expect(200)).body.total).toBe(0);
  });
});
