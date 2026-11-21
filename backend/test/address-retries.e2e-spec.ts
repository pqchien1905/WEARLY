import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Address create retries with PostgreSQL', () => {
  let app: INestApplication, db: PrismaService;
  const users: string[] = [],
    tokens: string[] = [];
  const path = '/api/v1/users/me/addresses';
  const body = {
    recipient: 'Khách kiểm thử',
    phone: '0901234567',
    address: '12 Nguyễn Huệ, TP.HCM',
    label: 'Nhà',
    isDefault: true,
  };
  const post = (key: string, data = body, user = 0) =>
    request(app.getHttpServer())
      .post(path)
      .auth(tokens[user], { type: 'bearer' })
      .set('Idempotency-Key', key)
      .send(data);
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
    for (let i = 0; i < 3; i++) {
      const r = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({
          name: 'Address retry fixture',
          email: `address-retry-${randomUUID()}@example.test`,
          password: 'Address-test-password-2026',
        })
        .expect(201);
      users.push(r.body.user.id);
      tokens.push(r.body.accessToken);
    }
  });
  afterAll(async () => {
    // Exact synthetic users created above, never development/user data.
    if (db) await db.user.deleteMany({ where: { id: { in: users } } });
    await app?.close();
  });
  it('concurrent replay creates one address and changed payload is rejected', async () => {
    const key = randomUUID();
    const before = await db.address.count({ where: { userId: users[0] } });
    const replies = await Promise.all([
      post(key).expect(201),
      post(key).expect(201),
    ]);
    expect(replies[0].body.id).toBe(replies[1].body.id);
    expect(await db.address.count({ where: { userId: users[0] } })).toBe(
      before + 1,
    );
    expect(replies[0].body.requestHash).toBeUndefined();
    await post(key, { ...body, recipient: 'Changed' }).expect(409);
    const other = await post(key, body, 1).expect(201);
    expect(other.body.id).not.toBe(replies[0].body.id);
  });
  it('replay preserves later edits/default and cannot resurrect deleted address', async () => {
    const key = randomUUID(),
      first = await post(key).expect(201);
    await request(app.getHttpServer())
      .patch(`${path}/${first.body.id}`)
      .auth(tokens[0], { type: 'bearer' })
      .send({ recipient: 'Updated recipient' })
      .expect(200);
    const second = await post(randomUUID()).expect(201);
    const replay = await post(key).expect(201);
    expect(replay.body.recipient).toBe('Updated recipient');
    expect(replay.body.isDefault).toBe(false);
    expect(
      (await db.address.findUniqueOrThrow({ where: { id: second.body.id } }))
        .isDefault,
    ).toBe(true);
    await request(app.getHttpServer())
      .delete(`${path}/${first.body.id}`)
      .auth(tokens[0], { type: 'bearer' })
      .expect(200);
    await post(key).expect(410);
    expect(
      await db.address.findUnique({ where: { id: first.body.id } }),
    ).toBeNull();
  });
  it('validates optional keys, rejects unauthenticated requests and retains legacy POST', async () => {
    for (const key of ['short', 'x'.repeat(129), 'contains invalid spaces'])
      await post(key).expect(400);
    await request(app.getHttpServer())
      .post(path)
      .set('Idempotency-Key', randomUUID())
      .send(body)
      .expect(401);
    await request(app.getHttpServer())
      .post(path)
      .auth(tokens[0], { type: 'bearer' })
      .send(body)
      .expect(201);
  });
  it('assigns the first default atomically without relying on the client', async () => {
    const results = await Promise.all([
      post(randomUUID(), { ...body, isDefault: false }, 2).expect(201),
      post(
        randomUUID(),
        { ...body, isDefault: false, label: 'Office' },
        2,
      ).expect(201),
    ]);
    expect(results[0].body.id).not.toBe(results[1].body.id);
    const list = () => db.address.findMany({ where: { userId: users[2] } });
    expect((await list()).filter((a) => a.isDefault)).toHaveLength(1);
    const current = (await list()).find((a) => a.isDefault)!;
    const remaining = (await list()).find((a) => !a.isDefault)!;
    await request(app.getHttpServer())
      .delete(`${path}/${current.id}`)
      .auth(tokens[2], { type: 'bearer' })
      .expect(200);
    expect(await list()).toMatchObject([{ id: remaining.id, isDefault: true }]);
    await request(app.getHttpServer())
      .delete(`${path}/${remaining.id}`)
      .auth(tokens[2], { type: 'bearer' })
      .expect(200);
    expect(await list()).toHaveLength(0);
    const next = await post(
      randomUUID(),
      { ...body, isDefault: false },
      2,
    ).expect(201);
    expect(next.body.isDefault).toBe(true);
  });
  it('serializes deleting the default with selecting another and isolates ownership', async () => {
    const original = await db.address.findFirstOrThrow({
      where: { userId: users[2], isDefault: true },
    });
    const second = await post(
      randomUUID(),
      { ...body, isDefault: false, label: 'Second' },
      2,
    ).expect(201);
    await post(
      randomUUID(),
      { ...body, isDefault: false, label: 'Third' },
      2,
    ).expect(201);
    await Promise.all([
      request(app.getHttpServer())
        .delete(`${path}/${original.id}`)
        .auth(tokens[2], { type: 'bearer' })
        .expect(200),
      request(app.getHttpServer())
        .patch(`${path}/${second.body.id}`)
        .auth(tokens[2], { type: 'bearer' })
        .send({ isDefault: true })
        .expect(200),
    ]);
    expect(
      await db.address.findMany({
        where: { userId: users[2], isDefault: true },
      }),
    ).toMatchObject([{ id: second.body.id }]);
    await request(app.getHttpServer())
      .delete(`${path}/${second.body.id}`)
      .auth(tokens[0], { type: 'bearer' })
      .expect(404);
    expect(
      (await db.address.findUniqueOrThrow({ where: { id: second.body.id } }))
        .isDefault,
    ).toBe(true);
  });
});
