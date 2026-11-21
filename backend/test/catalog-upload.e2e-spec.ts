import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { StorageService } from '../src/integrations/storage/storage.service';
import { validateEnv } from '../src/config/env.validation';
import { CatalogMediaService } from '../src/modules/catalog-media/catalog-media.service';
import { normalizeImage } from '../src/integrations/storage/image-policy';

const storageDescribe = process.env.TEST_S3_ENDPOINT ? describe : describe.skip;
storageDescribe('Catalog image upload with PostgreSQL and private S3', () => {
  let app: INestApplication, db: PrismaService, storage: StorageService;
  let admin: string,
    customer: string,
    productId: string,
    categoryId: string,
    brandId: string;
  let jpeg: Buffer;
  let catalog: CatalogMediaService, first: { id: string; url: string };
  const users: string[] = [];
  const suffix = randomUUID();
  beforeAll(async () => {
    if (
      !process.env.TEST_DATABASE_URL ||
      !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test') ||
      !process.env.TEST_S3_BUCKET?.endsWith('-test')
    )
      throw new Error('Dedicated test DB and bucket required');
    const config = validateEnv({
      ...process.env,
      DATABASE_URL: process.env.TEST_DATABASE_URL,
      S3_ENDPOINT: process.env.TEST_S3_ENDPOINT,
      S3_PUBLIC_ENDPOINT: process.env.TEST_S3_ENDPOINT,
      S3_BUCKET: process.env.TEST_S3_BUCKET,
      CORS_ORIGINS: 'http://localhost:4183',
    });
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ConfigService)
      .useValue(new ConfigService(config))
      .compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    storage = app.get(StorageService);
    catalog = app.get(CatalogMediaService);
    for (const role of ['ADMIN', 'CUSTOMER'] as const) {
      const result = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({
          email: `catalog-${role}-${suffix}@example.test`,
          name: role,
          password: 'Catalog-fixture-password-2026',
        })
        .expect(201);
      users.push(result.body.user.id);
      if (role === 'ADMIN') {
        await db.user.update({
          where: { id: result.body.user.id },
          data: { role },
        });
        admin = result.body.accessToken;
      } else customer = result.body.accessToken;
    }
    categoryId = (
      await db.category.create({
        data: { slug: suffix, name: 'Catalog fixture' },
      })
    ).id;
    brandId = (
      await db.brand.create({ data: { slug: suffix, name: 'Catalog fixture' } })
    ).id;
    productId = (
      await db.product.create({
        data: {
          slug: suffix,
          name: 'Catalog fixture',
          description: '',
          material: '',
          style: '',
          categoryId,
          brandId,
        },
      })
    ).id;
    jpeg = await sharp({
      create: { width: 64, height: 80, channels: 3, background: '#abc' },
    })
      .withExif({ IFD0: { Artist: 'Metadata must be stripped' } })
      .jpeg()
      .toBuffer();
  });
  afterAll(async () => {
    try {
      if (db) {
        const privateImages = await db.imageAsset.findMany({
          where: { userId: { in: users } },
        });
        await storage.deleteObjects(
          privateImages.map((image) => image.objectKey),
        );
        await db.imageAsset.deleteMany({ where: { userId: { in: users } } });
        if (productId) {
          const assets = await db.catalogAsset.findMany({
            where: { productId },
          });
          await storage.deleteObjects(assets.map((asset) => asset.objectKey));
          await db.catalogAsset.deleteMany({ where: { productId } });
        }
        await db.adminAuditEvent.deleteMany({
          where: { actorId: { in: users } },
        });
        if (productId) await db.product.delete({ where: { id: productId } });
        if (categoryId) await db.category.delete({ where: { id: categoryId } });
        if (brandId) await db.brand.delete({ where: { id: brandId } });
        await db.user.deleteMany({ where: { id: { in: users } } });
      }
    } finally {
      if (app) await app.close();
    }
  });
  const upload = (
    token = admin,
    key: string = randomUUID(),
    bytes = jpeg,
    type = 'image/jpeg',
  ) =>
    request(app.getHttpServer())
      .post(`/api/v1/admin/products/${productId}/images`)
      .auth(token, { type: 'bearer' })
      .set('Idempotency-Key', key)
      .field('alt', 'Uploaded catalog image')
      .attach('file', bytes, {
        filename: '../../untrusted.jpg',
        contentType: type,
      });
  it('requires administrator authorization for the multipart mutation', async () => {
    await request(app.getHttpServer())
      .post(`/api/v1/admin/products/${productId}/images`)
      .expect(401);
    await upload(customer).expect(403);
    const before = await db.product.findUniqueOrThrow({
      where: { id: productId },
    });
    first = (await upload(admin).expect(201)).body;
    // An editor opened before the upload must not erase the newly saved image.
    await request(app.getHttpServer())
      .patch(`/api/v1/admin/products/${productId}`)
      .auth(admin, { type: 'bearer' })
      .send({ images: [], expectedUpdatedAt: before.updatedAt.toISOString() })
      .expect(409);
    expect(await db.productImage.count({ where: { productId } })).toBe(1);
  });
  const gallery = (images: { url: string; alt: string }[]) =>
    request(app.getHttpServer())
      .patch(`/api/v1/admin/products/${productId}`)
      .auth(admin, { type: 'bearer' })
      .send({ images });
  it('serves only verified sanitized catalog bytes cross-origin while the bucket remains private', async () => {
    const result = await request(app.getHttpServer())
      .get('/api/v1/' + first.url)
      .set('Origin', 'http://localhost:4183')
      .expect(200);
    expect(result.headers['content-type']).toContain('image/jpeg');
    expect(result.headers['cross-origin-resource-policy']).toBe('cross-origin');
    expect(result.headers['access-control-allow-origin']).toBe(
      'http://localhost:4183',
    );
    expect(result.headers['x-content-type-options']).toBe('nosniff');
    const meta = await sharp(result.body as Buffer).metadata();
    expect(meta.width).toBe(64);
    expect(meta.height).toBe(80);
    expect(meta.exif).toBeUndefined();
    const asset = await db.catalogAsset.findUniqueOrThrow({
      where: { id: first.id },
    });
    const signed = new URL(await storage.signedRead(asset.objectKey));
    signed.search = '';
    expect(
      (await fetch(signed, { signal: AbortSignal.timeout(8000) })).status,
    ).toBe(403);
    expect(first).not.toHaveProperty('objectKey');
    await request(app.getHttpServer())
      .get('/api/v1/catalog/images/' + randomUUID())
      .expect(404);
    const privateImage = await request(app.getHttpServer())
      .post('/api/v1/uploads/images')
      .auth(customer, { type: 'bearer' })
      .field('consent', 'true')
      .attach('file', jpeg, {
        filename: 'private.jpg',
        contentType: 'image/jpeg',
      })
      .expect(201);
    await request(app.getHttpServer())
      .get('/api/v1/catalog/images/' + privateImage.body.id)
      .expect(404);
  });
  it('rejects invalid metadata, keys, forged MIME and oversized files without reserving objects', async () => {
    const before = await db.catalogAsset.count({ where: { productId } });
    await upload(admin, 'not-a-key').expect(400);
    await upload(admin, randomUUID(), jpeg, 'image/png').expect(400);
    await upload(admin, randomUUID(), Buffer.from('<svg/>')).expect(400);
    await upload(admin, randomUUID(), Buffer.alloc(8 * 1024 * 1024 + 1)).expect(
      413,
    );
    await request(app.getHttpServer())
      .post(`/api/v1/admin/products/${productId}/images`)
      .auth(admin, { type: 'bearer' })
      .set('Idempotency-Key', randomUUID())
      .field('alt', 'x'.repeat(201))
      .attach('file', jpeg, { filename: 'test.jpg', contentType: 'image/jpeg' })
      .expect(400);
    expect(await db.catalogAsset.count({ where: { productId } })).toBe(before);
  });
  it('writes one object/gallery/audit for concurrent retries and never reattaches a removed image on replay', async () => {
    const key = randomUUID();
    const put = jest.spyOn(storage, 'putImage');
    let receipt: { id: string; url: string };
    try {
      const results = await Promise.all([
        upload(admin, key),
        upload(admin, key),
      ]);
      expect(results.some((r) => r.status === 201)).toBe(true);
      expect(results.every((r) => [201, 409].includes(r.status))).toBe(true);
      receipt = results.find((r) => r.status === 201)!.body;
      expect(put).toHaveBeenCalledTimes(1);
      const replay = await upload(admin, key).expect(201);
      expect(replay.body).toEqual(receipt);
      expect(put).toHaveBeenCalledTimes(1);
      expect(
        await db.catalogAsset.count({
          where: { actorId: users[0], requestKey: key },
        }),
      ).toBe(1);
      expect(
        await db.productImage.count({ where: { productId, url: receipt.url } }),
      ).toBe(1);
      await gallery([]).expect(200);
      expect((await upload(admin, key).expect(201)).body).toEqual(receipt);
      expect(await db.productImage.count({ where: { productId } })).toBe(0);
      expect(put).toHaveBeenCalledTimes(1);
      await request(app.getHttpServer())
        .get('/api/v1/' + receipt.url)
        .expect(200);
      expect(
        await db.adminAuditEvent.count({
          where: { actorId: users[0], action: 'PRODUCT_IMAGE_UPLOADED' },
        }),
      ).toBe(2);
      await request(app.getHttpServer())
        .post(`/api/v1/admin/products/${productId}/images`)
        .auth(admin, { type: 'bearer' })
        .set('Idempotency-Key', key)
        .field('alt', 'Different')
        .attach('file', jpeg, {
          filename: 'test.jpg',
          contentType: 'image/jpeg',
        })
        .expect(409);
      const changedBytes = await sharp(jpeg).resize(80, 64).jpeg().toBuffer();
      await upload(admin, key, changedBytes).expect(409);
      expect(put).toHaveBeenCalledTimes(1);
    } finally {
      put.mockRestore();
    }
  });
  it('validates managed gallery references and enforces the 20-image bound under concurrent uploads', async () => {
    await gallery([{ url: 'catalog/images/' + randomUUID(), alt: '' }]).expect(
      400,
    );
    await gallery([{ url: first.url, alt: 'Valid owned asset' }]).expect(200);
    const other = await db.product.create({
      data: {
        slug: suffix + '-other',
        name: 'Other fixture',
        description: '',
        material: '',
        style: '',
        categoryId,
        brandId,
      },
    });
    try {
      await request(app.getHttpServer())
        .patch(`/api/v1/admin/products/${other.id}`)
        .auth(admin, { type: 'bearer' })
        .send({ images: [{ url: first.url, alt: 'Wrong product' }] })
        .expect(400);
      expect(
        await db.productImage.count({ where: { productId: other.id } }),
      ).toBe(0);
    } finally {
      await db.product.delete({ where: { id: other.id } });
    }
    await gallery(
      Array.from({ length: 19 }, () => ({
        url: 'assets/images/shirt.jpg',
        alt: '',
      })),
    ).expect(200);
    const results = await Promise.all([upload(), upload()]);
    expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
    expect(await db.productImage.count({ where: { productId } })).toBe(20);
    await gallery([]).expect(200);
  });
  it('keeps a failed PUT private, forbids a new writer for its key and reconciles a late remote object', async () => {
    const key = randomUUID(),
      actualPut = storage.putImage.bind(storage);
    const spy = jest
      .spyOn(storage, 'putImage')
      .mockImplementationOnce(async (...args) => {
        await actualPut(...args);
        throw new Error('Simulated lost S3 acknowledgement');
      });
    try {
      await upload(admin, key).expect(503);
    } finally {
      spy.mockRestore();
    }
    const asset = await db.catalogAsset.findUniqueOrThrow({
      where: { actorId_requestKey: { actorId: users[0], requestKey: key } },
    });
    expect(asset.verifiedAt).toBeNull();
    expect(asset.deletedAt).not.toBeNull();
    await request(app.getHttpServer())
      .get('/api/v1/catalog/images/' + asset.id)
      .expect(404);
    await upload(admin, key).expect(409);
    expect(await db.productImage.count({ where: { productId } })).toBe(0);
    await catalog.purge(asset.id);
    await expect(storage.readImage(asset.objectKey)).rejects.toThrow();
    // Simulate a provider completing an earlier accepted PUT after DELETE.
    await actualPut(asset.objectKey, await normalizeImage(jpeg, 'image/jpeg'));
    await db.catalogAsset.update({
      where: { id: asset.id },
      data: { purgeRetryAt: new Date(0) },
    });
    await catalog.purgeExpired();
    await expect(storage.readImage(asset.objectKey)).rejects.toThrow();
    await request(app.getHttpServer())
      .get('/api/v1/' + first.url)
      .expect(200);
  });
  it('serializes cleanup behind an in-flight upload and preserves the verified object', async () => {
    let release!: () => void, entered!: () => void;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const ready = new Promise<void>((resolve) => {
      entered = resolve;
    });
    const actualPut = storage.putImage.bind(storage),
      key = randomUUID();
    const spy = jest
      .spyOn(storage, 'putImage')
      .mockImplementationOnce(async (...args) => {
        entered();
        await gate;
        await actualPut(...args);
      });
    const pending = upload(admin, key).then((response) => response);
    let cleanup: Promise<void> | undefined;
    try {
      await ready;
      const asset = await db.catalogAsset.findUniqueOrThrow({
        where: { actorId_requestKey: { actorId: users[0], requestKey: key } },
      });
      await db.catalogAsset.update({
        where: { id: asset.id },
        data: { createdAt: new Date(Date.now() - 16 * 60000) },
      });
      cleanup = catalog.purge(asset.id);
    } finally {
      release();
      spy.mockRestore();
    }
    const response = await pending;
    expect(response.status).toBe(201);
    await cleanup;
    await request(app.getHttpServer())
      .get('/api/v1/' + response.body.url)
      .expect(200);
    const asset = await db.catalogAsset.findUniqueOrThrow({
      where: { id: response.body.id },
    });
    expect(asset.deletedAt).toBeNull();
    expect(asset.purgedAt).toBeNull();
  });
  it('rolls back gallery publication if the actual PostgreSQL audit insert fails', async () => {
    const name = 'catalog_audit_' + suffix.replace(/-/g, '');
    const before = await db.productImage.count({ where: { productId } });
    const key = randomUUID();
    await db.$executeRawUnsafe(
      `CREATE FUNCTION ${name}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Synthetic audit failure'; END $$`,
    );
    try {
      await db.$executeRawUnsafe(
        `CREATE TRIGGER ${name} BEFORE INSERT ON "AdminAuditEvent" FOR EACH ROW WHEN (NEW."actorId" = '${users[0]}'::uuid AND NEW.action = 'PRODUCT_IMAGE_UPLOADED') EXECUTE FUNCTION ${name}()`,
      );
      await upload(admin, key).expect(503);
    } finally {
      await db.$executeRawUnsafe(
        `DROP TRIGGER IF EXISTS ${name} ON "AdminAuditEvent"`,
      );
      await db.$executeRawUnsafe(`DROP FUNCTION ${name}()`);
    }
    expect(await db.productImage.count({ where: { productId } })).toBe(before);
    const asset = await db.catalogAsset.findUniqueOrThrow({
      where: { actorId_requestKey: { actorId: users[0], requestKey: key } },
    });
    expect(asset.verifiedAt).toBeNull();
    expect(asset.deletedAt).not.toBeNull();
    await request(app.getHttpServer())
      .get('/api/v1/catalog/images/' + asset.id)
      .expect(404);
    await catalog.purge(asset.id);
    await expect(storage.readImage(asset.objectKey)).rejects.toThrow();
  });
});
