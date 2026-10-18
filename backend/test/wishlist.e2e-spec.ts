import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Wishlist with PostgreSQL', () => {
  let app: INestApplication, db: PrismaService, categoryId: string, brandId: string;
  const suffix = randomUUID(), users: string[] = [], tokens: string[] = [], products: string[] = [];
  const credentials = (i: number) => ({ email: `wishlist-${i}-${suffix}@example.test`, password: 'Wishlist-test-password-2026' });
  const call = (method: 'get' | 'put' | 'delete', path = '', user = 0) => request(app.getHttpServer())[method]('/api/v1/wishlist' + path).auth(tokens[user], { type: 'bearer' });
  beforeAll(async () => {
    if (!process.env.TEST_DATABASE_URL || !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test')) throw new Error('Dedicated _test database required');
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    process.env.NODE_ENV = 'test';
    process.env.JWT_ACCESS_SECRET = 'test-access-'.repeat(5);
    process.env.JWT_REFRESH_SECRET = 'test-refresh-'.repeat(5);
    const module = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = module.createNestApplication({ logger: false }); configureApp(app); await app.init(); db = app.get(PrismaService);
    for (let i = 0; i < 2; i++) {
      const r = await request(app.getHttpServer()).post('/api/v1/auth/register').send({ ...credentials(i), name: 'Wishlist test' }).expect(201);
      users.push(r.body.user.id); tokens.push(r.body.accessToken);
    }
    categoryId = (await db.category.create({ data: { name: 'Wishlist test', slug: 'wishlist-' + suffix } })).id;
    brandId = (await db.brand.create({ data: { name: 'Wishlist test', slug: 'wishlist-' + suffix } })).id;
    for (let i = 0; i < 2; i++) {
      const p = await db.product.create({ data: { name: 'Saved shirt', slug: `wishlist-${i}-${suffix}`, description: '', material: 'Cotton', style: '', categoryId, brandId,
        variants: { create: { sku: `wishlist-${i}-${suffix}`, size: 'M', color: 'Black', colorHex: '#000000', price: '490000', inventory: { create: { quantity: 0 } } } } } });
      products.push(p.id);
    }
  });
  afterAll(async () => {
    if (db) {
      await db.user.deleteMany({ where: { id: { in: users } } });
      await db.inventory.deleteMany({ where: { variant: { productId: { in: products } } } });
      await db.productVariant.deleteMany({ where: { productId: { in: products } } });
      await db.product.deleteMany({ where: { id: { in: products } } });
      if (categoryId) await db.category.delete({ where: { id: categoryId } });
      if (brandId) await db.brand.delete({ where: { id: brandId } });
    }
    if (app) await app.close();
  });
  it('requires authentication, validates IDs and isolates owners across re-login', async () => {
    for (const method of ['get', 'put', 'delete'] as const) await request(app.getHttpServer())[method]('/api/v1/wishlist' + (method === 'get' ? '' : '/' + products[0])).expect(401);
    await call('put', '/invalid').expect(400);
    await call('put', '/' + randomUUID()).expect(404);
    const saved = await call('put', '/' + products[0]).expect(200);
    expect(saved.body.items).toHaveLength(1);
    expect(saved.body.items[0].product.variants[0].available).toBe(0);
    expect(saved.body.items[0].product.priceFrom.amount).toBe('490000');
    expect((await call('get', '', 1)).body.items).toEqual([]);
    await call('delete', '/' + products[0], 1).expect(200);
    expect((await call('get')).body.items).toHaveLength(1);
    await request(app.getHttpServer()).post('/api/v1/auth/logout').auth(tokens[0], { type: 'bearer' }).expect(201);
    tokens[0] = (await request(app.getHttpServer()).post('/api/v1/auth/login').send(credentials(0)).expect(201)).body.accessToken;
    expect((await call('get')).body.items[0].productId).toBe(products[0]);
  });
  it('handles duplicate adds/removes and unavailable products without exposing metadata', async () => {
    const added = await Promise.all([call('put', '/' + products[0]), call('put', '/' + products[0])]);
    expect(added.map(r => r.status)).toEqual([200, 200]);
    expect(await db.wishlistItem.count({ where: { userId: users[0] } })).toBe(1);
    await db.product.update({ where: { id: products[0] }, data: { active: false, name: 'Unpublished confidential name' } });
    const hidden = await call('get').expect(200);
    expect(hidden.body.items).toEqual([{ productId: products[0], product: null }]);
    expect(JSON.stringify(hidden.body)).not.toContain('Unpublished');
    await call('put', '/' + products[0], 1).expect(404);
    await db.product.update({ where: { id: products[0] }, data: { active: true } });
    await db.productVariant.updateMany({ where: { productId: products[0] }, data: { active: false } });
    expect((await call('get')).body.items[0].product).toBeNull();
    await call('put', '/' + products[0], 1).expect(404);
    await call('delete', '/' + products[0]).expect(200);
    await call('delete', '/' + products[0]).expect(200);
    await db.productVariant.updateMany({ where: { productId: products[0] }, data: { active: true } });
  });
  it('enforces quota atomically while allowing idempotent saves and removal', async () => {
    const filler = Array.from({ length: 199 }, () => randomUUID()); products.push(...filler);
    await db.product.createMany({ data: filler.map(id => ({ id, name: 'Quota fixture', slug: 'quota-' + id, description: '', material: '', style: '', active: false, categoryId, brandId })) });
    await db.wishlistItem.createMany({ data: filler.map(productId => ({ userId: users[0], productId })) });
    const results = await Promise.all([call('put', '/' + products[0]), call('put', '/' + products[1])]);
    expect(results.map(r => r.status).sort()).toEqual([200, 409]);
    expect(await db.wishlistItem.count({ where: { userId: users[0] } })).toBe(200);
    const savedId = products[results[0].status === 200 ? 0 : 1];
    await call('put', '/' + savedId).expect(200);
    await call('delete', '/' + filler[0]).expect(200);
    await call('put', '/' + products[0]).expect(200);
    expect((await call('get')).body.limit).toBe(200);
  });
});
