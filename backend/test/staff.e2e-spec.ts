import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { Client } from 'pg';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { PrismaClient } from '../src/generated/prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';

describe('Staff authorization and atomic administration', () => {
  let app: INestApplication, db: PrismaService, owner: Client;
  let created = false;
  let admin: Awaited<ReturnType<typeof register>>,
    customer: Awaited<ReturnType<typeof register>>;
  const name = `wearly_staff_${randomUUID().replaceAll('-', '')}_test`;
  const password = 'Staff-fixture-only-2026';
  beforeAll(async () => {
    const url = new URL(process.env.TEST_DATABASE_URL ?? 'http://invalid');
    if (!url.pathname.endsWith('_test'))
      throw new Error('Dedicated test DB required');
    const control = new URL(url);
    owner = new Client({ connectionString: control.toString() });
    await owner.connect();
    await owner.query(`CREATE SCHEMA "${name}"`);
    created = true;
    url.searchParams.set('schema', name);
    url.searchParams.set('options', `-c timezone=UTC -c search_path=${name}`);
    process.env.DATABASE_URL = url.toString();
    process.env.NODE_ENV = 'test';
    process.env.JWT_ACCESS_SECRET = 'staff-access-test-'.repeat(4);
    process.env.JWT_REFRESH_SECRET = 'staff-refresh-test-'.repeat(4);
    const migrated = spawnSync(
      process.execPath,
      ['node_modules/prisma/build/index.js', 'migrate', 'deploy'],
      { env: process.env, encoding: 'utf8', windowsHide: true },
    );
    if (migrated.status !== 0)
      throw new Error('Staff fixture migration failed');
    db = new PrismaClient({
      adapter: new PrismaPg(
        { connectionString: url.toString() },
        { schema: name },
      ),
    }) as PrismaService;
    await db.$connect();
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PrismaService)
      .useValue(db)
      .overrideGuard(ThrottlerGuard)
      .useValue({ canActivate: () => true })
      .compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    admin = await register();
    customer = await register();
    await db.user.update({
      where: { id: admin.user.id },
      data: { role: 'ADMIN' },
    });
  }, 30000);
  afterAll(async () => {
    if (app) await app.close();
    if (db) await db.$disconnect();
    if (owner) {
      try {
        if (created) await owner.query(`DROP SCHEMA "${name}" CASCADE`);
      } finally {
        await owner.end();
      }
    }
  });
  async function register() {
    const email = `staff-${randomUUID()}@example.test`;
    return (
      await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({ name: 'Staff fixture', email, password })
        .expect(201)
    ).body as {
      user: { id: string; email: string; username: string };
      accessToken: string;
      refreshToken: string;
    };
  }
  const get = (path: string, token = admin.accessToken) =>
    request(app.getHttpServer())
      .get('/api/v1/' + path)
      .auth(token, { type: 'bearer' });
  const change = (
    id: string,
    role: string,
    version = 0,
    active = true,
    token = admin.accessToken,
  ) =>
    request(app.getHttpServer())
      .patch('/api/v1/admin/staff/' + id)
      .auth(token, { type: 'bearer' })
      .send({ role, active, expectedVersion: version });
  const login = async (email: string) =>
    (
      await request(app.getHttpServer())
        .post('/api/v1/auth/admin/login')
        .send({
          username: (await db.user.findUniqueOrThrow({ where: { email } }))
            .username,
          password,
        })
        .expect(201)
    ).body.accessToken as string;

  it('restricts staff lookup and refuses registration privilege escalation', async () => {
    await request(app.getHttpServer()).get('/api/v1/admin/staff').expect(401);
    await get('admin/staff', customer.accessToken).expect(403);
    const found = (
      await get('admin/staff')
        .query({ email: customer.user.email.toUpperCase() })
        .expect(200)
    ).body;
    expect(found.total).toBe(1);
    expect(found.items[0]).toMatchObject({
      id: customer.user.id,
      role: 'CUSTOMER',
      staffVersion: 0,
    });
    expect(Object.keys(found.items[0]).sort()).toEqual([
      'active',
      'createdAt',
      'email',
      'id',
      'name',
      'role',
      'staffVersion',
      'username',
    ]);
    await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        name: 'Escalation',
        email: `denied-${randomUUID()}@example.test`,
        password,
        role: 'ADMIN',
      })
      .expect(400);
    await request(app.getHttpServer())
      .post('/api/v1/auth/admin/login')
      .send({ username: customer.user.username, password })
      .expect(403);
  });
  it('validates all staff mutation fields and requires administrator authority', async () => {
    await change(
      customer.user.id,
      'SUPPORT',
      0,
      true,
      customer.accessToken,
    ).expect(403);
    for (const patch of [
      { role: 'ROOT' },
      { role: null },
      { active: 'false' },
      { expectedVersion: -1 },
      { password: 'injected' },
    ]) {
      await request(app.getHttpServer())
        .patch('/api/v1/admin/staff/' + customer.user.id)
        .auth(admin.accessToken, { type: 'bearer' })
        .send({ role: 'SUPPORT', active: true, expectedVersion: 0, ...patch })
        .expect(400);
    }
  });
  it('revokes existing sessions atomically and permits only canonical no-op retries', async () => {
    const person = await register();
    const changed = (await change(person.user.id, 'SUPPORT').expect(200)).body;
    expect(changed).toMatchObject({
      role: 'SUPPORT',
      active: true,
      staffVersion: 1,
    });
    await get('auth/me', person.accessToken).expect(401);
    await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: person.refreshToken })
      .expect(401);
    await change(person.user.id, 'SUPPORT').expect(200);
    await change(person.user.id, 'WAREHOUSE').expect(409);
    expect(
      await db.adminAuditEvent.count({ where: { targetId: person.user.id } }),
    ).toBe(1);
    const token = await login(person.user.email);
    await get('admin/support', token).expect(200);
    await change(person.user.id, 'SUPPORT', 1, false).expect(200);
    await get('admin/support', token).expect(401);
  });
  it('enforces every role boundary on reads and mutation routes', async () => {
    const id = randomUUID();
    const routes: [string, string, string[]][] = [
      ['GET', 'admin/summary', ['MANAGER']],
      ['GET', 'admin/audit', ['MANAGER']],
      ['GET', 'admin/products', ['MANAGER']],
      ['GET', 'admin/inventory', ['MANAGER', 'WAREHOUSE']],
      ['GET', 'admin/orders', ['MANAGER', 'WAREHOUSE', 'SUPPORT']],
      ['GET', 'admin/users', ['MANAGER']],
      ['GET', 'admin/content', ['MANAGER']],
      ['GET', 'admin/promotions', ['MANAGER']],
      ['GET', 'admin/mail', ['MANAGER']],
      ['GET', 'admin/support', ['MANAGER', 'SUPPORT']],
      ['GET', 'admin/staff', []],
      ['PATCH', `admin/staff/${id}`, []],
      ['POST', 'admin/products', ['MANAGER']],
      ['PATCH', `admin/products/${id}`, ['MANAGER']],
      ['POST', `admin/products/${id}/images`, ['MANAGER']],
      ['POST', 'admin/skus', ['MANAGER']],
      ['PATCH', `admin/skus/${id}`, ['MANAGER']],
      ['POST', 'admin/categories', ['MANAGER']],
      ['PATCH', `admin/brands/${id}`, ['MANAGER']],
      ['POST', `admin/inventory/${id}/adjust`, ['MANAGER', 'WAREHOUSE']],
      ['PATCH', `admin/orders/${id}/status`, ['MANAGER', 'WAREHOUSE']],
      ['POST', `admin/orders/${id}/shipment-events`, ['MANAGER', 'WAREHOUSE']],
      ['POST', `admin/orders/${id}/settle-cod`, ['MANAGER']],
      ['POST', `admin/orders/${id}/cancel`, ['MANAGER']],
      ['POST', `admin/orders/${id}/returns/${id}/decision`, ['MANAGER']],
      [
        'POST',
        `admin/orders/${id}/returns/${id}/receive`,
        ['MANAGER', 'WAREHOUSE'],
      ],
      ['POST', `admin/orders/${id}/refunds`, ['MANAGER']],
      ['POST', `admin/orders/${id}/refunds/${id}/query`, ['MANAGER']],
      ['POST', `admin/support/${id}/replies`, ['MANAGER', 'SUPPORT']],
      ['PATCH', `admin/support/${id}`, ['MANAGER', 'SUPPORT']],
      ['POST', 'admin/promotions', ['MANAGER']],
      ['POST', 'admin/content/publish', ['MANAGER']],
    ];
    for (const role of ['MANAGER', 'WAREHOUSE', 'SUPPORT']) {
      const person = await register();
      await change(person.user.id, role).expect(200);
      const token = await login(person.user.email);
      for (const [method, path, allowed] of routes) {
        const client = request(app.getHttpServer());
        const pending =
          method === 'GET'
            ? client.get('/api/v1/' + path)
            : method === 'PATCH'
              ? client.patch('/api/v1/' + path)
              : client.post('/api/v1/' + path);
        const response = await pending
          .auth(token, { type: 'bearer' })
          .send(method === 'GET' ? undefined : {});
        if (!allowed.includes(role))
          expect({ role, path, status: response.status }).toEqual({
            role,
            path,
            status: 403,
          });
        else
          expect({
            role,
            path,
            authorized: ![401, 403, 500].includes(response.status),
          }).toEqual({ role, path, authorized: true });
        if (role === 'MANAGER' && path === 'admin/users')
          expect(
            response.body.items.every(
              (u: { role: string }) => u.role === 'CUSTOMER',
            ),
          ).toBe(true);
      }
    }
  });
  it('rolls back role, version and revocation when audit persistence fails', async () => {
    const person = await register();
    await db.$executeRawUnsafe(
      `ALTER TABLE "AdminAuditEvent" ADD CONSTRAINT "staff_test_failure" CHECK ("targetId" <> '${person.user.id}'::uuid)`,
    );
    try {
      await change(person.user.id, 'MANAGER').expect(500);
      expect(
        await db.user.findUnique({ where: { id: person.user.id } }),
      ).toMatchObject({ role: 'CUSTOMER', active: true, staffVersion: 0 });
      await get('auth/me', person.accessToken).expect(200);
    } finally {
      await db.$executeRaw`ALTER TABLE "AdminAuditEvent" DROP CONSTRAINT "staff_test_failure"`;
    }
  });
  it('rejects conflicting concurrent edits instead of overwriting a newer role', async () => {
    const person = await register();
    const results = await Promise.all([
      change(person.user.id, 'SUPPORT'),
      change(person.user.id, 'WAREHOUSE'),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
    expect(
      await db.adminAuditEvent.count({ where: { targetId: person.user.id } }),
    ).toBe(1);
  });
  it('records catalog and inventory before/after values without descriptions or reasons', async () => {
    const suffix = randomUUID();
    const category = await db.category.create({
        data: { name: suffix, slug: suffix },
      }),
      brand = await db.brand.create({ data: { name: suffix, slug: suffix } });
    const product = await db.product.create({
      data: {
        name: 'Private name',
        description: 'Private draft content',
        slug: suffix,
        material: 'Cotton',
        style: '',
        categoryId: category.id,
        brandId: brand.id,
      },
    });
    await request(app.getHttpServer())
      .patch('/api/v1/admin/products/' + product.id)
      .auth(admin.accessToken, { type: 'bearer' })
      .send({ active: false })
      .expect(200);
    expect(
      (
        await db.adminAuditEvent.findFirstOrThrow({
          where: { targetId: product.id },
        })
      ).details,
    ).toEqual({
      before: {
        active: true,
        tryOnSupported: false,
        categoryId: category.id,
        brandId: brand.id,
      },
      after: {
        active: false,
        tryOnSupported: false,
        categoryId: category.id,
        brandId: brand.id,
      },
    });
    const sku = await db.productVariant.create({
      data: {
        productId: product.id,
        sku: suffix,
        size: 'S',
        color: 'White',
        colorHex: '#FFFFFF',
        price: '100000',
        inventory: { create: { quantity: 5 } },
      },
      include: { inventory: true },
    });
    await request(app.getHttpServer())
      .post('/api/v1/admin/inventory/' + sku.inventory!.id + '/adjust')
      .auth(admin.accessToken, { type: 'bearer' })
      .send({
        delta: -2,
        expectedVersion: 0,
        reason: 'Private reason excluded',
      })
      .expect(201);
    expect(
      (
        await db.adminAuditEvent.findFirstOrThrow({
          where: { targetId: sku.inventory!.id },
        })
      ).details,
    ).toEqual({
      before: { quantity: 5, version: 0 },
      after: {
        quantity: 3,
        version: 1,
        movementId: expect.any(String),
        operation: 'delta',
      },
    });
  });
  it('records order transitions without customer address snapshots', async () => {
    const order = await db.order.create({
      data: {
        userId: customer.user.id,
        idempotencyKey: randomUUID(),
        requestHash: 'fixture',
        addressSnapshot: { name: 'Private recipient' },
        subtotal: '100000',
        shipping: '30000',
        total: '130000',
        payment: { create: { provider: 'cod', amount: '130000' } },
      },
    });
    await request(app.getHttpServer())
      .patch('/api/v1/admin/orders/' + order.id + '/status')
      .auth(admin.accessToken, { type: 'bearer' })
      .send({ status: 'CONFIRMED', expectedVersion: 0 })
      .expect(200);
    expect(
      (
        await db.adminAuditEvent.findFirstOrThrow({
          where: { targetId: order.id },
        })
      ).details,
    ).toEqual({
      before: { status: 'PENDING', version: 0 },
      after: { status: 'CONFIRMED', version: 1 },
    });
  });
  it('records support state changes without the message or recipient', async () => {
    const ticket = (
      await request(app.getHttpServer())
        .post('/api/v1/support')
        .send({
          requestKey: randomUUID(),
          name: 'Private name',
          email: 'private@example.test',
          message: 'Private customer message',
        })
        .expect(201)
    ).body;
    const reply = (
      await request(app.getHttpServer())
        .post('/api/v1/admin/support/' + ticket.id + '/replies')
        .auth(admin.accessToken, { type: 'bearer' })
        .send({
          requestKey: randomUUID(),
          expectedVersion: 0,
          message: 'Private staff reply',
        })
        .expect(201)
    ).body;
    expect(
      (
        await db.adminAuditEvent.findFirstOrThrow({
          where: { targetId: reply.id },
        })
      ).details,
    ).toEqual({
      before: { status: 'OPEN', version: 0 },
      after: { status: 'ANSWERED', version: 1 },
    });
    await request(app.getHttpServer())
      .patch('/api/v1/admin/support/' + ticket.id)
      .auth(admin.accessToken, { type: 'bearer' })
      .send({ expectedVersion: 1, status: 'CLOSED' })
      .expect(200);
    expect(
      (
        await db.adminAuditEvent.findFirstOrThrow({
          where: { targetId: ticket.id },
        })
      ).details,
    ).toEqual({
      before: { status: 'ANSWERED', version: 1 },
      after: { status: 'CLOSED', version: 2 },
    });
    expect(
      JSON.stringify((await get('admin/audit').expect(200)).body),
    ).not.toContain('Private');
  });
  it('cannot concurrently remove the last active administrators', async () => {
    await change(admin.user.id, 'ADMIN', 0, false).expect(409);
    const second = await register();
    await change(second.user.id, 'ADMIN').expect(200);
    const token = await login(second.user.email);
    const results = await Promise.all([
      change(admin.user.id, 'CUSTOMER'),
      change(second.user.id, 'CUSTOMER', 1, true, token),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
    expect(
      await db.user.count({ where: { role: 'ADMIN', active: true } }),
    ).toBe(1);
  });
});
