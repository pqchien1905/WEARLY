import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import { randomUUID } from 'node:crypto';
import * as argon2 from 'argon2';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Signed-in password change', () => {
  let app: INestApplication, db: PrismaService;
  const ids: string[] = [];
  const original = 'Original-password-2026';
  const next = 'Replaced-password-2026';
  beforeAll(async () => {
    const url = new URL(process.env.TEST_DATABASE_URL ?? 'http://invalid');
    if (!url.pathname.endsWith('_test')) throw new Error('Test DB required');
    process.env.DATABASE_URL = url.toString();
    const mod = await Test.createTestingModule({ imports: [AppModule] })
      .overrideGuard(ThrottlerGuard)
      .useValue({ canActivate: () => true })
      .compile();
    app = mod.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
  });
  afterAll(async () => {
    if (db) await db.user.deleteMany({ where: { id: { in: ids } } });
    if (app) await app.close();
  });
  const post = (path: string, token?: string) => {
    const r = request(app.getHttpServer()).post('/api/v1/' + path);
    return token ? r.set('Authorization', 'Bearer ' + token) : r;
  };
  async function customer() {
    const email = `change-${randomUUID()}@example.test`;
    const r = await post('auth/register')
      .send({ email, password: original, name: 'Change fixture' })
      .expect(201);
    ids.push(r.body.user.id);
    return { email, id: r.body.user.id as string };
  }
  const login = async (email: string, password: string) =>
    (await post('auth/login').send({ email, password }).expect(201)).body as {
      accessToken: string;
      refreshToken: string;
    };

  it('requires authentication', async () => {
    await post('auth/change-password')
      .send({ currentPassword: original, newPassword: next })
      .expect(401);
  });

  it('rejects a wrong current password, short or unchanged passwords', async () => {
    const u = await customer();
    const s = await login(u.email, original);
    const wrong = await post('auth/change-password', s.accessToken)
      .send({ currentPassword: 'Not-the-password-1', newPassword: next })
      .expect(400);
    expect(wrong.body.error.code).toBe('CURRENT_PASSWORD_INVALID');
    await post('auth/change-password', s.accessToken)
      .send({ currentPassword: original, newPassword: 'short' })
      .expect(400);
    const same = await post('auth/change-password', s.accessToken)
      .send({ currentPassword: original, newPassword: original })
      .expect(400);
    expect(same.body.error.code).toBe('PASSWORD_UNCHANGED');
    await login(u.email, original);
  });

  it('changes the password, keeps the current session and revokes other devices', async () => {
    const u = await customer();
    const current = await login(u.email, original);
    const other = await login(u.email, original);
    await post('auth/change-password', current.accessToken)
      .send({ currentPassword: original, newPassword: next })
      .expect(200, { changed: true });
    await post('auth/login')
      .send({ email: u.email, password: original })
      .expect(401);
    await login(u.email, next);
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .set('Authorization', 'Bearer ' + current.accessToken)
      .expect(200);
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .set('Authorization', 'Bearer ' + other.accessToken)
      .expect(401);
    await post('auth/refresh')
      .send({ refreshToken: other.refreshToken })
      .expect(401);
    const refreshed = await post('auth/refresh')
      .send({ refreshToken: current.refreshToken })
      .expect(201);
    expect(refreshed.body.accessToken).toBeTruthy();
    const user = await db.user.findUniqueOrThrow({ where: { id: u.id } });
    expect(user.passwordChangedAt).toBeTruthy();
    expect(await argon2.verify(user.passwordHash, next)).toBe(true);
  });

  it('lets staff change their own password for the admin login', async () => {
    const u = await customer();
    await db.user.update({ where: { id: u.id }, data: { role: 'WAREHOUSE' } });
    const { username } = await db.user.findUniqueOrThrow({
      where: { id: u.id },
    });
    const s = (
      await post('auth/admin/login')
        .send({ username, password: original })
        .expect(201)
    ).body as { accessToken: string };
    await post('auth/change-password', s.accessToken)
      .send({ currentPassword: original, newPassword: next })
      .expect(200);
    await post('auth/admin/login')
      .send({ username, password: original })
      .expect(401);
    await post('auth/admin/login')
      .send({ username, password: next })
      .expect(201);
  });
});
