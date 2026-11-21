import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import * as argon2 from 'argon2';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Administrative customer password reset', () => {
  let app: INestApplication, db: PrismaService, origin: string;
  const ids: string[] = [];
  const actors: Record<string, { id: string; token: string }> = {};
  const originalPassword = 'Customer-original-2026';
  const newPassword = 'Customer-replaced-2026';

  async function customer(active = true) {
    const user = await db.user.create({
      data: {
        name: 'Password reset fixture',
        email: `password-${randomUUID()}@example.test`,
        passwordHash: await argon2.hash(originalPassword),
        active,
      },
    });
    ids.push(user.id);
    return user;
  }
  const reset = (id: string, actor = 'ADMIN') =>
    request(app.getHttpServer())
      .post(`/api/v1/admin/users/${id}/reset-password`)
      .auth(actors[actor].token, { type: 'bearer' });
  const login = (email: string, password: string) =>
    request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email, password });
  const me = (token: string) =>
    request(app.getHttpServer())
      .get('/api/v1/users/me')
      .auth(token, { type: 'bearer' });

  beforeAll(async () => {
    if (!new URL(process.env.TEST_DATABASE_URL!).pathname.endsWith('_test'))
      throw Error('Isolated test database required');
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    origin = app
      .get(ConfigService)
      .getOrThrow<string>('CORS_ORIGINS')
      .split(',')[0]
      .trim();
    for (const role of ['ADMIN', 'MANAGER', 'SUPPORT', 'CUSTOMER'] as const) {
      const user = await customer();
      const username = `reset-${randomUUID()}`;
      await db.user.update({
        where: { id: user.id },
        data: { role, username },
      });
      const response =
        role === 'CUSTOMER'
          ? await login(user.email, originalPassword).expect(201)
          : await request(app.getHttpServer())
              .post('/api/v1/auth/admin/login')
              .send({ username, password: originalPassword })
              .expect(201);
      actors[role] = { id: user.id, token: response.body.accessToken };
    }
  });
  afterAll(async () => {
    try {
      if (db) {
        await db.adminAuditEvent.deleteMany({
          where: { targetId: { in: ids } },
        });
        await db.user.deleteMany({ where: { id: { in: ids } } });
      }
    } finally {
      await app?.close();
    }
  });

  it('requires permission, a customer target, a version and a valid password', async () => {
    const user = await customer();
    const body = {
      expectedUpdatedAt: user.updatedAt.toISOString(),
      password: newPassword,
    };
    await request(app.getHttpServer())
      .post(`/api/v1/admin/users/${user.id}/reset-password`)
      .send(body)
      .expect(401);
    for (const role of ['CUSTOMER', 'SUPPORT'])
      await reset(user.id, role).send(body).expect(403);
    for (const id of [actors.ADMIN.id, actors.MANAGER.id, randomUUID()])
      await reset(id).send(body).expect(404);
    for (const invalid of [
      { password: newPassword },
      { expectedUpdatedAt: body.expectedUpdatedAt },
      { ...body, expectedUpdatedAt: 'invalid' },
      { ...body, password: null },
      { ...body, password: 'short' },
      { ...body, password: 'x'.repeat(129) },
      { ...body, role: 'ADMIN' },
      { ...body, active: true },
    ])
      await reset(user.id).send(invalid).expect(400);
    expect(
      (await db.user.findUniqueOrThrow({ where: { id: user.id } }))
        .passwordHash,
    ).toBe(user.passwordHash);
    expect(
      await db.adminAuditEvent.count({ where: { targetId: user.id } }),
    ).toBe(0);
    await db.user.update({
      where: { id: user.id },
      data: { deletedAt: new Date(), active: false },
    });
    await reset(user.id).send(body).expect(404);
  });

  it('lets a manager replace the password, revoke every session and recovery grant, and record a private audit', async () => {
    const user = await customer();
    const session = await login(user.email, originalPassword).expect(201);
    const browser = await request(app.getHttpServer())
      .post('/api/v1/auth/browser/customer/login')
      .set('Origin', origin)
      .set('X-Wearly-Browser', '1')
      .send({ email: user.email, password: originalPassword })
      .expect(201);
    const cookie = (
      browser.headers['set-cookie'] as unknown as string[]
    )[0].split(';')[0];
    await db.passwordResetToken.create({
      data: {
        userId: user.id,
        tokenHash: randomUUID(),
        expiresAt: new Date(Date.now() + 60000),
      },
    });
    await db.passwordResetCode.create({
      data: {
        userId: user.id,
        codeHash: randomUUID(),
        requestedAt: new Date(),
        expiresAt: new Date(Date.now() + 60000),
      },
    });
    const body = {
      password: newPassword,
      expectedUpdatedAt: user.updatedAt.toISOString(),
    };
    const response = await reset(user.id, 'MANAGER').send(body).expect(201);
    expect(response.body).toMatchObject({
      id: user.id,
      email: user.email,
      name: user.name,
      active: true,
      role: 'CUSTOMER',
    });
    for (const key of [
      'password',
      'passwordHash',
      'accessToken',
      'refreshToken',
    ])
      expect(response.body[key]).toBeUndefined();
    const stored = await db.user.findUniqueOrThrow({ where: { id: user.id } });
    expect(stored.updatedAt.getTime()).toBeGreaterThan(
      user.updatedAt.getTime(),
    );
    expect(stored.passwordChangedAt).toBeInstanceOf(Date);
    expect(await argon2.verify(stored.passwordHash, newPassword)).toBe(true);
    expect(await argon2.verify(stored.passwordHash, originalPassword)).toBe(
      false,
    );
    await me(session.body.accessToken).expect(401);
    await me(browser.body.accessToken).expect(401);
    await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: session.body.refreshToken })
      .expect(401);
    await request(app.getHttpServer())
      .post('/api/v1/auth/browser/customer/refresh')
      .set('Origin', origin)
      .set('X-Wearly-Browser', '1')
      .set('Cookie', cookie)
      .send({})
      .expect(401);
    expect(
      await db.passwordResetToken.count({
        where: { userId: user.id, consumedAt: null },
      }),
    ).toBe(0);
    expect(
      await db.passwordResetCode.count({
        where: { userId: user.id, consumedAt: null },
      }),
    ).toBe(0);
    await login(user.email, originalPassword).expect(401);
    const next = await login(user.email, newPassword).expect(201);
    await reset(user.id)
      .send({ ...body, password: 'Stale-attempt-2026' })
      .expect(409);
    await me(next.body.accessToken).expect(200);
    const events = await db.adminAuditEvent.findMany({
      where: { targetId: user.id },
    });
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({
      actorId: actors.MANAGER.id,
      action: 'STAFF_UPDATED',
      details: {
        before: { role: 'CUSTOMER', active: true },
        after: { role: 'CUSTOMER', active: true, passwordChanged: true },
      },
    });
    for (const secret of [
      originalPassword,
      newPassword,
      stored.passwordHash,
      user.email,
    ])
      expect(JSON.stringify(events)).not.toContain(secret);
  });

  it('keeps a locked account locked after an administrator resets its password', async () => {
    const user = await customer(false);
    await reset(user.id)
      .send({
        password: newPassword,
        expectedUpdatedAt: user.updatedAt.toISOString(),
      })
      .expect(201);
    const stored = await db.user.findUniqueOrThrow({ where: { id: user.id } });
    expect(stored.active).toBe(false);
    expect(stored.role).toBe('CUSTOMER');
    expect(await argon2.verify(stored.passwordHash, newPassword)).toBe(true);
    await login(user.email, newPassword).expect(401);
  });

  it('allows only one of two competing password replacements', async () => {
    const user = await customer();
    const passwords = ['Concurrent-first-2026', 'Concurrent-second-2026'];
    const results = await Promise.all(
      passwords.map((password) =>
        reset(user.id).send({
          password,
          expectedUpdatedAt: user.updatedAt.toISOString(),
        }),
      ),
    );
    expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
    const stored = await db.user.findUniqueOrThrow({ where: { id: user.id } });
    for (let i = 0; i < results.length; i++)
      expect(await argon2.verify(stored.passwordHash, passwords[i])).toBe(
        results[i].status === 201,
      );
    expect(
      await db.adminAuditEvent.count({ where: { targetId: user.id } }),
    ).toBe(1);
  });
});
