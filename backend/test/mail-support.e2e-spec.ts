import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import * as audit from '../src/modules/admin/audit';

describe('Persistent guest support', () => {
  let app: INestApplication, db: PrismaService, admin: string, buyer: string;
  const call = (method: 'get' | 'post' | 'patch', path: string, token = '') =>
    request(app.getHttpServer())
      [method]('/api/v1/' + path)
      .auth(token, { type: 'bearer' });
  const draft = () => ({
    requestKey: randomUUID(),
    name: 'Local customer',
    email: randomUUID() + '@example.test',
    message: 'Please help with choosing a size.',
  });
  beforeAll(async () => {
    if (
      !new URL(
        process.env.TEST_DATABASE_URL ?? 'http://invalid',
      ).pathname.endsWith('_test')
    )
      throw Error('Dedicated test database required');
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    process.env.NODE_ENV = 'test';
    process.env.JWT_ACCESS_SECRET = 'test-access-'.repeat(5);
    process.env.JWT_REFRESH_SECRET = 'test-refresh-'.repeat(5);
    jest.spyOn(ThrottlerGuard.prototype, 'canActivate').mockResolvedValue(true);
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    for (let i = 0; i < 2; i++) {
      const r = await call('post', 'auth/register')
        .send({
          name: 'Support fixture',
          email: randomUUID() + '@example.test',
          password: 'Support-password-2026',
        })
        .expect(201);
      if (i === 0) {
        admin = r.body.accessToken;
        await db.user.update({
          where: { id: r.body.user.id },
          data: { role: 'ADMIN' },
        });
      } else buyer = r.body.accessToken;
    }
  });
  afterAll(async () => {
    jest.restoreAllMocks();
    if (app) await app.close();
  });
  it('stores a guest request, returns only a receipt, replays it, and protects its contents', async () => {
    const data = draft(),
      first = await call('post', 'support').send(data).expect(201);
    expect(Object.keys(first.body).sort()).toEqual(['createdAt', 'id']);
    expect((await call('post', 'support').send(data).expect(201)).body).toEqual(
      first.body,
    );
    await call('post', 'support')
      .send({ ...data, message: 'Different private message' })
      .expect(409);
    await call('get', 'support/' + first.body.id).expect(404);
    await call('get', 'admin/support/' + first.body.id).expect(401);
    await call('get', 'admin/support/' + first.body.id, buyer).expect(403);
    const detail = await call(
      'get',
      'admin/support/' + first.body.id,
      admin,
    ).expect(200);
    expect(detail.body).toMatchObject({
      name: data.name,
      email: data.email,
      message: data.message,
      status: 'OPEN',
      version: 0,
      replies: [],
    });
  });
  it('validates contact bounds and normalizes email', async () => {
    const data = draft();
    for (const patch of [
      { name: 'x' },
      { email: 'bad' },
      { message: 'short' },
      { message: 'a'.repeat(3001) },
      { requestKey: 'bad' },
    ])
      await call('post', 'support')
        .send({ ...data, ...patch })
        .expect(400);
    const r = await call('post', 'support')
      .send({ ...data, email: '  ' + data.email.toUpperCase() + '  ' })
      .expect(201);
    expect(
      (await call('get', 'admin/support/' + r.body.id, admin).expect(200)).body
        .email,
    ).toBe(data.email);
  });
  it('replies once, checks stale versions, closes and explicitly reopens', async () => {
    const ticket = (await call('post', 'support').send(draft()).expect(201))
      .body;
    const path = 'admin/support/' + ticket.id,
      reply = {
        requestKey: randomUUID(),
        expectedVersion: 0,
        message: 'We can help you choose the correct size.',
      };
    const results = await Promise.all([
      call('post', path + '/replies', admin).send(reply),
      call('post', path + '/replies', admin).send(reply),
    ]);
    expect(results.map((r) => r.status)).toEqual([201, 201]);
    expect(results[0].body).toEqual(results[1].body);
    await call('post', path + '/replies', admin)
      .send({ ...reply, message: 'Changed message' })
      .expect(409);
    await call('post', path + '/replies', admin)
      .send({ ...reply, requestKey: randomUUID() })
      .expect(409);
    let detail = (await call('get', path, admin).expect(200)).body;
    expect(detail).toMatchObject({ status: 'ANSWERED', version: 1 });
    expect(detail.replies).toHaveLength(1);
    expect(detail.replies[0].mail.status).toBe('PENDING');
    await call('patch', path, admin)
      .send({ expectedVersion: 1, status: 'CLOSED' })
      .expect(200);
    await call('post', path + '/replies', admin)
      .send({ ...reply, requestKey: randomUUID(), expectedVersion: 2 })
      .expect(409);
    await call('patch', path, admin)
      .send({ expectedVersion: 2, status: 'OPEN' })
      .expect(200);
    detail = (await call('get', path, admin).expect(200)).body;
    expect(detail).toMatchObject({ version: 3, status: 'OPEN' });
  });
  it('rolls back reply and mail together when auditing fails', async () => {
    const ticket = (await call('post', 'support').send(draft()).expect(201))
      .body;
    const record = jest
      .spyOn(audit, 'recordAdminActivity')
      .mockRejectedValueOnce(Error('fixture audit unavailable'));
    try {
      await call('post', 'admin/support/' + ticket.id + '/replies', admin)
        .send({
          requestKey: randomUUID(),
          expectedVersion: 0,
          message: 'A reply which must be rolled back.',
        })
        .expect(500);
    } finally {
      record.mockRestore();
    }
    const detail = (
      await call('get', 'admin/support/' + ticket.id, admin).expect(200)
    ).body;
    expect(detail).toMatchObject({ version: 0, status: 'OPEN', replies: [] });
    expect(await db.mailOutbox.count({ where: { supportId: ticket.id } })).toBe(
      0,
    );
  });
  it('limits public contact submissions to five per minute', async () => {
    jest.spyOn(ThrottlerGuard.prototype, 'canActivate').mockRestore();
    for (let i = 0; i < 5; i++)
      await call('post', 'support').send(draft()).expect(201);
    await call('post', 'support').send(draft()).expect(429);
  });
});
