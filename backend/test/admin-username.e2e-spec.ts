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

describe('Admin username login', () => {
  let app: INestApplication, db: PrismaService;
  const ids: string[] = [];
  const origin = 'http://localhost:8080';
  beforeAll(async () => {
    const url = new URL(process.env.TEST_DATABASE_URL ?? 'http://invalid');
    if (!url.pathname.endsWith('_test')) throw new Error('Test DB required');
    process.env.DATABASE_URL = url.toString();
    process.env.CORS_ORIGINS = origin;
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
  async function account(admin = true) {
    const email = `username-${randomUUID()}@example.test`;
    const r = await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        email,
        password: 'Customer-policy-2026',
        name: 'Username fixture',
      })
      .expect(201);
    ids.push(r.body.user.id);
    await db.user.update({
      where: { id: r.body.user.id },
      data: {
        role: admin ? 'ADMIN' : 'CUSTOMER',
        passwordHash: await argon2.hash('123456789'),
      },
    });
    return r.body.user as { id: string; email: string; username: string };
  }
  const login = (browser = false) => {
    const r = request(app.getHttpServer()).post(
      '/api/v1/auth/' + (browser ? 'browser/admin/login' : 'admin/login'),
    );
    return browser ? r.set('Origin', origin).set('X-Wearly-Browser', '1') : r;
  };
  it('authenticates by username and the local nine-character password in both transports', async () => {
    const u = await account();
    for (const browser of [false, true]) {
      const r = await login(browser)
        .send({
          username: ` ${u.username?.toUpperCase()} `,
          password: '123456789',
        })
        .expect(201);
      expect(r.body.user.id).toBe(u.id);
      expect(r.body.user.username).toBe(u.username);
      expect(r.body.user.passwordHash).toBeUndefined();
      await request(app.getHttpServer())
        .get('/api/v1/admin/summary')
        .auth(r.body.accessToken, { type: 'bearer' })
        .expect(200);
      if (browser) expect(r.headers['set-cookie'][0]).toContain('HttpOnly');
    }
  });
  it('rejects email login, wrong passwords, disabled accounts and customer roles', async () => {
    const u = await account(),
      customer = await account(false);
    for (const browser of [false, true]) {
      await login(browser)
        .send({ email: u.email, password: '123456789' })
        .expect(400);
      await login(browser)
        .send({ username: u.username, password: 'wrong-password' })
        .expect(401);
      await login(browser)
        .send({ username: customer.username, password: '123456789' })
        .expect(403);
      await login(browser)
        .send({ username: u.email, password: '123456789' })
        .expect(400);
    }
    await db.user.update({ where: { id: u.id }, data: { active: false } });
    await login()
      .send({ username: u.username, password: '123456789' })
      .expect(401);
  });
  it('rejects staff accounts on customer login and renewal', async () => {
    const password = 'Independent-admin-password-2026';
    const u = await account();
    await db.user.update({
      where: { id: u.id },
      data: { passwordHash: await argon2.hash(password) },
    });
    for (const role of ['ADMIN', 'MANAGER', 'WAREHOUSE', 'SUPPORT'] as const) {
      await db.user.update({ where: { id: u.id }, data: { role } });
      for (const endpoint of ['login', 'browser/customer/login']) {
        const r = await request(app.getHttpServer())
          .post('/api/v1/auth/' + endpoint)
          .set('Origin', origin)
          .set('X-Wearly-Browser', '1')
          .send({ email: u.email, password })
          .expect(403);
        expect(r.body.error.code).toBe('CUSTOMER_ACCOUNT_REQUIRED');
      }
      await login().send({ username: u.username, password }).expect(201);
    }
    await db.user.update({ where: { id: u.id }, data: { role: 'CUSTOMER' } });
    const customer = await request(app.getHttpServer())
      .post('/api/v1/auth/browser/customer/login')
      .set('Origin', origin)
      .set('X-Wearly-Browser', '1')
      .send({ email: u.email, password })
      .expect(201);
    await db.user.update({ where: { id: u.id }, data: { role: 'ADMIN' } });
    await request(app.getHttpServer())
      .post('/api/v1/auth/browser/customer/refresh')
      .set('Origin', origin)
      .set('X-Wearly-Browser', '1')
      .set('Cookie', customer.headers['set-cookie'][0].split(';')[0])
      .expect(401);
  });

  it('preserves customer email login and registration password requirements', async () => {
    const email = `customer-${randomUUID()}@example.test`;
    await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({ email, name: 'Customer', password: '1234567' })
      .expect(400);
    const r = await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({ email, name: 'Customer', password: 'Customer-policy-2026' })
      .expect(201);
    ids.push(r.body.user.id);
    await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email, password: 'Customer-policy-2026' })
      .expect(201);
  });
});
