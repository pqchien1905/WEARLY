import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID, createHash } from 'node:crypto';
import { AddressInfo, createServer, createConnection, Socket } from 'node:net';
import { SMTPServer } from 'smtp-server';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { validateEnv } from '../src/config/env.validation';
import {
  RecoveryService,
  databaseNow,
} from '../src/modules/recovery/recovery.service';
import { RecoveryWorker } from '../src/worker/recovery.worker';
import { RECOVERY_QUEUE } from '../src/modules/recovery/recovery.queue';
import { Job, Queue } from 'bullmq';
import { AuthService } from '../src/modules/auth/auth.service';
import { RecoveryMailer } from '../src/modules/recovery/recovery.mailer';
import argon2 from 'argon2';

const redisDescribe = process.env.TEST_REDIS_HOST ? describe : describe.skip;
redisDescribe('Password recovery with PostgreSQL, Redis and SMTP', () => {
  let app: INestApplication, db: PrismaService, smtp: SMTPServer;
  const suffix = randomUUID();
  const email = `recovery-${suffix}@example.test`;
  const password = 'Recovery-original-2026';
  const nextPassword = 'Recovery-replaced-2026';
  const mails: string[] = [];
  const users: string[] = [];
  let access: string, refresh: string;
  let recovery: RecoveryService, worker: RecoveryWorker, queue: Queue;
  let rejectMail = false;
  const eventually = async (condition: () => Promise<boolean> | boolean) => {
    for (let i = 0; i < 100; i++) {
      if (await condition()) return;
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    throw new Error('Expected recovery state did not arrive');
  };
  const mailToken = (mail: string) => {
    const split = mail.indexOf('\r\n\r\n');
    const headers = mail.slice(0, split);
    const body = mail.slice(split + 4);
    const decoded = /Content-Transfer-Encoding: base64/i.test(headers)
      ? Buffer.from(body.replace(/\s/g, ''), 'base64').toString()
      : body
          .replace(/=\r\n/g, '')
          .replace(/=([0-9A-F]{2})/gi, (_, hex: string) =>
            String.fromCharCode(parseInt(hex, 16)),
          );
    const token = decoded.match(/token=([A-Za-z0-9_-]{43})/)?.[1];
    if (!token) throw new Error('Reset token absent from delivered mail');
    return token;
  };
  const issue = async () => {
    await eventually(async () => {
      const counts = await queue.getJobCounts('waiting', 'active');
      return counts.waiting === 0 && counts.active === 0;
    });
    const before = mails.length;
    await recovery.process({
      kind: 'request',
      email,
      requestedAt: (await databaseNow(db)).toISOString(),
    });
    expect(mails.length).toBe(before + 1);
    return mailToken(mails[before]);
  };
  const call = (path: string) =>
    request(app.getHttpServer()).post('/api/v1/auth/' + path);
  beforeAll(async () => {
    if (
      !process.env.TEST_DATABASE_URL ||
      !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test')
    )
      throw new Error('Dedicated _test database required');
    smtp = new SMTPServer({
      authOptional: true,
      disabledCommands: ['AUTH', 'STARTTLS'],
      logger: false,
      onData(stream, _session, callback) {
        let text = '';
        stream.on('data', (chunk: Buffer) => {
          text += chunk.toString();
        });
        stream.on('end', () => {
          if (rejectMail)
            callback(new Error('simulated-sensitive-recipient@example.test'));
          else {
            mails.push(text);
            callback();
          }
        });
      },
    });
    await new Promise<void>((resolve) => smtp.listen(0, '127.0.0.1', resolve));
    const config = validateEnv({
      ...process.env,
      NODE_ENV: 'test',
      DATABASE_URL: process.env.TEST_DATABASE_URL,
      REDIS_HOST: process.env.TEST_REDIS_HOST,
      REDIS_PORT: process.env.TEST_REDIS_PORT ?? '6379',
      AI_QUEUE_PREFIX: 'recovery-test-' + suffix,
      JWT_ACCESS_SECRET: 'test-access-'.repeat(5),
      JWT_REFRESH_SECRET: 'test-refresh-'.repeat(5),
      CORS_ORIGINS: 'http://localhost:4183',
      PASSWORD_RECOVERY_ENABLED: 'true',
      SMTP_HOST: '127.0.0.1',
      SMTP_PORT: (smtp.server.address() as AddressInfo).port,
      SMTP_FROM: 'store@example.test',
      SMTP_ALLOW_INSECURE_LOCAL: 'true',
      PASSWORD_RESET_WEB_URL: 'http://localhost:4183/#/reset-password',
    });
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ConfigService)
      .useValue(new ConfigService(config))
      .compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    recovery = app.get(RecoveryService);
    queue = new Queue(RECOVERY_QUEUE, {
      prefix: config.AI_QUEUE_PREFIX,
      connection: { host: config.REDIS_HOST, port: config.REDIS_PORT },
    });
    await queue.waitUntilReady();
    worker = new RecoveryWorker(app.get(ConfigService), recovery);
    worker.onModuleInit();
    const registered = await call('register')
      .send({ email, password, name: 'Recovery test' })
      .expect(201);
    users.push(registered.body.user.id);
    access = registered.body.accessToken;
    refresh = registered.body.refreshToken;
  });
  afterAll(async () => {
    try {
      if (worker) await worker.onModuleDestroy();
      // Only this test's unique Redis namespace; never clear application queues.
      if (queue) {
        await queue.obliterate({ force: true });
        await queue.close();
      }
      if (db) await db.user.deleteMany({ where: { id: { in: users } } });
    } finally {
      if (app) await app.close();
      if (smtp) await new Promise<void>((resolve) => smtp.close(resolve));
    }
  });
  it('accepts existing and unknown email identically without returning a token', async () => {
    const known = await call('forgot-password').send({ email }).expect(202);
    const unknown = await call('forgot-password')
      .send({ email: `absent-${suffix}@example.test` })
      .expect(202);
    expect(known.body).toEqual({ accepted: true });
    expect(unknown.body).toEqual(known.body);
    await call('forgot-password').send({ email: 'invalid' }).expect(400);
    await eventually(() => mails.length === 1);
    await call('forgot-password')
      .send({ email: email.toUpperCase() })
      .expect(202);
    await eventually(
      async () => (await queue.getJobCounts('waiting', 'active')).active === 0,
    );
    expect(mails).toHaveLength(1);
    const token = mailToken(mails[0]);
    const row = await db.passwordResetToken.findUnique({
      where: { tokenHash: createHash('sha256').update(token).digest('hex') },
    });
    expect(Boolean(row)).toBe(true);
    expect(row!.tokenHash).not.toBe(token);
    expect(
      row!.expiresAt.getTime() - row!.createdAt.getTime(),
    ).toBeLessThanOrEqual(900100);
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .auth(access, { type: 'bearer' })
      .expect(200);
  });
  it('atomically consumes one link, invalidates other links and revokes all sessions', async () => {
    const first = mailToken(mails[0]);
    const other = await issue();
    await db.user.update({ where: { id: users[0] }, data: { role: 'ADMIN' } });
    const adminSession = await call('admin/login')
      .send({ email, password })
      .expect(201);
    await call('reset-password')
      .send({ token: first, password: 'short' })
      .expect(400);
    const results = await Promise.all(
      [1, 2].map(() =>
        call('reset-password').send({ token: first, password: nextPassword }),
      ),
    );
    expect(results.map((r) => r.status).sort()).toEqual([200, 400]);
    await call('reset-password').send({ token: other, password }).expect(400);
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .auth(access, { type: 'bearer' })
      .expect(401);
    await call('refresh').send({ refreshToken: refresh }).expect(401);
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .auth(adminSession.body.accessToken, { type: 'bearer' })
      .expect(401);
    await call('login').send({ email, password }).expect(401);
    await call('login').send({ email, password: nextPassword }).expect(201);
    expect(
      await db.refreshToken.count({
        where: { userId: users[0], revokedAt: null },
      }),
    ).toBe(1);
    await eventually(() =>
      mails.some(
        (mail) =>
          !(() => {
            try {
              mailToken(mail);
              return true;
            } catch {
              return false;
            }
          })(),
      ),
    );
  });
  it('rejects expired links and old queued requests after password change', async () => {
    const count = await db.passwordResetToken.count({
      where: { userId: users[0] },
    });
    await recovery.process({
      kind: 'request',
      email,
      requestedAt: '2000-01-01T00:00:00.000Z',
    });
    expect(
      await db.passwordResetToken.count({ where: { userId: users[0] } }),
    ).toBe(count);
    const token = await issue();
    await db.passwordResetToken.update({
      where: { tokenHash: createHash('sha256').update(token).digest('hex') },
      data: { expiresAt: new Date(0) },
    });
    await call('reset-password').send({ token, password }).expect(400);
    const fake = Buffer.alloc(32, 1).toString('base64url');
    await call('reset-password').send({ token: fake, password }).expect(400);
  });
  it('prevents an already verified old-password login from creating a session after reset', async () => {
    const token = await issue();
    const auth = app.get(AuthService);
    const realVerify = argon2.verify;
    let release!: () => void, entered!: () => void;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const reached = new Promise<void>((resolve) => {
      entered = resolve;
    });
    const spy = jest
      .spyOn(argon2, 'verify')
      .mockImplementationOnce(async (...args) => {
        const valid = await realVerify(...args);
        entered();
        await gate;
        return valid;
      });
    const pending = auth.login({ email, password: nextPassword }).then(
      () => 'issued',
      () => 'rejected',
    );
    try {
      await reached;
      await call('reset-password').send({ token, password }).expect(200);
    } finally {
      release();
      spy.mockRestore();
    }
    expect(await pending).toBe('rejected');
    expect(
      await db.refreshToken.count({
        where: { userId: users[0], revokedAt: null },
      }),
    ).toBe(0);
    const logged = await call('login').send({ email, password }).expect(201);
    const nextToken = await issue();
    const raced = await Promise.all([
      call('refresh').send({ refreshToken: logged.body.refreshToken }),
      call('reset-password').send({ token: nextToken, password: nextPassword }),
    ]);
    expect(raced[1].status).toBe(200);
    expect([201, 401]).toContain(raced[0].status);
    expect(
      await db.refreshToken.count({
        where: { userId: users[0], revokedAt: null },
      }),
    ).toBe(0);
  });
  it('revokes failed SMTP attempts and persists only sanitized queue failures', async () => {
    rejectMail = true;
    let attempt!: Job;
    try {
      const job = await queue.add(
        'request',
        {
          kind: 'request',
          email,
          requestedAt: (await databaseNow(db)).toISOString(),
        },
        {
          attempts: 1,
          removeOnFail: false,
        },
      );
      attempt = job;
      await eventually(async () => (await job.getState()) === 'failed');
      const failed = await queue.getJob(job.id!);
      expect(failed!.failedReason).toBe('RECOVERY_DELIVERY_FAILED');
      expect((failed!.stacktrace ?? []).join(' ')).not.toContain(
        'simulated-sensitive',
      );
      expect(
        await db.passwordResetToken.count({
          where: {
            userId: users[0],
            consumedAt: null,
            expiresAt: { gt: new Date() },
          },
        }),
      ).toBe(0);
      await job.retry();
      await eventually(async () => (await job.getState()) === 'failed');
    } finally {
      rejectMail = false;
    }
    const token = await issue();
    await call('reset-password').send({ token, password }).expect(200);
    const count = await db.passwordResetToken.count({
      where: { userId: users[0] },
    });
    await attempt.retry();
    await eventually(async () => (await attempt.getState()) === 'completed');
    expect(
      await db.passwordResetToken.count({ where: { userId: users[0] } }),
    ).toBe(count);
  });
  it('does not send mail for inactive accounts and limits public request frequency', async () => {
    await eventually(
      async () => (await queue.getJobCounts('active')).active === 0,
    );
    const before = mails.length;
    await db.user.update({ where: { id: users[0] }, data: { active: false } });
    const tokenCount = await db.passwordResetToken.count({
      where: { userId: users[0] },
    });
    await call('forgot-password').send({ email }).expect(202);
    await recovery.process({
      kind: 'request',
      email,
      requestedAt: (await databaseNow(db)).toISOString(),
    });
    expect(mails.length).toBe(before);
    expect(
      await db.passwordResetToken.count({ where: { userId: users[0] } }),
    ).toBe(tokenCount);
    let limited = false;
    for (let i = 0; i < 11; i++) {
      const response = await call('forgot-password').send({
        email: `limited-${i}-${suffix}@example.test`,
      });
      if (response.status === 429) {
        limited = true;
        break;
      }
      expect(response.status).toBe(202);
      expect(response.body).toEqual({ accepted: true });
    }
    expect(limited).toBe(true);
  });
  it('returns the same unavailable response when explicitly disabled', async () => {
    const original = app.get(ConfigService);
    const config = new ConfigService(
      validateEnv({
        DATABASE_URL: process.env.TEST_DATABASE_URL,
        NODE_ENV: 'test',
        JWT_ACCESS_SECRET: original.get('JWT_ACCESS_SECRET'),
        JWT_REFRESH_SECRET: original.get('JWT_REFRESH_SECRET'),
        CORS_ORIGINS: 'http://localhost:4183',
      }),
    );
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ConfigService)
      .useValue(config)
      .compile();
    const disabled = module.createNestApplication({ logger: false });
    configureApp(disabled);
    await disabled.init();
    try {
      for (const address of [email, 'absent@example.test']) {
        const result = await request(disabled.getHttpServer())
          .post('/api/v1/auth/forgot-password')
          .send({ email: address })
          .expect(503);
        expect(result.body.error.code).toBe('RECOVERY_UNAVAILABLE');
      }
    } finally {
      await disabled.close();
    }
  });
  it('bounds HTTP enqueue latency when an established Redis connection stops answering', async () => {
    let stalled = false;
    const sockets = new Set<Socket>();
    const proxy = createServer((downstream) => {
      const upstream = createConnection({
        host: process.env.TEST_REDIS_HOST!,
        port: Number(process.env.TEST_REDIS_PORT ?? 6379),
      });
      for (const socket of [downstream, upstream]) {
        sockets.add(socket);
        socket.on('error', () => undefined);
        socket.on('close', () => sockets.delete(socket));
      }
      downstream.on('data', (data) => {
        if (!stalled) upstream.write(data);
      });
      upstream.on('data', (data) => {
        if (!stalled) downstream.write(data);
      });
    });
    await new Promise<void>((resolve) => proxy.listen(0, '127.0.0.1', resolve));
    const original = app.get(ConfigService);
    const isolatedPrefix = 'recovery-stall-' + suffix;
    const values: Record<string, unknown> = {
      PASSWORD_RECOVERY_ENABLED: 'true',
      REDIS_HOST: '127.0.0.1',
      REDIS_PORT: (proxy.address() as AddressInfo).port,
      AI_QUEUE_PREFIX: isolatedPrefix,
      JWT_ACCESS_SECRET: original.get('JWT_ACCESS_SECRET'),
    };
    const isolated = new RecoveryService(
      db,
      new ConfigService(values),
      app.get(RecoveryMailer),
    );
    isolated.onModuleInit();
    const cleanup = new Queue(RECOVERY_QUEUE, {
      prefix: isolatedPrefix,
      connection: {
        host: process.env.TEST_REDIS_HOST,
        port: Number(process.env.TEST_REDIS_PORT ?? 6379),
      },
    });
    try {
      await eventually(async () => {
        try {
          await isolated.request('absent-stall@example.test');
          return true;
        } catch {
          return false;
        }
      });
      stalled = true;
      const started = Date.now();
      await expect(
        isolated.request('absent-stall-2@example.test'),
      ).rejects.toMatchObject({ status: 503 });
      expect(Date.now() - started).toBeLessThan(4500);
    } finally {
      stalled = false;
      try {
        await isolated.onModuleDestroy();
      } finally {
        for (const socket of sockets) socket.destroy();
        await new Promise<void>((resolve) => proxy.close(() => resolve()));
        await cleanup.obliterate({ force: true });
        await cleanup.close();
      }
    }
  });
  it('removes expired recovery credentials without removing current links or user records', async () => {
    const owner = await db.user.findUniqueOrThrow({ where: { id: users[0] } });
    const id = randomUUID();
    await db.passwordResetToken.create({
      data: {
        id,
        userId: owner.id,
        tokenHash: createHash('sha256').update(id).digest('hex'),
        expiresAt: new Date(Date.now() + 60000),
      },
    });
    await recovery.purgeExpired();
    expect(
      await db.passwordResetToken.count({
        where: { expiresAt: { lte: new Date() } },
      }),
    ).toBe(0);
    expect(await db.passwordResetToken.count({ where: { id } })).toBe(1);
    expect(await db.user.count({ where: { id: owner.id } })).toBe(1);
  });
});
