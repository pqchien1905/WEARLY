import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { ContentService } from '../src/modules/content/content.service';

describe('Store content publication with PostgreSQL', () => {
  let app: INestApplication, db: PrismaService, admin: string, customer: string;
  const users: string[] = [];
  const suffix = randomUUID();
  let contentId: string | undefined;
  const call = (method: 'get' | 'put' | 'post', path: string, token = admin) =>
    request(app.getHttpServer())
      [method]('/api/v1/' + path)
      .auth(token, { type: 'bearer' });
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
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    // Never overwrite a pre-existing singleton, even in the dedicated test DB.
    expect(await db.storeContent.count()).toBe(0);
    for (const role of ['ADMIN', 'CUSTOMER'] as const) {
      const r = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({
          name: role,
          email: `content-${role}-${suffix}@example.test`,
          password: 'Wearly-content-test-2026',
        })
        .expect(201);
      users.push(r.body.user.id);
      if (role === 'ADMIN') {
        admin = r.body.accessToken;
        await db.user.update({ where: { id: r.body.user.id }, data: { role } });
      } else customer = r.body.accessToken;
    }
  });
  afterAll(async () => {
    try {
      if (db) {
        await db.adminAuditEvent.deleteMany({
          where: { actorId: { in: users } },
        });
        if (contentId)
          await db.storeContent.delete({ where: { id: contentId } });
        await db.user.deleteMany({ where: { id: { in: users } } });
      }
    } finally {
      if (app) await app.close();
    }
  });
  it('exposes only published content publicly and protects drafts', async () => {
    const publicResult = await request(app.getHttpServer())
      .get('/api/v1/content')
      .expect(200);
    expect(publicResult.body).toEqual({ content: null });
    for (const [method, path] of [
      ['get', 'admin/content'],
      ['put', 'admin/content'],
      ['post', 'admin/content/publish'],
    ] as const) {
      await request(app.getHttpServer())
        [method]('/api/v1/' + path)
        .expect(401);
      await call(method, path, customer).expect(403);
    }
    const draft = await call('get', 'admin/content').expect(200);
    expect(draft.body).toMatchObject({
      id: null,
      version: 0,
      policy: '',
      published: null,
    });
  });
  it('validates drafts and allows only one concurrent first save without publishing', async () => {
    for (const body of [
      { banner: ' ', policy: 'Policy', expectedVersion: 0 },
      { banner: 'Title', policy: null, expectedVersion: 0 },
      { banner: 'x'.repeat(121), policy: 'Policy', expectedVersion: 0 },
      { banner: 'Title', policy: 'x'.repeat(5001), expectedVersion: 0 },
      { banner: 'Title', policy: 'Policy' },
      { banner: 'Title', policy: 'Policy', expectedVersion: -1 },
      {
        banner: 'Title',
        policy: 'Policy',
        expectedVersion: 0,
        published: true,
      },
      {
        banner: 'Title',
        policy: 'Policy',
        expectedVersion: 0,
        actorId: users[1],
      },
    ])
      await call('put', 'admin/content').send(body).expect(400);
    await call('post', 'admin/content/publish')
      .send({ expectedVersion: 0 })
      .expect(409);
    const body = {
      banner: '  Campaign <title>  ',
      policy: '  Private policy ' + suffix + '  ',
      expectedVersion: 0,
    };
    const writes = await Promise.all([
      call('put', 'admin/content').send(body),
      call('put', 'admin/content').send(body),
    ]);
    expect(writes.map((r) => r.status).sort()).toEqual([200, 409]);
    const saved = writes.find((r) => r.status === 200)!.body;
    contentId = saved.id;
    expect(saved).toMatchObject({
      banner: 'Campaign <title>',
      policy: 'Private policy ' + suffix,
      version: 1,
      published: null,
    });
    expect(
      (await request(app.getHttpServer()).get('/api/v1/content').expect(200))
        .body,
    ).toEqual({ content: null });
    expect(
      await db.adminAuditEvent.count({ where: { targetId: contentId } }),
    ).toBe(1);
  });
  it('rolls back publication when its audit insert fails', async () => {
    const before = await db.storeContent.findUniqueOrThrow({
      where: { id: contentId },
    });
    await expect(
      app.get(ContentService).publish('invalid-actor', { expectedVersion: 1 }),
    ).rejects.toThrow();
    expect(
      await db.storeContent.findUniqueOrThrow({ where: { id: contentId } }),
    ).toEqual(before);
    expect(
      (await request(app.getHttpServer()).get('/api/v1/content')).body,
    ).toEqual({ content: null });
  });
  it('publishes one exact saved revision and keeps subsequent drafts private', async () => {
    const writes = await Promise.all([
      call('post', 'admin/content/publish').send({ expectedVersion: 1 }),
      call('post', 'admin/content/publish').send({ expectedVersion: 1 }),
    ]);
    expect(writes.map((r) => r.status).sort()).toEqual([201, 409]);
    const published = writes.find((r) => r.status === 201)!.body;
    expect(published).toMatchObject({
      version: 2,
      published: {
        version: 2,
        banner: 'Campaign <title>',
        policy: 'Private policy ' + suffix,
      },
    });
    const publicResult = (
      await request(app.getHttpServer()).get('/api/v1/content').expect(200)
    ).body;
    expect(publicResult).toEqual({ content: published.published });
    await call('post', 'admin/content/publish')
      .send({ expectedVersion: 2 })
      .expect(409);
    await call('put', 'admin/content')
      .send({
        banner: 'Not published',
        policy: 'Draft only',
        expectedVersion: 2,
      })
      .expect(200);
    await call('put', 'admin/content')
      .send({ banner: 'Stale', policy: 'Stale', expectedVersion: 2 })
      .expect(409);
    await call('post', 'admin/content/publish')
      .send({ expectedVersion: 2 })
      .expect(409);
    expect(
      (await request(app.getHttpServer()).get('/api/v1/content').expect(200))
        .body,
    ).toEqual(publicResult);
    const draft = (await call('get', 'admin/content').expect(200)).body;
    expect(draft).toMatchObject({
      version: 3,
      banner: 'Not published',
      published: published.published,
    });
    const events = await db.adminAuditEvent.findMany({
      where: { targetId: contentId },
    });
    expect(events.map((e) => e.action).sort()).toEqual([
      'CONTENT_DRAFT_SAVED',
      'CONTENT_DRAFT_SAVED',
      'CONTENT_PUBLISHED',
    ]);
    expect(events.every((e) => e.actorId === users[0])).toBe(true);
  });
  it('publishes typed identity without leaking drafts and preserves it for legacy saves', async () => {
    const details = {
      name: '  Local Shop  ',
      tagline: 'Demo',
      email: '',
      phone: '',
      address: '',
      about: 'About draft',
      privacy: 'Privacy draft',
      terms: 'Terms draft',
    };
    const draft = (await call('get', 'admin/content').expect(200)).body;
    expect(draft.details).toMatchObject({
      name: 'WEARLY',
      email: '',
      phone: '',
      address: '',
    });
    for (const invalid of [
      null,
      [],
      {},
      { ...details, name: ' ' },
      { ...details, email: 'not-email' },
      { ...details, name: 'x'.repeat(81) },
      { ...details, privacy: 'x'.repeat(5001) },
      { ...details, unknown: true },
    ]) {
      await call('put', 'admin/content')
        .send({
          banner: 'Identity',
          policy: 'Local shipping',
          expectedVersion: draft.version,
          details: invalid,
        })
        .expect(400);
    }
    const saved = (
      await call('put', 'admin/content')
        .send({
          banner: 'Identity',
          policy: 'Local shipping',
          expectedVersion: draft.version,
          details,
        })
        .expect(200)
    ).body;
    expect(saved.details.name).toBe('Local Shop');
    expect(
      (await request(app.getHttpServer()).get('/api/v1/content')).body.content
        .details.name,
    ).toBe('WEARLY');
    const legacy = (
      await call('put', 'admin/content')
        .send({
          banner: 'Legacy',
          policy: 'Local shipping',
          expectedVersion: saved.version,
        })
        .expect(200)
    ).body;
    expect(legacy.details).toEqual(saved.details);
    await call('post', 'admin/content/publish')
      .send({ expectedVersion: legacy.version })
      .expect(201);
    const published = (
      await request(app.getHttpServer()).get('/api/v1/content').expect(200)
    ).body.content;
    expect(published.details).toEqual(saved.details);
    await call('put', 'admin/content')
      .send({
        banner: 'Later',
        policy: 'Later',
        expectedVersion: legacy.version + 1,
        details: { ...details, name: 'Unpublished' },
      })
      .expect(200);
    expect(
      (await request(app.getHttpServer()).get('/api/v1/content')).body.content,
    ).toEqual(published);
  });
});
