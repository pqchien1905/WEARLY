import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Customer style preferences with PostgreSQL', () => {
  let app: INestApplication, db: PrismaService;
  const users: string[] = [],
    tokens: string[] = [];
  const path = '/api/v1/users/me/style';
  const defaults = {
    size: 'M',
    style: '',
    color: '',
    budget: '1500000',
    version: 0,
  };
  const selection = {
    size: 'L',
    style: 'Tối giản',
    color: 'Đen',
    budget: '800000',
    expectedVersion: 0,
  };
  const get = (user = 0, query = '') =>
    request(app.getHttpServer())
      .get(path + query)
      .auth(tokens[user], { type: 'bearer' });
  const put = (user = 0) =>
    request(app.getHttpServer())
      .put(path)
      .auth(tokens[user], { type: 'bearer' });
  beforeAll(async () => {
    if (
      !process.env.TEST_DATABASE_URL ||
      !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test')
    )
      throw new Error('Dedicated _test database required');
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    process.env.NODE_ENV = 'test';
    process.env.JWT_ACCESS_SECRET = 'test-access-'.repeat(5);
    process.env.JWT_REFRESH_SECRET = 'test-refresh-'.repeat(5);
    app = (
      await Test.createTestingModule({ imports: [AppModule] }).compile()
    ).createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    for (let i = 0; i < 2; i++) {
      const r = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({
          name: 'Style fixture',
          email: `style-${randomUUID()}@example.test`,
          password: 'Style-test-password-2026',
        })
        .expect(201);
      users.push(r.body.user.id);
      tokens.push(r.body.accessToken);
    }
  });
  afterAll(async () => {
    if (db) await db.user.deleteMany({ where: { id: { in: users } } });
    if (app) await app.close();
  });
  it('provides private defaults without writing and rejects invalid fields', async () => {
    await request(app.getHttpServer()).get(path).expect(401);
    await request(app.getHttpServer()).put(path).send(selection).expect(401);
    expect((await get().expect(200)).body).toEqual(defaults);
    const counts = await db.$queryRaw<
      Array<{ count: bigint }>
    >`SELECT COUNT(*) AS count FROM "StylePreference" WHERE "userId" = ${users[0]}::uuid`;
    expect(Number(counts[0].count)).toBe(0);
    for (const body of [
      {},
      { ...selection, expectedVersion: undefined },
      { ...selection, expectedVersion: -1 },
      { ...selection, expectedVersion: 0.5 },
      { ...selection, expectedVersion: '0' },
      { ...selection, size: '3XL' },
      { ...selection, size: null },
      { ...selection, style: 'Unknown' },
      { ...selection, color: '#000000' },
      { ...selection, budget: 800000 },
      { ...selection, budget: '800000.0' },
      { ...selection, budget: '0' },
      { ...selection, userId: users[1] },
    ])
      await put().send(body).expect(400);
  });
  it('persists exact selections and isolates customers', async () => {
    const response = (await put().send(selection).expect(200)).body;
    expect(response).toEqual({
      size: 'L',
      style: 'Tối giản',
      color: 'Đen',
      budget: '800000',
      version: 1,
    });
    expect((await get().expect(200)).body).toEqual(response);
    expect((await get(1, '?userId=' + users[0]).expect(200)).body).toEqual(
      defaults,
    );
    expect(
      (
        await request(app.getHttpServer())
          .get('/api/v1/users/me/addresses')
          .auth(tokens[0], { type: 'bearer' })
          .expect(200)
      ).body,
    ).toEqual([]);
  });
  it('serializes first-save races and refuses stale replacements', async () => {
    const created = await Promise.all([
      put(1).send(selection),
      put(1).send({ ...selection, size: 'S' }),
    ]);
    expect(created.map((r) => r.status).sort()).toEqual([200, 409]);
    expect((await get(1)).body.version).toBe(1);
    const changed = await Promise.all(
      ['XL', 'XXL'].map((size) =>
        put().send({ ...selection, size, expectedVersion: 1 }),
      ),
    );
    expect(changed.map((r) => r.status).sort()).toEqual([200, 409]);
    const saved = changed.find((r) => r.status === 200)!.body;
    expect(saved.version).toBe(2);
    await put()
      .send({ ...selection, expectedVersion: 1 })
      .expect(409);
    expect((await get()).body).toEqual(saved);
  });
  it('supports subsequent saves including optional empty selections', async () => {
    const response = (
      await put()
        .send({
          size: 'XS',
          style: '',
          color: '',
          budget: '2500000',
          expectedVersion: 2,
        })
        .expect(200)
    ).body;
    expect(response).toEqual({
      size: 'XS',
      style: '',
      color: '',
      budget: '2500000',
      version: 3,
    });
    expect((await get()).body).toEqual(response);
    expect(Object.keys(response).sort()).toEqual(
      ['size', 'style', 'color', 'budget', 'version'].sort(),
    );
  });
});
