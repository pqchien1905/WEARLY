import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Owned try-on history presentation', () => {
  let app: INestApplication, db: PrismaService;
  let productId: string,
    categoryId: string,
    brandId: string,
    variantId: string,
    imageId: string,
    jobId: string;
  const users: string[] = [],
    tokens: string[] = [];
  const fixture = 'history-' + randomUUID();
  const get = (path = '/ai/try-on/jobs', owner = 0) =>
    request(app.getHttpServer())
      .get('/api/v1' + path)
      .auth(tokens[owner], { type: 'bearer' });
  beforeAll(async () => {
    app = (
      await Test.createTestingModule({ imports: [AppModule] }).compile()
    ).createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    for (let i = 0; i < 2; i++) {
      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({
          name: 'History fixture',
          email: `${fixture}-${i}@example.test`,
          password: 'History-fixture-2026',
        })
        .expect(201);
      users.push(response.body.user.id);
      tokens.push(response.body.accessToken);
    }
    categoryId = (
      await db.category.create({ data: { name: fixture, slug: fixture } })
    ).id;
    brandId = (
      await db.brand.create({ data: { name: fixture, slug: fixture } })
    ).id;
    const product = await db.product.create({
      data: {
        name: 'Áo sơ mi thử lịch sử',
        slug: fixture,
        description: 'Fixture',
        material: 'Cotton',
        style: 'Thanh lịch',
        tryOnSupported: true,
        categoryId,
        brandId,
        images: {
          create: [
            {
              url: '/assets/other.jpg',
              alt: 'White',
              color: 'Trắng',
              position: 0,
            },
            {
              url: '/assets/black.jpg',
              alt: 'Black',
              color: 'Đen',
              position: 1,
            },
          ],
        },
        variants: {
          create: {
            sku: fixture,
            size: 'M',
            color: 'Đen',
            colorHex: '#000000',
            price: 300000,
          },
        },
      },
      include: { variants: true },
    });
    productId = product.id;
    variantId = product.variants[0].id;
    imageId = (
      await db.imageAsset.create({
        data: {
          userId: users[0],
          objectKey: fixture,
          mimeType: 'image/png',
          size: 100,
          consentAt: new Date(),
          verifiedAt: new Date(),
          expiresAt: new Date(Date.now() + 3600000),
        },
      })
    ).id;
    jobId = (
      await db.aIJob.create({
        data: {
          userId: users[0],
          variantId,
          imageId,
          consentAt: new Date(),
          status: 'FAILED',
          errorCode: 'AI_PROVIDER_UNAVAILABLE',
        },
      })
    ).id;
  });
  afterAll(async () => {
    if (db) {
      await db.aIJob.deleteMany({ where: { userId: { in: users } } });
      await db.imageAsset.deleteMany({ where: { userId: { in: users } } });
      if (productId) {
        await db.productVariant.deleteMany({ where: { productId } });
        await db.product.delete({ where: { id: productId } });
      }
      if (categoryId) await db.category.delete({ where: { id: categoryId } });
      if (brandId) await db.brand.delete({ where: { id: brandId } });
      await db.user.deleteMany({ where: { id: { in: users } } });
    }
    await app?.close();
  });
  it('returns the real garment and matching color image without private storage keys', async () => {
    const response = await get().expect(200);
    expect(response.headers['cache-control']).toBe('private, no-store');
    expect(response.body.items).toHaveLength(1);
    expect(response.body.items[0]).toMatchObject({
      id: jobId,
      size: 'M',
      color: 'Đen',
      status: 'failed',
      product: {
        name: 'Áo sơ mi thử lịch sử',
        slug: fixture,
        image: '/assets/black.jpg',
        tryOnSupported: true,
      },
    });
    expect(response.body.items[0]).not.toHaveProperty('objectKey');
    expect(
      (await get('/ai/try-on/jobs/' + jobId).expect(200)).body.product,
    ).toEqual(response.body.items[0].product);
  });
  it('keeps history isolated from guests and another customer', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/ai/try-on/jobs')
      .expect(401);
    expect((await get('/ai/try-on/jobs', 1).expect(200)).body.items).toEqual(
      [],
    );
    await get('/ai/try-on/jobs/' + jobId, 1).expect(404);
  });
  it('retains history while disabling links for unpublished garments', async () => {
    await db.productVariant.update({
      where: { id: variantId },
      data: { active: false },
    });
    expect((await get().expect(200)).body.items[0].product.tryOnSupported).toBe(
      false,
    );
    await db.product.update({
      where: { id: productId },
      data: { active: false },
    });
    const job = (await get().expect(200)).body.items[0];
    expect(job.product).toBeNull();
    expect(job.sku).toBe(fixture);
  });
});
