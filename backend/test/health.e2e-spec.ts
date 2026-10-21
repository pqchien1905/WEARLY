import 'reflect-metadata';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../src/database/prisma.service';
import { Client } from 'pg';
import { HealthController } from '../src/modules/health/health.controller';
import * as schemaReadiness from '../src/database/schema-readiness';
import { createServer, connect, Socket } from 'node:net';
import { randomUUID } from 'node:crypto';

const redisDescribe = process.env.TEST_REDIS_HOST ? describe : describe.skip;
redisDescribe('Readiness with PostgreSQL schema and Redis', () => {
  let db: PrismaService;
  let config: ConfigService;
  beforeAll(async () => {
    if (!new URL(process.env.TEST_DATABASE_URL ?? 'http://invalid').pathname.endsWith('_test')) {
      throw new Error('Dedicated test DB required');
    }
    config = new ConfigService({
      DATABASE_URL: process.env.TEST_DATABASE_URL,
      REDIS_HOST: process.env.TEST_REDIS_HOST,
      REDIS_PORT: Number(process.env.TEST_REDIS_PORT ?? 6379),
    });
    db = new PrismaService(config);
    await db.onModuleInit();
  });
  afterAll(async () => { if (db) await db.onModuleDestroy(); });
  it('reports ready when required schema and dependencies are available', async () => {
    await expect(new HealthController(config).ready()).resolves.toMatchObject({ status: 'ready', database: true, redis: true });
  });
  it('checks the Prisma schema when the connection search path starts elsewhere', async () => {
    const url = new URL(process.env.TEST_DATABASE_URL!);
    url.searchParams.set('options', '-c search_path=pg_catalog,public');
    const alternateConfig = new ConfigService({ DATABASE_URL: url.toString(), REDIS_HOST: process.env.TEST_REDIS_HOST, REDIS_PORT: Number(process.env.TEST_REDIS_PORT ?? 6379) });
    const alternate = new PrismaService(alternateConfig);
    try {
      await alternate.onModuleInit();
      expect(await alternate.user.count()).toBeGreaterThanOrEqual(0);
      await expect(new HealthController(alternateConfig).ready()).resolves.toMatchObject({ status: 'ready' });
    } finally { await alternate.onModuleDestroy(); }
  });
  it('cancels a stalled database probe before responding unavailable', async () => {
    let settled = false;
    const probe = jest.spyOn(schemaReadiness, 'databaseSchemaReady').mockImplementationOnce(async (tx) => {
      try { await tx.query('SELECT pg_sleep(3)::text'); return true; }
      finally { settled = true; }
    });
    try {
      const start = Date.now();
      await expect(new HealthController(config).ready()).rejects.toMatchObject({ status: 503 });
      expect(Date.now() - start).toBeLessThan(2500);
      expect(settled).toBe(true);
    } finally { probe.mockRestore(); }
  });
  it('closes its database transport when the server stops replying', async () => {
    const url = new URL(process.env.TEST_DATABASE_URL!);
    const target = { port: Number(url.port || 5432), host: url.hostname };
    const sockets = new Set<Socket>();
    let dropReplies = false;
    const proxy = createServer((incoming) => {
      const outgoing = connect(target.port, target.host);
      for (const socket of [incoming, outgoing]) {
        sockets.add(socket);
        socket.on('error', () => undefined);
        socket.on('close', () => { sockets.delete(socket); incoming.destroy(); outgoing.destroy(); });
      }
      incoming.pipe(outgoing);
      outgoing.on('data', (bytes: Buffer) => { if (!dropReplies) incoming.write(bytes); });
    });
    await new Promise<void>((resolve) => proxy.listen(0, '127.0.0.1', resolve));
    const address = proxy.address();
    if (!address || typeof address === 'string') throw new Error('TCP test listener missing');
    const name = `health-stall-${randomUUID()}`;
    url.hostname = '127.0.0.1'; url.port = String(address.port);
    url.searchParams.set('application_name', name);
    const stalledConfig = new ConfigService({ DATABASE_URL: url.toString(), REDIS_HOST: process.env.TEST_REDIS_HOST, REDIS_PORT: Number(process.env.TEST_REDIS_PORT ?? 6379) });
    const realProbe = schemaReadiness.databaseSchemaReady;
    const stub = jest.spyOn(schemaReadiness, 'databaseSchemaReady').mockImplementationOnce((connection) => { dropReplies = true; return realProbe(connection); });
    try {
      await expect(new HealthController(stalledConfig).ready()).rejects.toMatchObject({ status: 503 });
      await new Promise((resolve) => setTimeout(resolve, 100));
      const active = await db.$queryRaw<{ count: bigint }[]>`SELECT count(*) FROM pg_stat_activity WHERE application_name = ${name}`;
      expect(Number(active[0].count)).toBe(0);
    } finally {
      for (const socket of sockets) socket.destroy();
      stub.mockRestore();
      await new Promise<void>((resolve) => proxy.close(() => resolve()));
    }
  });
  async function missingSchema(sql: string) {
    const connection = new Client({ connectionString: process.env.TEST_DATABASE_URL });
    await connection.connect();
    const realProbe = schemaReadiness.databaseSchemaReady;
    const stub = jest.spyOn(schemaReadiness, 'databaseSchemaReady').mockImplementationOnce(() => realProbe(connection));
    try {
      await connection.query('BEGIN');
      await connection.query(sql);
      const health = new HealthController(config);
      expect(health.live()).toMatchObject({ status: 'ok' });
      await expect(health.ready()).rejects.toMatchObject({ status: 503 });
    } finally {
      stub.mockRestore();
      await connection.query('ROLLBACK');
      await connection.end();
    }
  }
  it('refuses readiness when a required column is missing, without changing liveness', async () => {
    await missingSchema(`ALTER TABLE "User" RENAME COLUMN "passwordChangedAt" TO "__health_missing_password_changed_at"`);
  });
  it('refuses readiness when a required table is missing', async () => {
    await missingSchema(`ALTER TABLE "StoreContent" RENAME TO "__health_missing_store_content"`);
  });
  it('returns unavailable promptly if Redis cannot be reached', async () => {
    const failed = new ConfigService({ DATABASE_URL: process.env.TEST_DATABASE_URL, REDIS_HOST: '127.0.0.1', REDIS_PORT: 1 });
    const start = Date.now();
    await expect(new HealthController(failed).ready()).rejects.toMatchObject({ status: 503 });
    expect(Date.now() - start).toBeLessThan(2500);
  });
});
