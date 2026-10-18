import 'reflect-metadata';
import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { Queue } from 'bullmq';
import { Client } from 'pg';
import { WorkerModule } from '../src/worker/worker.module';
import { AiProcessor } from '../src/worker/ai.processor';
import { PrismaService } from '../src/database/prisma.service';
import {
  TryOnInput,
  TryOnOutput,
  TryOnProvider,
} from '../src/integrations/ai-providers/try-on.provider';
import { StorageService } from '../src/integrations/storage/storage.service';
import { AI_QUEUE } from '../src/queues/ai.queue';
import { validateEnv } from '../src/config/env.validation';
import { AiService } from '../src/modules/ai/ai.service';
import { ImageLifecycleService } from '../src/modules/uploads/image-lifecycle.service';

// PostgreSQL and Redis are real. Only paid AI and object storage are test doubles.
const redisDescribe = process.env.TEST_REDIS_HOST ? describe : describe.skip;
redisDescribe('AI worker with PostgreSQL and Redis', () => {
  let module: TestingModule,
    db: PrismaService,
    processor: AiProcessor,
    queue: Queue;
  let userId: string, variantId: string;
  let suiteLock: Client | undefined;
  const namespace = 'wearly-test-' + randomUUID();
  const jobs: string[] = [];
  const provider = {
    enabled: false,
    calls: 0,
    async generate(_input: TryOnInput): Promise<TryOnOutput> {
      this.calls++;
      return { bytes: new Uint8Array([1]), contentType: 'image/png' };
    },
  };
  const storage = {
    signedRead: async (key: string) => 'https://storage.example.test/' + key,
    putResult: jest.fn(async () => undefined),
    deleteObjects: jest.fn(async (_keys: string[]) => undefined),
  };
  beforeAll(async () => {
    if (
      !process.env.TEST_DATABASE_URL ||
      !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test')
    ) {
      throw new Error(
        'A dedicated TEST_DATABASE_URL ending in _test is required',
      );
    }
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    process.env.NODE_ENV = 'test';
    process.env.REDIS_HOST = process.env.TEST_REDIS_HOST;
    process.env.REDIS_PORT = process.env.TEST_REDIS_PORT ?? '6379';
    process.env.AI_QUEUE_PREFIX = namespace;
    process.env.JWT_ACCESS_SECRET = 'test-access-'.repeat(5);
    process.env.JWT_REFRESH_SECRET = 'test-refresh-'.repeat(5);
    process.env.CORS_ORIGINS = 'http://localhost:5173';
    // Queue prefixes isolate Redis; a DB lock also prevents another suite's
    // outbox rows being consumed by this run's provider double.
    suiteLock = new Client({ connectionString: process.env.TEST_DATABASE_URL });
    await suiteLock.connect();
    const lock = await suiteLock.query<{ locked: boolean }>(
      'SELECT pg_try_advisory_lock(hashtext($1)) AS locked',
      ['wearly-worker-e2e'],
    );
    if (!lock.rows[0].locked) {
      throw new Error(
        'Another worker suite is using this test database; run suites sequentially',
      );
    }
    const pending = await suiteLock.query<{ pending: boolean }>(
      `SELECT EXISTS(SELECT 1 FROM "OutboxEvent" WHERE "publishedAt" IS NULL)
       OR EXISTS(SELECT 1 FROM "AIJob" WHERE status IN ('PENDING', 'PROCESSING')) AS pending`,
    );
    if (pending.rows[0].pending) {
      throw new Error(
        'Test database has unfinished AI fixtures; inspect them before running the worker suite',
      );
    }
    module = await Test.createTestingModule({ imports: [WorkerModule] })
      .overrideProvider(ConfigService)
      .useValue(new ConfigService(validateEnv(process.env)))
      .overrideProvider(TryOnProvider)
      .useValue(provider)
      .overrideProvider(StorageService)
      .useValue(storage)
      .compile();
    await module.init();
    db = module.get(PrismaService);
    processor = module.get(AiProcessor);
    const config = module.get(ConfigService);
    queue = new Queue(AI_QUEUE, {
      prefix: namespace,
      connection: {
        host: config.getOrThrow<string>('REDIS_HOST'),
        port: config.getOrThrow<number>('REDIS_PORT'),
      },
    });
    await queue.waitUntilReady();
    const user = await db.user.create({
      data: {
        email: randomUUID() + '@worker.example.test',
        name: 'Worker test',
        passwordHash: 'test-fixture-no-login',
      },
    });
    userId = user.id;
    const category = await db.category.create({
      data: { name: 'Worker test', slug: randomUUID() },
    });
    const brand = await db.brand.create({
      data: { name: 'Worker test', slug: randomUUID() },
    });
    const product = await db.product.create({
      data: {
        name: 'Worker test',
        slug: randomUUID(),
        description: 'Integration fixture',
        material: 'Cotton',
        style: 'Test',
        categoryId: category.id,
        brandId: brand.id,
        tryOnSupported: true,
        variants: {
          create: {
            sku: randomUUID(),
            size: 'M',
            color: 'Black',
            colorHex: '#000000',
            price: '1000',
          },
        },
      },
      include: { variants: true },
    });
    variantId = product.variants[0].id;
  });
  afterAll(async () => {
    try {
      if (module) await module.close();
      // Delete only this run's known jobs, never FLUSHDB or another queue.
      if (queue) {
        for (const id of jobs) {
          const job = await queue.getJob(id);
          if (job) await job.remove();
        }
        await queue.close();
      }
    } finally {
      await suiteLock?.end();
    }
  });
  async function fixture() {
    const image = await db.imageAsset.create({
      data: {
        userId,
        objectKey: 'test/' + randomUUID(),
        mimeType: 'image/png',
        size: 1,
        verifiedAt: new Date(),
        expiresAt: new Date(Date.now() + 3600000),
      },
    });
    const job = await db.aIJob.create({
      data: {
        userId,
        variantId,
        imageId: image.id,
        consentAt: new Date(),
        outbox: { create: {} },
      },
    });
    jobs.push(job.id);
    return job;
  }
  async function terminal(id: string) {
    const end = Date.now() + 15000;
    while (Date.now() < end) {
      const row = await db.aIJob.findUniqueOrThrow({ where: { id } });
      const queued = await queue.getJob(id);
      const state = await queued?.getState();
      if (
        ['COMPLETED', 'FAILED'].includes(row.status) &&
        ['completed', 'failed'].includes(state ?? '')
      )
        return { row, queued: queued! };
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    throw new Error('Job did not reach a terminal state in its isolated queue');
  }
  it('publishes the outbox into an isolated queue and fails a disabled provider without a result', async () => {
    const job = await fixture();
    await processor.dispatch();
    const { row, queued } = await terminal(job.id);
    expect(row.status).toBe('FAILED');
    expect(row.errorCode).toBe('AI_PROVIDER_NOT_CONFIGURED');
    expect(row.attempts).toBe(1);
    expect(queued.failedReason).toBe('AI_PROVIDER_NOT_CONFIGURED');
    expect(await db.tryOnResult.count({ where: { jobId: job.id } })).toBe(0);
    expect(
      (await db.outboxEvent.findUniqueOrThrow({ where: { jobId: job.id } }))
        .publishedAt,
    ).not.toBeNull();
  });
  it('retries three times and keeps provider secrets out of database and Redis errors', async () => {
    provider.enabled = true;
    provider.calls = 0;
    provider.generate = async () => {
      provider.calls++;
      throw new Error(
        'provider-token-should-not-be-stored https://private.example.test/signed',
      );
    };
    const job = await fixture();
    await processor.dispatch();
    const { row, queued } = await terminal(job.id);
    expect(row.status).toBe('FAILED');
    expect(row.attempts).toBe(3);
    expect(provider.calls).toBe(3);
    expect(row.errorCode).toBe('AI_PROVIDER_ERROR');
    expect(queued.failedReason).toBe('AI_PROVIDER_ERROR');
    expect(JSON.stringify(queued.stacktrace)).not.toContain(
      'provider-token-should-not-be-stored',
    );
    expect(await db.tryOnResult.count({ where: { jobId: job.id } })).toBe(0);
  });
  it('rejects an expired image before calling the provider', async () => {
    provider.enabled = true;
    provider.calls = 0;
    const job = await fixture();
    await db.imageAsset.update({
      where: { id: job.imageId },
      data: { expiresAt: new Date(0) },
    });
    await processor.dispatch();
    const { row } = await terminal(job.id);
    expect(row.errorCode).toBe('IMAGE_UNAVAILABLE');
    expect(row.attempts).toBe(1);
    expect(provider.calls).toBe(0);
  });
  it('stores one result and does not generate again when an outbox publication is replayed', async () => {
    provider.enabled = true;
    provider.calls = 0;
    provider.generate = async () => {
      provider.calls++;
      return { bytes: new Uint8Array([1]), contentType: 'image/png' };
    };
    const job = await fixture();
    await processor.dispatch();
    const first = await terminal(job.id);
    expect(first.row.status).toBe('COMPLETED');
    await db.outboxEvent.update({
      where: { jobId: job.id },
      data: { publishedAt: null },
    });
    await processor.dispatch();
    const publishedDeadline = Date.now() + 5000;
    while (
      !(await db.outboxEvent.findUniqueOrThrow({ where: { jobId: job.id } }))
        .publishedAt
    ) {
      if (Date.now() >= publishedDeadline)
        throw new Error('Outbox was not republished');
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    const replay = await terminal(job.id);
    expect(replay.row.attempts).toBe(1);
    expect(provider.calls).toBe(1);
    expect(await db.tryOnResult.count({ where: { jobId: job.id } })).toBe(1);
  });
  it('does not publish a result if the source image is deleted during generation', async () => {
    provider.enabled = true;
    provider.generate = async (input) => {
      const job = await db.aIJob.findUniqueOrThrow({
        where: { id: input.jobId },
      });
      await db.imageAsset.update({
        where: { id: job.imageId },
        data: { deletedAt: new Date() },
      });
      return { bytes: new Uint8Array([1]), contentType: 'image/png' };
    };
    storage.putResult.mockClear();
    const job = await fixture();
    await processor.dispatch();
    const { row } = await terminal(job.id);
    expect(row.status).toBe('FAILED');
    expect(row.errorCode).toBe('IMAGE_UNAVAILABLE');
    expect(storage.putResult).not.toHaveBeenCalled();
    expect(await db.tryOnResult.count({ where: { jobId: job.id } })).toBe(0);
  });
  it('creates a durable job only for the image owner and hides results from other users', async () => {
    provider.enabled = true;
    provider.generate = async () => ({
      bytes: new Uint8Array([1]),
      contentType: 'image/png',
    });
    const image = await db.imageAsset.create({
      data: {
        userId,
        objectKey: 'test/' + randomUUID(),
        mimeType: 'image/png',
        size: 1,
        verifiedAt: new Date(),
        expiresAt: new Date(Date.now() + 3600000),
      },
    });
    const variant = await db.productVariant.findUniqueOrThrow({
      where: { id: variantId },
    });
    const service = new AiService(
      db,
      provider,
      storage as unknown as StorageService,
    );
    const dto = { imageId: image.id, sku: variant.sku, consent: true };
    await expect(service.create(randomUUID(), dto)).rejects.toMatchObject({
      status: 404,
    });
    expect(await db.aIJob.count({ where: { imageId: image.id } })).toBe(0);
    const created = await service.create(userId, dto);
    jobs.push(created.id);
    await processor.dispatch();
    expect((await terminal(created.id)).row.status).toBe('COMPLETED');
    await expect(service.get(randomUUID(), created.id)).rejects.toMatchObject({
      status: 404,
    });
    expect((await service.get(userId, created.id)).resultUrl).toContain(
      'https://storage.example.test/',
    );
  });
  it('serializes deletion against result storage and purges all deterministic job keys', async () => {
    provider.enabled = true;
    provider.generate = async () => ({
      bytes: new Uint8Array([1]),
      contentType: 'image/png',
    });
    const lifecycle = new ImageLifecycleService(
      db,
      storage as unknown as StorageService,
    );
    let release!: () => void, entered!: () => void;
    const waiting = new Promise<void>((resolve) => {
      release = resolve;
    });
    const writing = new Promise<void>((resolve) => {
      entered = resolve;
    });
    storage.putResult.mockImplementationOnce(async () => {
      entered();
      await waiting;
    });
    const job = await fixture();
    await processor.dispatch();
    await writing;
    let deletionFinished = false;
    const deletion = lifecycle.deleteOwned(userId, job.imageId).then(() => {
      deletionFinished = true;
    });
    try {
      await new Promise((resolve) => setTimeout(resolve, 150));
      expect(deletionFinished).toBe(false);
    } finally {
      release();
      await deletion;
    }
    await terminal(job.id);
    const service = new AiService(
      db,
      provider,
      storage as unknown as StorageService,
    );
    expect((await service.get(userId, job.id)).resultUrl).toBeNull();
    expect(await lifecycle.purge(job.imageId)).toBe(true);
    expect(storage.deleteObjects).toHaveBeenCalledWith(
      expect.arrayContaining(['results/' + userId + '/' + job.id]),
    );
    expect(
      (await db.imageAsset.findUniqueOrThrow({ where: { id: job.imageId } }))
        .purgedAt,
    ).not.toBeNull();
  });
  it('cancels pending jobs, purges unrecorded result keys and rejects new jobs on a deleted image', async () => {
    provider.enabled = true;
    const image = await db.imageAsset.create({
      data: {
        userId,
        objectKey: 'test/' + randomUUID(),
        mimeType: 'image/png',
        size: 1,
        verifiedAt: new Date(),
        expiresAt: new Date(Date.now() + 3600000),
      },
    });
    const job = await db.aIJob.create({
      data: { userId, variantId, imageId: image.id, consentAt: new Date() },
    });
    const lifecycle = new ImageLifecycleService(
      db,
      storage as unknown as StorageService,
    );
    await lifecycle.deleteOwned(userId, image.id);
    expect(
      (await db.aIJob.findUniqueOrThrow({ where: { id: job.id } })).status,
    ).toBe('FAILED');
    await lifecycle.purge(image.id);
    expect(storage.deleteObjects).toHaveBeenCalledWith(
      expect.arrayContaining([
        image.objectKey,
        'results/' + userId + '/' + job.id,
      ]),
    );
    const service = new AiService(
      db,
      provider,
      storage as unknown as StorageService,
    );
    const variant = await db.productVariant.findUniqueOrThrow({
      where: { id: variantId },
    });
    await expect(
      service.create(userId, {
        imageId: image.id,
        sku: variant.sku,
        consent: true,
      }),
    ).rejects.toMatchObject({ status: 404 });
  });
  it('bounds jobs per image so cleanup work stays finite', async () => {
    provider.enabled = true;
    const image = await db.imageAsset.create({
      data: {
        userId,
        objectKey: 'test/' + randomUUID(),
        mimeType: 'image/png',
        size: 1,
        verifiedAt: new Date(),
        expiresAt: new Date(Date.now() + 3600000),
      },
    });
    await db.aIJob.createMany({
      data: Array.from({ length: 20 }, () => ({
        userId,
        variantId,
        imageId: image.id,
        consentAt: new Date(),
        status: 'FAILED' as const,
      })),
    });
    const service = new AiService(
      db,
      provider,
      storage as unknown as StorageService,
    );
    const variant = await db.productVariant.findUniqueOrThrow({
      where: { id: variantId },
    });
    await expect(
      service.create(userId, {
        imageId: image.id,
        sku: variant.sku,
        consent: true,
      }),
    ).rejects.toMatchObject({ status: 429 });
    expect(await db.aIJob.count({ where: { imageId: image.id } })).toBe(20);
  });
  it('serializes result signing with deletion and prevents new reads after revocation', async () => {
    const image = await db.imageAsset.create({
      data: {
        userId,
        objectKey: 'test/' + randomUUID(),
        mimeType: 'image/png',
        size: 1,
        verifiedAt: new Date(),
        expiresAt: new Date(Date.now() + 3600000),
      },
    });
    const job = await db.aIJob.create({
      data: {
        userId,
        variantId,
        imageId: image.id,
        consentAt: new Date(),
        status: 'COMPLETED',
        result: {
          create: {
            objectKey: 'results/' + randomUUID(),
            expiresAt: image.expiresAt,
          },
        },
      },
    });
    let release!: () => void, entered!: () => void;
    const waiting = new Promise<void>((resolve) => {
      release = resolve;
    });
    const signing = new Promise<void>((resolve) => {
      entered = resolve;
    });
    const sign = jest
      .spyOn(storage, 'signedRead')
      .mockImplementationOnce(async () => {
        entered();
        await waiting;
        return 'https://storage.example.test/signed';
      });
    const service = new AiService(
      db,
      provider,
      storage as unknown as StorageService,
    );
    const lifecycle = new ImageLifecycleService(
      db,
      storage as unknown as StorageService,
    );
    const read = service.get(userId, job.id);
    await signing;
    let deleted = false;
    const deletion = lifecycle.deleteOwned(userId, image.id).then(() => {
      deleted = true;
    });
    try {
      await new Promise((resolve) => setTimeout(resolve, 150));
      expect(deleted).toBe(false);
    } finally {
      release();
      await Promise.all([read, deletion]);
      sign.mockRestore();
    }
    expect((await service.get(userId, job.id)).resultUrl).toBeNull();
  });
});
