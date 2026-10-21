import 'reflect-metadata';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { Client } from 'pg';
import { PrismaService } from '../src/database/prisma.service';
import { databaseNow } from '../src/modules/recovery/recovery.service';

describe('Database time on native non-UTC PostgreSQL', () => {
  let db: PrismaService;
  const email = `database-${randomUUID()}@example.test`;
  beforeAll(async () => {
    const url = new URL(process.env.TEST_DATABASE_URL ?? 'http://invalid');
    if (!url.pathname.endsWith('_test')) throw new Error('Dedicated _test database required');
    // A URL option has priority over a pg configuration property; exercise it.
    url.searchParams.set('options', '-c timezone=Asia/Bangkok -c statement_timeout=4000');
    const native = new Client({ connectionString: url.toString() });
    await native.connect();
    try {
      expect((await native.query('SHOW timezone')).rows[0].TimeZone).toBe('Asia/Bangkok');
    } finally { await native.end(); }
    db = new PrismaService(new ConfigService({ DATABASE_URL: url.toString() }));
    await db.onModuleInit();
  });
  afterAll(async () => {
    if (db) {
      try { await db.user.deleteMany({ where: { email } }); }
      finally { await db.onModuleDestroy(); }
    }
  });
  it('reads the real instant for recovery, even when the URL requests Bangkok time', async () => {
    const before = Date.now();
    const now = await databaseNow(db);
    expect(now.getTime()).toBeGreaterThanOrEqual(before - 2000);
    expect(now.getTime()).toBeLessThanOrEqual(Date.now() + 2000);
  });
  it('keeps every pooled transaction in UTC while preserving other connection options', async () => {
    const rows = await Promise.all(Array.from({ length: 12 }, () => db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT pg_sleep(0.03)::text`;
      return tx.$queryRaw<{ zone: string; timeout: string }[]>`
        SELECT current_setting('TimeZone') AS zone, current_setting('statement_timeout') AS timeout`;
    })));
    expect(rows.flat()).toEqual(Array.from({ length: 12 }, () => ({ zone: 'UTC', timeout: '4s' })));
  });
  it('stores new business timestamps as the real instant', async () => {
    const before = Date.now();
    const user = await db.user.create({ data: { email, name: 'UTC regression', passwordHash: 'unused-test-hash' } });
    expect(user.createdAt.getTime()).toBeGreaterThanOrEqual(before - 2000);
    expect(user.createdAt.getTime()).toBeLessThanOrEqual(Date.now() + 2000);
  });
});
