import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import {
  S3Client,
  GetObjectCommand,
  HeadObjectCommand,
} from '@aws-sdk/client-s3';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { StorageService } from '../src/integrations/storage/storage.service';
import { validateEnv } from '../src/config/env.validation';
import { ImageLifecycleService } from '../src/modules/uploads/image-lifecycle.service';
import { normalizeImage } from '../src/integrations/storage/image-policy';

const storageDescribe = process.env.TEST_S3_ENDPOINT ? describe : describe.skip;
storageDescribe('Private uploads with real PostgreSQL and S3', () => {
  let app: INestApplication,
    db: PrismaService,
    storage: StorageService,
    s3: S3Client;
  let token: string,
    otherToken: string,
    userId: string,
    jpeg: Buffer,
    lifecycle: ImageLifecycleService;
  let bucket: string;
  const ownedIds: string[] = [];
  beforeAll(async () => {
    if (
      !process.env.TEST_DATABASE_URL ||
      !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test') ||
      !process.env.TEST_S3_BUCKET?.endsWith('-test')
    )
      throw new Error('Dedicated test database and S3 bucket are required');
    const config = validateEnv({
      ...process.env,
      DATABASE_URL: process.env.TEST_DATABASE_URL,
      S3_ENDPOINT: process.env.TEST_S3_ENDPOINT,
      S3_PUBLIC_ENDPOINT: process.env.TEST_S3_ENDPOINT,
      S3_BUCKET: process.env.TEST_S3_BUCKET,
    });
    bucket = config.S3_BUCKET;
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ConfigService)
      .useValue(new ConfigService(config))
      .compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    storage = app.get(StorageService);
    lifecycle = app.get(ImageLifecycleService);
    s3 = new S3Client({
      endpoint: config.S3_ENDPOINT,
      region: config.S3_REGION,
      forcePathStyle: true,
      credentials: {
        accessKeyId: config.S3_ACCESS_KEY_ID,
        secretAccessKey: config.S3_SECRET_ACCESS_KEY,
      },
    });
    const customer = async () =>
      (
        await request(app.getHttpServer())
          .post('/api/v1/auth/register')
          .send({
            name: 'Upload test',
            email: randomUUID() + '@upload.example.test',
            password: 'Wearly-test-password-2026',
          })
          .expect(201)
      ).body;
    const owner = await customer();
    token = owner.accessToken;
    userId = owner.user.id;
    otherToken = (await customer()).accessToken;
    jpeg = await sharp({
      create: { width: 64, height: 80, channels: 3, background: '#abc' },
    })
      .withExif({ IFD0: { Artist: 'Private identity' } })
      .jpeg()
      .toBuffer();
  });
  afterAll(async () => {
    jest.restoreAllMocks();
    try {
      if (db && storage && userId) {
        const rows = await db.imageAsset.findMany({ where: { userId } });
        await storage.deleteObjects(rows.map((row) => row.objectKey));
        await db.imageAsset.updateMany({
          where: { userId },
          data: { deletedAt: new Date(), purgedAt: new Date() },
        });
      }
    } finally {
      s3?.destroy();
      if (app) await app.close();
    }
  });
  const upload = (
    auth = token,
    bytes = jpeg,
    type = 'image/jpeg',
    consent = 'true',
  ) =>
    request(app.getHttpServer())
      .post('/api/v1/uploads/images')
      .auth(auth, { type: 'bearer' })
      .field('consent', consent)
      .attach('file', bytes, {
        filename: 'untrusted-name.jpg',
        contentType: type,
      });
  it('requires authentication and explicit consent and rejects forged or oversized content', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/uploads/images')
      .expect(401);
    await upload(token, jpeg, 'image/jpeg', 'false').expect(400);
    await upload(token, jpeg, 'image/png').expect(400);
    await upload(token, Buffer.from('<svg/>'), 'image/jpeg').expect(400);
    await upload(token, Buffer.alloc(8 * 1024 * 1024 + 1), 'image/jpeg').expect(
      413,
    );
    expect(await db.imageAsset.count({ where: { userId } })).toBe(0);
  });
  it('stores sanitized bytes privately, returns an expiring owned URL and hides object keys', async () => {
    const created = await upload().expect(201);
    const id = created.body.id;
    ownedIds.push(id);
    expect(created.body).toMatchObject({
      mimeType: 'image/jpeg',
      width: 64,
      height: 80,
    });
    expect(created.body.objectKey).toBeUndefined();
    const row = await db.imageAsset.findUniqueOrThrow({ where: { id } });
    expect(row.verifiedAt).not.toBeNull();
    const object = await s3.send(
      new GetObjectCommand({ Bucket: bucket, Key: row.objectKey }),
    );
    const metadata = await sharp(
      await object.Body!.transformToByteArray(),
    ).metadata();
    expect(metadata.exif).toBeUndefined();
    const privateUrl =
      process.env.TEST_S3_ENDPOINT + '/' + bucket + '/' + row.objectKey;
    expect((await fetch(privateUrl)).status).toBe(403);
    const read = await request(app.getHttpServer())
      .get('/api/v1/uploads/images/' + id)
      .auth(token, { type: 'bearer' })
      .expect(200);
    expect(new URL(read.body.url).searchParams.get('X-Amz-Expires')).toBe('60');
    expect((await fetch(read.body.url)).status).toBe(200);
    await request(app.getHttpServer())
      .get('/api/v1/uploads/images/' + id)
      .auth(otherToken, { type: 'bearer' })
      .expect(404);
    await request(app.getHttpServer())
      .delete('/api/v1/uploads/images/' + id)
      .auth(otherToken, { type: 'bearer' })
      .expect(404);
    const list = await request(app.getHttpServer())
      .get('/api/v1/uploads/images')
      .auth(otherToken, { type: 'bearer' })
      .expect(200);
    expect(list.body.items).toEqual([]);
  });
  it('revokes reads immediately and makes deletion idempotent', async () => {
    const id = ownedIds[0];
    await request(app.getHttpServer())
      .delete('/api/v1/uploads/images/' + id)
      .auth(token, { type: 'bearer' })
      .expect(202);
    await request(app.getHttpServer())
      .get('/api/v1/uploads/images/' + id)
      .auth(token, { type: 'bearer' })
      .expect(404);
    await request(app.getHttpServer())
      .delete('/api/v1/uploads/images/' + id)
      .auth(token, { type: 'bearer' })
      .expect(202);
    const row = await db.imageAsset.findUniqueOrThrow({ where: { id } });
    expect(row.deletedAt).not.toBeNull();
  });
  it('leaves a cleanup tombstone after storage failure without leaking its error', async () => {
    const put = jest
      .spyOn(storage, 'putImage')
      .mockRejectedValueOnce(new Error('private-storage-secret'));
    const res = await upload().expect(503);
    expect(res.body.error.code).toBe('STORAGE_UNAVAILABLE');
    expect(JSON.stringify(res.body)).not.toContain('private-storage-secret');
    put.mockRestore();
    const rows = await db.imageAsset.findMany({
      where: { userId, verifiedAt: null },
    });
    expect(rows).toHaveLength(1);
    expect(rows[0].deletedAt).not.toBeNull();
    await expect(
      s3.send(
        new HeadObjectCommand({ Bucket: bucket, Key: rows[0].objectKey }),
      ),
    ).rejects.toMatchObject({ $metadata: { httpStatusCode: 404 } });
  });
  it('retries failed purges and removes expired/stale uploads without touching a live image', async () => {
    const expired = (await upload().expect(201)).body.id as string;
    const live = (await upload().expect(201)).body.id as string;
    await db.imageAsset.update({
      where: { id: expired },
      data: { expiresAt: new Date(0) },
    });
    await request(app.getHttpServer())
      .get('/api/v1/uploads/images/' + expired)
      .auth(token, { type: 'bearer' })
      .expect(404);
    const remove = jest
      .spyOn(storage, 'deleteObjects')
      .mockRejectedValueOnce(new Error('private-storage-secret'));
    await expect(lifecycle.purge(expired)).rejects.toThrow();
    let row = await db.imageAsset.findUniqueOrThrow({ where: { id: expired } });
    expect(row.deletedAt).not.toBeNull();
    expect(row.purgedAt).toBeNull();
    remove.mockRestore();
    expect(await lifecycle.purge(expired)).toBe(true);
    row = await db.imageAsset.findUniqueOrThrow({ where: { id: expired } });
    expect(row.purgedAt).not.toBeNull();
    await expect(
      s3.send(new HeadObjectCommand({ Bucket: bucket, Key: row.objectKey })),
    ).rejects.toMatchObject({ $metadata: { httpStatusCode: 404 } });
    expect(await lifecycle.purge(live)).toBe(false);
    const liveRow = await db.imageAsset.findUniqueOrThrow({
      where: { id: live },
    });
    expect(
      (
        await s3.send(
          new HeadObjectCommand({ Bucket: bucket, Key: liveRow.objectKey }),
        )
      ).ContentLength,
    ).toBeGreaterThan(0);
    const stale = await db.imageAsset.create({
      data: {
        userId,
        objectKey: 'uploads/' + userId + '/' + randomUUID(),
        mimeType: 'image/jpeg',
        size: jpeg.length,
        createdAt: new Date(Date.now() - 3600000),
        expiresAt: new Date(Date.now() + 3600000),
      },
    });
    await storage.putImage(stale.objectKey, {
      bytes: jpeg,
      contentType: 'image/jpeg',
      width: 64,
      height: 80,
    });
    expect(await lifecycle.purge(stale.id)).toBe(true);
    await expect(
      s3.send(new HeadObjectCommand({ Bucket: bucket, Key: stale.objectKey })),
    ).rejects.toMatchObject({ $metadata: { httpStatusCode: 404 } });
  });
  it('reconciles a remote PUT completed after an earlier successful purge', async () => {
    const before = (
      await db.imageAsset.findMany({ where: { userId }, select: { id: true } })
    ).map((row) => row.id);
    const put = jest
      .spyOn(storage, 'putImage')
      .mockRejectedValueOnce(new Error('Lost remote acknowledgement'));
    try {
      await upload().expect(503);
    } finally {
      put.mockRestore();
    }
    const reservation = await db.imageAsset.findFirstOrThrow({
      where: { userId, id: { notIn: before } },
    });
    expect(reservation.verifiedAt).toBeNull();
    expect(await lifecycle.purge(reservation.id)).toBe(true);
    // Provider finishes a previously accepted PUT after responding to DELETE.
    await storage.putImage(
      reservation.objectKey,
      await normalizeImage(jpeg, 'image/jpeg'),
    );
    expect(
      (
        await s3.send(
          new HeadObjectCommand({ Bucket: bucket, Key: reservation.objectKey }),
        )
      ).ContentLength,
    ).toBeGreaterThan(0);
    await request(app.getHttpServer())
      .get('/api/v1/uploads/images/' + reservation.id)
      .auth(token, { type: 'bearer' })
      .expect(404);
    const originalFind = db.imageAsset.findMany.bind(db.imageAsset);
    const find = jest
      .spyOn(db.imageAsset, 'findMany')
      .mockImplementation((args) =>
        originalFind({
          ...args,
          where: { ...args?.where, id: reservation.id },
        }),
      );
    try {
      const remove = jest.spyOn(storage, 'deleteObjects');
      try {
        await lifecycle.purgeExpired();
        expect(remove).not.toHaveBeenCalled();
      } finally {
        remove.mockRestore();
      }
      await db.imageAsset.update({
        where: { id: reservation.id },
        data: { purgeRetryAt: new Date(0) },
      });
      await lifecycle.purgeExpired();
    } finally {
      find.mockRestore();
    }
    await expect(
      s3.send(
        new HeadObjectCommand({ Bucket: bucket, Key: reservation.objectKey }),
      ),
    ).rejects.toMatchObject({ $metadata: { httpStatusCode: 404 } });
    const reconciled = await db.imageAsset.findUniqueOrThrow({
      where: { id: reservation.id },
    });
    expect(reconciled.purgedAt).not.toBeNull();
    expect(reconciled.purgeRetryAt!.getTime()).toBeGreaterThan(
      Date.now() + 23 * 3600000,
    );
  });
  it('serializes concurrent reservations and enforces both retained and daily quotas', async () => {
    // Fixtures only: never delete a shared bucket or reset database state.
    await db.imageAsset.updateMany({
      where: { userId },
      data: { deletedAt: new Date(), purgedAt: new Date() },
    });
    const make = (purged: boolean) => ({
      userId,
      objectKey: 'uploads/' + userId + '/' + randomUUID(),
      mimeType: 'image/jpeg',
      size: 1,
      verifiedAt: new Date(),
      expiresAt: new Date(Date.now() + 3600000),
      ...(purged ? { deletedAt: new Date(), purgedAt: new Date() } : {}),
    });
    await db.imageAsset.createMany({
      data: Array.from({ length: 19 }, () => make(false)),
    });
    const pair = await Promise.all([upload(), upload()]);
    expect(pair.map((r) => r.status).sort()).toEqual([201, 429]);
    expect(
      await db.imageAsset.count({ where: { userId, purgedAt: null } }),
    ).toBe(20);
    await db.imageAsset.updateMany({
      where: { userId },
      data: { deletedAt: new Date(), purgedAt: new Date() },
    });
    const daily = await db.imageAsset.count({ where: { userId } });
    await db.imageAsset.createMany({
      data: Array.from({ length: 100 - daily }, () => make(true)),
    });
    const limited = await upload().expect(429);
    expect(limited.body.error.code).toBe('IMAGE_QUOTA_EXCEEDED');
  });
  it('continues cleanup past a full batch of persistent object failures', async () => {
    await db.imageAsset.updateMany({
      where: { userId },
      data: { deletedAt: new Date(), purgedAt: new Date() },
    });
    const rows = await db.imageAsset.createManyAndReturn({
      data: Array.from({ length: 51 }, (_, i) => ({
        userId,
        objectKey: 'uploads/' + userId + '/' + randomUUID(),
        mimeType: 'image/jpeg',
        size: 1,
        expiresAt: new Date(i),
        deletedAt: new Date(),
      })),
    });
    rows.sort((a, b) => a.expiresAt.getTime() - b.expiresAt.getTime());
    const failingKeys = new Set(rows.slice(0, 50).map((row) => row.objectKey));
    const originalFind = db.imageAsset.findMany.bind(db.imageAsset);
    const originalDelete = storage.deleteObjects.bind(storage);
    // Preserve the real selection predicates; scope this sweep to this run's owner.
    const find = jest
      .spyOn(db.imageAsset, 'findMany')
      .mockImplementation((args) =>
        originalFind({ ...args, where: { ...args?.where, userId } }),
      );
    const remove = jest
      .spyOn(storage, 'deleteObjects')
      .mockImplementation(async (keys) => {
        if (keys.some((key) => failingKeys.has(key)))
          throw new Error('object-specific access denied');
        await originalDelete(keys);
      });
    try {
      await lifecycle.purgeExpired();
      await lifecycle.purgeExpired();
      expect(
        (await db.imageAsset.findUniqueOrThrow({ where: { id: rows[50].id } }))
          .purgedAt,
      ).not.toBeNull();
      expect(
        await db.imageAsset.count({
          where: {
            id: { in: rows.slice(0, 50).map((row) => row.id) },
            purgedAt: null,
          },
        }),
      ).toBe(50);
    } finally {
      find.mockRestore();
      remove.mockRestore();
    }
  });
});
