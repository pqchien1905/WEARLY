import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ThrottlerGuard } from '@nestjs/throttler';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import Redis from 'ioredis';
import { Queue } from 'bullmq';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { validateEnv } from '../src/config/env.validation';
import { WorkerHeartbeat } from '../src/modules/operations/worker-heartbeat.service';
import {
  operationsResources,
  OperationsProbes,
} from '../src/modules/operations/operations.probes';

const redisDescribe = process.env.TEST_REDIS_HOST ? describe : describe.skip;
redisDescribe(
  'Private operations diagnostics with real PostgreSQL and Redis',
  () => {
    let app: INestApplication, db: PrismaService, redis: Redis, queue: Queue;
    const prefix = `operations-${randomUUID()}`,
      users: string[] = [],
      mailIds: string[] = [];
    let admin: string, manager: string, customer: string;
    const get = (token?: string) => {
      const r = request(app.getHttpServer()).get('/api/v1/admin/operations');
      return token ? r.auth(token, { type: 'bearer' }) : r;
    };
    beforeAll(async () => {
      if (
        !new URL(
          process.env.TEST_DATABASE_URL ?? 'http://invalid',
        ).pathname.endsWith('_test')
      )
        throw Error('Dedicated test DB required');
      process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
      const env = validateEnv({
        ...process.env,
        NODE_ENV: 'test',
        AI_QUEUE_PREFIX: prefix,
        REDIS_HOST: process.env.TEST_REDIS_HOST,
        REDIS_PORT: process.env.TEST_REDIS_PORT ?? 6379,
        S3_ENDPOINT: process.env.TEST_S3_ENDPOINT ?? 'http://127.0.0.1:1',
        S3_BUCKET: process.env.TEST_S3_BUCKET ?? 'operations-test',
        GEMINI_API_KEY: '',
        VNPAY_ENABLED: 'false',
        LOCAL_MAIL_ENABLED: 'false',
        PASSWORD_RECOVERY_ENABLED: 'false',
      });
      const module = await Test.createTestingModule({ imports: [AppModule] })
        .overrideProvider(ConfigService)
        .useValue(new ConfigService(env))
        .overrideGuard(ThrottlerGuard)
        .useValue({ canActivate: () => true })
        .compile();
      app = module.createNestApplication({ logger: false });
      configureApp(app);
      await app.init();
      db = app.get(PrismaService);
      redis = new Redis({
        host: env.REDIS_HOST,
        port: env.REDIS_PORT,
        maxRetriesPerRequest: 0,
      });
      queue = new Queue('wearly-try-on', { connection: redis, prefix });
      for (const role of ['ADMIN', 'MANAGER', 'CUSTOMER'] as const) {
        const r = await request(app.getHttpServer())
          .post('/api/v1/auth/register')
          .send({
            email: `ops-${randomUUID()}@example.test`,
            name: 'Private operations fixture',
            password: 'Operations-fixture-2026',
          })
          .expect(201);
        users.push(r.body.user.id);
        await db.user.update({ where: { id: r.body.user.id }, data: { role } });
        if (role === 'ADMIN') admin = r.body.accessToken;
        else if (role === 'MANAGER') manager = r.body.accessToken;
        else customer = r.body.accessToken;
      }
    });
    afterAll(async () => {
      if (queue) {
        await queue.obliterate({ force: true });
        await queue.close();
      }
      if (redis) {
        await redis.del(
          `${prefix}:monitor:worker`,
          `${prefix}-foreign:monitor:worker`,
        );
        redis.disconnect();
      }
      if (db) {
        await db.mailOutbox.deleteMany({ where: { id: { in: mailIds } } });
        await db.aiUsage.deleteMany({ where: { userId: { in: users } } });
        await db.user.deleteMany({ where: { id: { in: users } } });
      }
      if (app) await app.close();
    });
    it('allows only ADMIN and marks the response private and non-cacheable', async () => {
      await get().expect(401);
      await get(customer).expect(403);
      await get(manager).expect(403);
      const r = await get(admin).expect(200);
      expect(r.headers['cache-control']).toContain('no-store');
      expect(r.headers['cache-control']).toContain('private');
      expect(r.body.database).toMatchObject({
        status: 'ok',
        schemaReady: true,
      });
      expect(r.body.database.migrations).toBeGreaterThanOrEqual(26);
      expect(r.body.mail.status).toBe('disabled');
      expect(r.body.providers.gemini.configured).toBe(false);
      expect(r.body.providers.vnpay.configured).toBe(false);
    });
    it('reports exact aggregate deltas, sanitizes failure codes and never returns private rows', async () => {
      const before = (await get(admin).expect(200)).body;
      await db.aiUsage.createMany({
        data: [
          {
            userId: users[0],
            kind: 'TRY_ON',
            requestKey: randomUUID(),
            inputHash: 'a'.repeat(64),
            model: 'gemini-fixture',
            estimatedCostVnd: 3000,
            status: 'RESERVED',
            deadlineAt: new Date(Date.now() - 1000),
            expiresAt: new Date(Date.now() + 60000),
          },
          {
            userId: users[0],
            kind: 'STYLIST',
            requestKey: randomUUID(),
            inputHash: 'b'.repeat(64),
            model: 'gemini-fixture',
            estimatedCostVnd: 500,
            status: 'FAILED',
            errorCode: 'private-customer-secret',
            deadlineAt: new Date(),
            expiresAt: new Date(Date.now() + 60000),
          },
        ],
      });
      const mail = await db.mailOutbox.create({
        data: {
          eventKey: randomUUID(),
          recipient: 'private-mail@example.test',
          subject: 'private-subject',
          body: 'private-body',
          status: 'FAILED',
        },
      });
      mailIds.push(mail.id);
      const after = (await get(admin).expect(200)).body;
      expect(after.work.ai.reserved).toBe(before.work.ai.reserved + 1);
      expect(after.work.ai.stale).toBe(before.work.ai.stale + 1);
      expect(after.work.ai.todayCount).toBe(before.work.ai.todayCount + 2);
      expect(
        BigInt(after.work.ai.todayEstimatedVnd) -
          BigInt(before.work.ai.todayEstimatedVnd),
      ).toBe(3500n);
      expect(after.work.mail.failed).toBe(before.work.mail.failed + 1);
      expect(after.work.ai.failures).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            kind: 'STYLIST',
            code: 'OTHER',
            count: expect.any(Number),
          }),
        ]),
      );
      expect(JSON.stringify(after)).not.toMatch(
        /private-|@example|inputHash|recipient|requestKey|objectKey|postgresql:|password/i,
      );
      for (const id of users) expect(JSON.stringify(after)).not.toContain(id);
    });
    it('scopes queue metrics and rejects missing, stale, malformed and foreign heartbeats', async () => {
      await redis.set(
        `${prefix}-foreign:monitor:worker`,
        JSON.stringify({
          instanceId: randomUUID(),
          startedAt: new Date().toISOString(),
          lastAt: new Date().toISOString(),
        }),
        'EX',
        30,
      );
      let r = (await get(admin).expect(200)).body;
      expect(r.worker).toMatchObject({ status: 'unavailable', lastAt: null });
      await queue.add(
        'private-job-name',
        { secret: 'private-queue-payload' },
        { jobId: randomUUID() },
      );
      r = (await get(admin).expect(200)).body;
      expect(r.redis.queues.tryOn.waiting).toBe(1);
      expect(r.redis.queues.tryOn.active).toBe(0);
      expect(r.redis.queues.tryOn.oldestWaitingAt).toEqual(expect.any(String));
      expect(r.redis.queues.recovery).toBeNull();
      expect(JSON.stringify(r)).not.toContain('private-queue');
      const old = new Date(Date.now() - 40000).toISOString();
      await redis.set(
        `${prefix}:monitor:worker`,
        JSON.stringify({
          instanceId: randomUUID(),
          startedAt: old,
          lastAt: old,
        }),
        'EX',
        30,
      );
      expect((await get(admin).expect(200)).body.worker).toMatchObject({
        status: 'unavailable',
        lastAt: old,
      });
      await redis.set(
        `${prefix}:monitor:worker`,
        'private-invalid-heartbeat',
        'EX',
        30,
      );
      expect((await get(admin).expect(200)).body.worker).toMatchObject({
        status: 'unavailable',
        lastAt: null,
      });
      const now = new Date().toISOString();
      await redis.set(
        `${prefix}:monitor:worker`,
        JSON.stringify({
          instanceId: randomUUID(),
          startedAt: now,
          lastAt: now,
        }),
        'EX',
        30,
      );
      expect((await get(admin).expect(200)).body.worker).toMatchObject({
        status: 'ok',
        lastAt: now,
      });
    });
    it('does not let an old worker delete another live worker heartbeat', async () => {
      const config = app.get(ConfigService);
      const first = new WorkerHeartbeat(config, operationsResources);
      const second = new WorkerHeartbeat(config, operationsResources);
      try {
        await first.onModuleInit();
        const before = await redis.get(`${prefix}:monitor:worker`);
        await second.onModuleInit();
        const current = await redis.get(`${prefix}:monitor:worker`);
        expect(current).not.toBe(before);
        await first.onModuleDestroy();
        expect(await redis.get(`${prefix}:monitor:worker`)).toBe(current);
        expect((await get(admin).expect(200)).body.worker.status).toBe('ok');
      } finally {
        await first.onModuleDestroy();
        await second.onModuleDestroy();
      }
      expect(await redis.get(`${prefix}:monitor:worker`)).toBeNull();
    });
    it('reads the Prisma schema even with an alternate search path', async () => {
      const config = app.get(ConfigService),
        url = new URL(config.getOrThrow('DATABASE_URL'));
      url.searchParams.set(
        'options',
        '-c search_path=pg_catalog -c timezone=Asia/Bangkok',
      );
      const alternate = new ConfigService({ DATABASE_URL: url.toString() });
      const result = await new OperationsProbes(
        alternate,
        operationsResources,
      ).database();
      expect(result.database.schemaReady).toBe(true);
      expect(result.work?.ai.dayStartedAt).toMatch(/T00:00:00\+00:00$/);
      expect(result.work?.ai.todayEstimatedVnd).toMatch(/^\d+$/);
    });
    it('observing legacy queue markers never changes the queue', async () => {
      const key = `${prefix}:wearly-try-on:wait`;
      await redis.rpush(key, '0:legacy-marker');
      const before = await redis.lrange(key, 0, -1);
      const snapshot = (await get(admin).expect(200)).body;
      expect(await redis.lrange(key, 0, -1)).toEqual(before);
      expect(snapshot.redis.queues.tryOn.waiting).toBe(1);
      expect(snapshot.redis.queues.tryOn.oldestWaitingAt).toEqual(
        expect.any(String),
      );
      await redis.lrem(key, 0, '0:legacy-marker');
      await queue.pause();
      expect(
        (await get(admin).expect(200)).body.redis.queues.tryOn.waiting,
      ).toBe(1);
      await queue.add(
        'priority-fixture',
        {},
        { priority: 1, jobId: randomUUID() },
      );
      expect(
        (await get(admin).expect(200)).body.redis.queues.tryOn,
      ).toMatchObject({ waiting: 2, oldestWaitingAt: null });
    });
  },
);
