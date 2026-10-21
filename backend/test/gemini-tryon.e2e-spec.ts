import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ThrottlerGuard } from '@nestjs/throttler';
import { randomUUID } from 'node:crypto';
import { Job } from 'bullmq';
import sharp from 'sharp';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { validateEnv } from '../src/config/env.validation';
import { GEMINI_HTTP } from '../src/integrations/ai-providers/gemini-transport';
import { TryOnProvider } from '../src/integrations/ai-providers/try-on.provider';
import { GarmentReader } from '../src/integrations/ai-providers/garment-reader.service';
import { StorageService } from '../src/integrations/storage/storage.service';
import { AiUsageService } from '../src/modules/ai/ai-usage.service';
import { AiProcessor } from '../src/worker/ai.processor';

const storageDescribe = process.env.TEST_S3_ENDPOINT ? describe : describe.skip;
storageDescribe('Private Gemini jobs with PostgreSQL and MinIO', () => {
  let app: INestApplication,
    db: PrismaService,
    config: ConfigService,
    storage: StorageService,
    usage: AiUsageService;
  let productId: string,
    variantId: string,
    categoryId: string,
    brandId: string,
    sku: string,
    photo: Buffer;
  const users: string[] = [];
  const send = jest.fn(
    async (
      _url: string | URL | Request,
      _options?: RequestInit,
    ): Promise<Response> => imageResponse(),
  );
  const imageResponse = () =>
    Response.json({
      status: 'completed',
      steps: [
        {
          type: 'model_output',
          content: [
            {
              type: 'image',
              mime_type: 'image/png',
              data: photo.toString('base64'),
            },
          ],
        },
      ],
      usage: { total_input_tokens: 10, total_output_tokens: 20 },
    });
  async function customer() {
    const r = await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        email: 'tryon-' + randomUUID() + '@example.test',
        name: 'Try-on fixture',
        password: 'Tryon-fixture-2026',
      })
      .expect(201);
    users.push(r.body.user.id);
    return {
      id: r.body.user.id as string,
      token: r.body.accessToken as string,
    };
  }
  const upload = (token: string, key = randomUUID(), bytes = photo) =>
    request(app.getHttpServer())
      .post('/api/v1/uploads/images')
      .auth(token, { type: 'bearer' })
      .set('Idempotency-Key', key)
      .field('consent', 'true')
      .attach('file', bytes, {
        filename: 'photo.png',
        contentType: 'image/png',
      });
  const create = (
    token: string,
    imageId: string,
    key = randomUUID(),
    chosenSku = sku,
  ) =>
    request(app.getHttpServer())
      .post('/api/v1/ai/try-on/jobs')
      .auth(token, { type: 'bearer' })
      .set('Idempotency-Key', key)
      .send({ imageId, sku: chosenSku, consent: true });
  const get = (token: string, path: string) =>
    request(app.getHttpServer())
      .get('/api/v1/' + path)
      .auth(token, { type: 'bearer' });
  const job = (id: string) =>
    ({ data: { id }, attemptsMade: 0, opts: { attempts: 3 } }) as Job<{
      id: string;
    }>;
  function processor() {
    // Exercise the real processor deterministically; worker.e2e also covers Redis delivery.
    return Reflect.construct(AiProcessor, [
      db,
      config,
      app.get(TryOnProvider),
      storage,
      usage,
      app.get(GarmentReader),
    ]) as AiProcessor;
  }
  beforeAll(async () => {
    if (
      !process.env.TEST_DATABASE_URL ||
      !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test') ||
      !process.env.TEST_S3_BUCKET?.endsWith('-test')
    )
      throw Error('Dedicated test DB/storage required');
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    const env = validateEnv({
      ...process.env,
      NODE_ENV: 'test',
      DATABASE_URL: process.env.TEST_DATABASE_URL,
      S3_ENDPOINT: process.env.TEST_S3_ENDPOINT,
      S3_BUCKET: process.env.TEST_S3_BUCKET,
      GEMINI_API_KEY: 'fixture-key-not-a-real-key-2026',
      AI_TRYON_USER_DAILY_LIMIT: 20,
      VNPAY_ENABLED: 'false',
      LOCAL_MAIL_ENABLED: 'false',
      PASSWORD_RECOVERY_ENABLED: 'false',
    });
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ConfigService)
      .useValue(new ConfigService(env))
      .overrideProvider(GEMINI_HTTP)
      .useValue(send)
      .overrideGuard(ThrottlerGuard)
      .useValue({ canActivate: () => true })
      .compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    config = app.get(ConfigService);
    storage = app.get(StorageService);
    usage = app.get(AiUsageService);
    photo = await sharp({
      create: { width: 64, height: 80, channels: 3, background: '#abc' },
    })
      .png()
      .toBuffer();
    categoryId = (
      await db.category.create({
        data: { name: 'Try-on fixture', slug: randomUUID() },
      })
    ).id;
    brandId = (
      await db.brand.create({
        data: { name: 'Try-on fixture', slug: randomUUID() },
      })
    ).id;
    sku = 'TRYON-' + randomUUID();
    const product = await db.product.create({
      data: {
        name: 'Try-on fixture',
        slug: randomUUID(),
        description: 'Fixture',
        material: 'Cotton',
        style: 'Minimal',
        categoryId,
        brandId,
        tryOnSupported: true,
        images: { create: { url: 'assets/images/shirt.jpg', alt: 'Fixture' } },
        variants: {
          create: {
            sku,
            size: 'M',
            color: 'White',
            colorHex: '#ffffff',
            price: 400000,
            inventory: { create: { quantity: 3 } },
          },
        },
      },
      include: { variants: true },
    });
    productId = product.id;
    variantId = product.variants[0].id;
  });
  beforeEach(() => {
    send.mockClear();
    config.set('GEMINI_API_KEY', 'fixture-key-not-a-real-key-2026');
    config.set('AI_TRYON_USER_DAILY_LIMIT', 20);
    config.set('AI_GLOBAL_DAILY_ESTIMATE_VND', 100000);
  });
  afterAll(async () => {
    if (db) {
      const owner = { userId: { in: users } },
        jobs = await db.aIJob.findMany({ where: owner });
      const images = await db.imageAsset.findMany({ where: owner });
      await storage.deleteObjects([
        ...images.map((i) => i.objectKey),
        ...jobs.map((j) => 'results/' + j.userId + '/' + j.id),
      ]);
      await db.tryOnResult.deleteMany({
        where: { jobId: { in: jobs.map((j) => j.id) } },
      });
      await db.outboxEvent.deleteMany({
        where: { jobId: { in: jobs.map((j) => j.id) } },
      });
      await db.aIJob.deleteMany({ where: owner });
      await db.aiUsage.deleteMany({ where: owner });
      await db.imageAsset.deleteMany({ where: owner });
      await db.user.deleteMany({ where: { id: { in: users } } });
      if (variantId) await db.inventory.deleteMany({ where: { variantId } });
      if (productId) {
        await db.productVariant.deleteMany({ where: { productId } });
        await db.product.delete({ where: { id: productId } });
      }
      if (categoryId) await db.category.delete({ where: { id: categoryId } });
      if (brandId) await db.brand.delete({ where: { id: brandId } });
    }
    await app?.close();
  });
  it('reports missing configuration without reserving quota', async () => {
    const c = await customer();
    config.set('GEMINI_API_KEY', '');
    await request(app.getHttpServer())
      .get('/api/v1/ai/try-on/status')
      .expect(401);
    expect(
      (await get(c.token, 'ai/try-on/status').expect(200)).body.configured,
    ).toBe(false);
    await create(c.token, randomUUID()).expect(503);
    expect(await db.aiUsage.count({ where: { userId: c.id } })).toBe(0);
    expect(send).not.toHaveBeenCalled();
  });
  it('recovers a private upload with the same key and refuses changed bytes', async () => {
    const c = await customer(),
      key = randomUUID();
    const first = await upload(c.token, key).expect(201),
      replay = await upload(c.token, key).expect(201);
    expect(replay.body.id).toBe(first.body.id);
    expect(replay.body.requestKey).toBe(key);
    expect(await db.imageAsset.count({ where: { userId: c.id } })).toBe(1);
    const changed = await sharp({
      create: { width: 64, height: 80, channels: 3, background: 'red' },
    })
      .png()
      .toBuffer();
    await upload(c.token, key, changed).expect(409);
    const metadata = await get(
      c.token,
      'uploads/images/' + first.body.id,
    ).expect(200);
    expect(metadata.body.url).toBeUndefined();
    expect(JSON.stringify(metadata.body)).not.toContain('X-Amz');
    const bytes = await get(
      c.token,
      'uploads/images/' + first.body.id + '/content',
    ).expect(200);
    expect(bytes.headers['cache-control']).toContain('no-store');
    expect((await sharp(bytes.body as Buffer).metadata()).width).toBe(64);
    const other = await customer();
    await get(
      other.token,
      'uploads/images/' + first.body.id + '/content',
    ).expect(404);
  });
  it('reserves one job for racing matching requests and recovers it through an owned list', async () => {
    const c = await customer(),
      other = await customer(),
      key = randomUUID();
    const image = (await upload(c.token).expect(201)).body.id;
    const results = await Promise.all([
      create(c.token, image, key),
      create(c.token, image, key),
    ]);
    expect(results.map((r) => r.status)).toEqual([201, 201]);
    expect(results[0].body.id).toBe(results[1].body.id);
    expect(results[0].body.requestKey).toBe(key);
    expect(await db.aiUsage.count({ where: { userId: c.id } })).toBe(1);
    expect(await db.aIJob.count({ where: { userId: c.id } })).toBe(1);
    expect(
      await db.outboxEvent.count({ where: { jobId: results[0].body.id } }),
    ).toBe(1);
    await create(c.token, image, key, 'changed-sku').expect(409);
    await create(other.token, image).expect(404);
    expect(
      (await get(c.token, 'ai/try-on/jobs').expect(200)).body.items[0]
        .requestKey,
    ).toBe(key);
    expect(
      (await get(other.token, 'ai/try-on/jobs').expect(200)).body.items,
    ).toEqual([]);
    config.set('GEMINI_API_KEY', '');
    expect((await create(c.token, image, key).expect(201)).body.id).toBe(
      results[0].body.id,
    );
  });
  it('claims a job once and publishes only authenticated private result bytes', async () => {
    const c = await customer(),
      other = await customer(),
      image = (await upload(c.token).expect(201)).body.id;
    const created = (await create(c.token, image).expect(201)).body;
    const worker = processor();
    await Promise.all([
      worker.process(job(created.id)),
      worker.process(job(created.id)),
    ]);
    expect(send).toHaveBeenCalledTimes(1);
    const body = JSON.parse(send.mock.calls[0][1]!.body as string);
    expect(
      body.input.filter((p: { type: string }) => p.type === 'image'),
    ).toHaveLength(2);
    const done = (
      await get(c.token, 'ai/try-on/jobs/' + created.id).expect(200)
    ).body;
    expect(done).toMatchObject({ status: 'completed', resultAvailable: true });
    expect(done.resultUrl).toBeUndefined();
    const result = await get(
      c.token,
      'ai/try-on/jobs/' + created.id + '/result',
    ).expect(200);
    expect(result.headers['cache-control']).toContain('no-store');
    expect((await sharp(result.body as Buffer).metadata()).height).toBe(80);
    await get(other.token, 'ai/try-on/jobs/' + created.id + '/result').expect(
      404,
    );
    await worker.process(job(created.id));
    expect(send).toHaveBeenCalledTimes(1);
    await request(app.getHttpServer())
      .delete('/api/v1/uploads/images/' + image)
      .auth(c.token, { type: 'bearer' })
      .expect(202);
    await get(c.token, 'ai/try-on/jobs/' + created.id + '/result').expect(404);
    await get(c.token, 'uploads/images/' + image + '/content').expect(404);
  });
  it('does not publish when the owner deletes a photo during generation', async () => {
    const c = await customer(),
      image = (await upload(c.token).expect(201)).body.id;
    const created = (await create(c.token, image).expect(201)).body;
    let release!: () => void, entered!: () => void;
    const gate = new Promise<void>((r) => {
        release = r;
      }),
      started = new Promise<void>((r) => {
        entered = r;
      });
    send.mockImplementationOnce(async () => {
      entered();
      await gate;
      return imageResponse();
    });
    const work = processor()
      .process(job(created.id))
      .catch(() => undefined);
    try {
      await started;
      await request(app.getHttpServer())
        .delete('/api/v1/uploads/images/' + image)
        .auth(c.token, { type: 'bearer' })
        .expect(202);
    } finally {
      release();
    }
    await work;
    expect(send).toHaveBeenCalledTimes(1);
    expect(await db.tryOnResult.count({ where: { jobId: created.id } })).toBe(
      0,
    );
    await get(c.token, 'ai/try-on/jobs/' + created.id + '/result').expect(404);
  });
  it('settles queued expiry and uncertain processing without another provider call', async () => {
    for (const processing of [false, true]) {
      const c = await customer(),
        image = (await upload(c.token).expect(201)).body.id;
      const created = (await create(c.token, image).expect(201)).body;
      await db.aiUsage.updateMany({
        where: { userId: c.id },
        data: {
          ...(processing ? { status: 'PROCESSING' as const } : {}),
          deadlineAt: new Date(0),
        },
      });
      if (processing)
        await db.aIJob.update({
          where: { id: created.id },
          data: { status: 'PROCESSING', attempts: 1 },
        });
      await processor().process(job(created.id));
      const r = (await get(c.token, 'ai/try-on/jobs/' + created.id).expect(200))
        .body;
      expect(r.status).toBe('failed');
      expect(r.errorCode).toBe(
        processing ? 'AI_OUTCOME_UNKNOWN' : 'AI_QUEUE_EXPIRED',
      );
    }
    expect(send).not.toHaveBeenCalled();
  });
  it('enforces the paid allowance and preserves replay at its limit', async () => {
    const c = await customer(),
      image = (await upload(c.token).expect(201)).body.id,
      key = randomUUID();
    config.set('AI_TRYON_USER_DAILY_LIMIT', 1);
    await create(c.token, image, key).expect(201);
    await create(c.token, image).expect(429);
    await create(c.token, image, key).expect(201);
    expect(
      (await get(c.token, 'ai/try-on/status').expect(200)).body,
    ).toMatchObject({
      used: 1,
      remaining: 0,
      estimatedUsedVnd: '3000',
      costIsEstimate: true,
    });
  });
  it('rejects missing consent/key or newly unavailable stock without a paid call', async () => {
    const c = await customer(),
      image = (await upload(c.token).expect(201)).body.id;
    await request(app.getHttpServer())
      .post('/api/v1/ai/try-on/jobs')
      .auth(c.token, { type: 'bearer' })
      .set('Idempotency-Key', randomUUID())
      .send({ imageId: image, sku, consent: false })
      .expect(400);
    await request(app.getHttpServer())
      .post('/api/v1/ai/try-on/jobs')
      .auth(c.token, { type: 'bearer' })
      .send({ imageId: image, sku, consent: true })
      .expect(400);
    const created = (await create(c.token, image).expect(201)).body;
    await db.inventory.update({ where: { variantId }, data: { quantity: 0 } });
    try {
      await create(c.token, image).expect(404);
      await expect(processor().process(job(created.id))).rejects.toThrow(
        'AI_CATALOG_CHANGED',
      );
    } finally {
      await db.inventory.update({
        where: { variantId },
        data: { quantity: 3 },
      });
    }
    expect(send).not.toHaveBeenCalled();
  });
  it('shares the global estimated budget under concurrent reservations', async () => {
    const a = await customer(),
      b = await customer();
    const first = (await upload(a.token).expect(201)).body.id,
      second = (await upload(b.token).expect(201)).body.id;
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);
    const spent = await db.aiUsage.aggregate({
      where: { createdAt: { gte: today } },
      _sum: { estimatedCostVnd: true },
    });
    config.set(
      'AI_GLOBAL_DAILY_ESTIMATE_VND',
      Number(spent._sum.estimatedCostVnd ?? 0) + 3000,
    );
    const replies = await Promise.all([
      create(a.token, first),
      create(b.token, second),
    ]);
    expect(replies.map((r) => r.status).sort()).toEqual([201, 429]);
    expect(
      await db.aiUsage.count({ where: { userId: { in: [a.id, b.id] } } }),
    ).toBe(1);
  });
  it('does not resurrect a result completed after its processing deadline', async () => {
    const c = await customer(),
      image = (await upload(c.token).expect(201)).body.id;
    const created = (await create(c.token, image).expect(201)).body;
    let release!: () => void, entered!: () => void;
    const gate = new Promise<void>((r) => {
        release = r;
      }),
      started = new Promise<void>((r) => {
        entered = r;
      });
    send.mockImplementationOnce(async () => {
      entered();
      await gate;
      return imageResponse();
    });
    const worker = processor(),
      work = worker.process(job(created.id)).catch(() => undefined);
    try {
      await started;
      await db.aiUsage.updateMany({
        where: { userId: c.id },
        data: { deadlineAt: new Date(0) },
      });
      await usage.cleanup();
    } finally {
      release();
    }
    await work;
    await worker.process(job(created.id));
    const result = (
      await get(c.token, 'ai/try-on/jobs/' + created.id).expect(200)
    ).body;
    expect(result).toMatchObject({
      status: 'failed',
      errorCode: 'AI_OUTCOME_UNKNOWN',
      resultAvailable: false,
    });
    expect(await db.tryOnResult.count({ where: { jobId: created.id } })).toBe(
      0,
    );
    expect(send).toHaveBeenCalledTimes(1);
  });
  it('racing upload retries create one private object', async () => {
    const c = await customer(),
      key = randomUUID();
    const responses = await Promise.all([
      upload(c.token, key),
      upload(c.token, key),
    ]);
    expect(responses.every((r) => [201, 409].includes(r.status))).toBe(true);
    expect(responses.some((r) => r.status === 201)).toBe(true);
    const recovered = await upload(c.token, key).expect(201);
    expect(recovered.body.id).toBe(
      responses.find((r) => r.status === 201)!.body.id,
    );
    expect(await db.imageAsset.count({ where: { userId: c.id } })).toBe(1);
  });
});
