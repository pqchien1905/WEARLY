import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ThrottlerGuard } from '@nestjs/throttler';
import request from 'supertest';
import { createHash, randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { validateEnv } from '../src/config/env.validation';

describe('Persistent browser sessions with real PostgreSQL', () => {
  let app: INestApplication, db: PrismaService, config: ConfigService;
  const ids: string[] = [];
  const password = 'Browser-fixture-only-2026';
  const origin = 'http://127.0.0.1:4183';
  const path = (scope = 'customer') => '/api/v1/auth/browser/' + scope;
  const call = (action: string, scope = 'customer') =>
    request(app.getHttpServer())
      .post(path(scope) + '/' + action)
      .set('Origin', origin)
      .set('X-Wearly-Browser', '1');
  const cookie = (r: request.Response) =>
    (r.headers['set-cookie'] as unknown as string[])[0].split(';')[0];
  async function register() {
    const email = `browser-${randomUUID()}@example.test`;
    const r = await call('register')
      .send({ email, password, name: 'Browser fixture' })
      .expect(201);
    ids.push(r.body.user.id);
    return { r, email, id: r.body.user.id as string, cookie: cookie(r) };
  }
  beforeAll(async () => {
    if (
      !process.env.TEST_DATABASE_URL ||
      !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test')
    )
      throw new Error('Dedicated test DB required');
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
    process.env.NODE_ENV = 'test';
    process.env.CORS_ORIGINS =
      origin + ',https://shop.example.test,http://not-local.example.test';
    process.env.PASSWORD_RECOVERY_ENABLED = 'false';
    process.env.LOCAL_MAIL_ENABLED = 'false';
    process.env.VNPAY_ENABLED = 'false';
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ConfigService)
      .useValue(new ConfigService(validateEnv(process.env)))
      .overrideGuard(ThrottlerGuard)
      .useValue({ canActivate: () => true })
      .compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    config = app.get(ConfigService);
  });
  afterAll(async () => {
    if (db) await db.user.deleteMany({ where: { id: { in: ids } } });
    if (app) await app.close();
  });

  it('stores only a hash and issues private scoped cookies without a JSON refresh token', async () => {
    const c = await register();
    expect(Object.keys(c.r.body).sort()).toEqual([
      'accessToken',
      'expiresIn',
      'user',
    ]);
    const header = (c.r.headers['set-cookie'] as unknown as string[])[0];
    expect(header).toContain('HttpOnly');
    expect(header).toContain('SameSite=Strict');
    expect(header).toContain('Path=' + path());
    expect(header).toContain('Max-Age=604800');
    expect(header).not.toContain('Domain=');
    expect(header).not.toContain('Secure');
    const raw = c.cookie.split('=')[1];
    expect(raw).toMatch(/^[A-Za-z0-9_-]{43}$/);
    const row = await db.refreshToken.findFirstOrThrow({
      where: { userId: c.id },
    });
    expect(row.tokenHash).toBe(createHash('sha256').update(raw).digest('hex'));
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .auth(c.r.body.accessToken, { type: 'bearer' })
      .expect(200);
    await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: raw })
      .expect(401);
  });

  it('requires exact origin and custom header on every cookie endpoint, including login/logout', async () => {
    for (const scope of ['customer', 'admin']) {
      for (const action of [
        'login',
        'refresh',
        'logout',
        ...(scope === 'customer' ? ['register'] : []),
      ]) {
        for (const invalidOrigin of [
          undefined,
          'null',
          'https://evil.example.test',
          origin + '.evil.test',
          'http://not-local.example.test',
        ]) {
          const r = request(app.getHttpServer())
            .post(path(scope) + '/' + action)
            .set('X-Wearly-Browser', '1');
          if (invalidOrigin) r.set('Origin', invalidOrigin);
          await r.send({}).expect(403);
        }
        await request(app.getHttpServer())
          .post(path(scope) + '/' + action)
          .set('Origin', origin)
          .send({})
          .expect(403);
        await call(action, scope)
          .set('Host', 'not-local.example.test')
          .send({})
          .expect(403);
      }
    }
    const preflight = await request(app.getHttpServer())
      .options(path() + '/refresh')
      .set('Origin', origin)
      .set('Access-Control-Request-Method', 'POST')
      .set('Access-Control-Request-Headers', 'X-Wearly-Browser,Content-Type')
      .expect(204);
    expect(preflight.headers['access-control-allow-origin']).toBe(origin);
    expect(preflight.headers['access-control-allow-credentials']).toBe('true');
    expect(
      preflight.headers['access-control-allow-headers'].toLowerCase(),
    ).toContain('x-wearly-browser');
    config.set('NODE_ENV', 'production');
    try {
      await call('refresh').send({}).expect(403);
    } finally {
      config.set('NODE_ENV', 'test');
    }
  });

  it('rejects ambiguous cookies and keeps customer/staff sessions separate', async () => {
    const c = await register();
    await db.user.update({ where: { id: c.id }, data: { role: 'ADMIN' } });
    const a = await call('login', 'admin')
      .send({ email: c.email, password })
      .expect(201);
    const staffCookie = cookie(a);
    expect(staffCookie).toMatch(/^wearly_admin_session=/);
    expect((a.headers['set-cookie'] as unknown as string[])[0]).toContain(
      'Max-Age=28800',
    );
    await call('refresh', 'admin').set('Cookie', c.cookie).expect(401);
    await call('refresh').set('Cookie', staffCookie).expect(401);
    await call('refresh')
      .set('Cookie', c.cookie + '; ' + c.cookie)
      .expect(401);
    await call('refresh')
      .set('Cookie', 'wearly_customer_session=%invalid')
      .expect(401);
    await call('refresh')
      .set('Cookie', c.cookie.replace('wearly_customer', 'wearly_admin'))
      .expect(401);
    await call('logout').set('Cookie', c.cookie).expect(201);
    await call('refresh').set('Cookie', c.cookie).expect(401);
    await call('refresh', 'admin').set('Cookie', staffCookie).expect(201);
  });

  it('renews concurrently with fixed absolute expiry and no refresh Set-Cookie', async () => {
    const c = await register();
    const before = await db.refreshToken.findFirstOrThrow({
      where: { userId: c.id },
    });
    const results = await Promise.all(
      Array.from({ length: 8 }, () => call('refresh').set('Cookie', c.cookie)),
    );
    for (const result of results) {
      expect(result.status).toBe(201);
      expect(result.body.user.id).toBe(c.id);
      expect(result.body.refreshToken).toBeUndefined();
      expect(result.headers['set-cookie']).toBeUndefined();
    }
    const after = await db.refreshToken.findFirstOrThrow({
      where: { userId: c.id },
    });
    expect(after.expiresAt).toEqual(before.expiresAt);
    expect(after.tokenHash).toBe(before.tokenHash);
    expect(await db.refreshToken.count({ where: { userId: c.id } })).toBe(1);
    await db.refreshToken.update({
      where: { id: before.id },
      data: { expiresAt: new Date(0) },
    });
    const expired = await call('refresh').set('Cookie', c.cookie).expect(401);
    expect(expired.headers['set-cookie']).toBeUndefined();
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .auth(c.r.body.accessToken, { type: 'bearer' })
      .expect(401);
  });

  it('new login revokes the presented session and logout immediately revokes access', async () => {
    const c = await register(),
      other = await register();
    await call('login')
      .set('Cookie', c.cookie)
      .send({ email: other.email, password: 'wrong-password' })
      .expect(401);
    await call('refresh').set('Cookie', c.cookie).expect(201);
    const login = await call('login')
      .set('Cookie', c.cookie)
      .send({ email: other.email, password })
      .expect(201);
    await call('refresh').set('Cookie', c.cookie).expect(401);
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .auth(c.r.body.accessToken, { type: 'bearer' })
      .expect(401);
    const fresh = cookie(login);
    const logout = await call('logout').set('Cookie', fresh).expect(201);
    expect(logout.body).toEqual({ loggedOut: true });
    expect((logout.headers['set-cookie'] as unknown as string[])[0]).toContain(
      'Expires=Thu, 01 Jan 1970',
    );
    await call('refresh').set('Cookie', fresh).expect(401);
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .auth(login.body.accessToken, { type: 'bearer' })
      .expect(401);
    await call('logout').set('Cookie', fresh).expect(201);
  });

  it('checks current staff role, account activation and revoked session on renewal', async () => {
    const c = await register();
    await call('login', 'admin').send({ email: c.email, password }).expect(403);
    await db.user.update({ where: { id: c.id }, data: { role: 'SUPPORT' } });
    const a = await call('login', 'admin')
      .send({ email: c.email, password })
      .expect(201);
    await db.user.update({ where: { id: c.id }, data: { role: 'CUSTOMER' } });
    await call('refresh', 'admin').set('Cookie', cookie(a)).expect(401);
    await db.user.update({ where: { id: c.id }, data: { active: false } });
    await call('refresh').set('Cookie', c.cookie).expect(401);
    await db.user.update({ where: { id: c.id }, data: { active: true } });
    await db.refreshToken.updateMany({
      where: { userId: c.id },
      data: { revokedAt: new Date() },
    });
    await call('refresh').set('Cookie', c.cookie).expect(401);
  });

  it('retains native rotating refresh behavior independently of browser cookies', async () => {
    const c = await register();
    const login = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email: c.email, password })
      .expect(201);
    expect(login.headers['set-cookie']).toBeUndefined();
    const rotated = await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: login.body.refreshToken })
      .expect(201);
    expect(rotated.body.refreshToken).not.toBe(login.body.refreshToken);
    await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: login.body.refreshToken })
      .expect(401);
    await call('refresh').set('Cookie', c.cookie).expect(201);
  });

  it('staff administration revokes both browser scopes atomically with role changes', async () => {
    const owner = await register(),
      target = await register();
    await db.user.update({ where: { id: owner.id }, data: { role: 'ADMIN' } });
    await db.user.update({
      where: { id: target.id },
      data: { role: 'SUPPORT' },
    });
    const staff = await call('login', 'admin')
      .send({ email: target.email, password })
      .expect(201);
    await request(app.getHttpServer())
      .patch('/api/v1/admin/staff/' + target.id)
      .auth(owner.r.body.accessToken, { type: 'bearer' })
      .send({ role: 'CUSTOMER', active: true, expectedVersion: 0 })
      .expect(200);
    await call('refresh', 'admin').set('Cookie', cookie(staff)).expect(401);
    await call('refresh').set('Cookie', target.cookie).expect(401);
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .auth(staff.body.accessToken, { type: 'bearer' })
      .expect(401);
  });
});
