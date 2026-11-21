import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { randomUUID, randomInt } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Customer management with real PostgreSQL', () => {
  let app: INestApplication, db: PrismaService;
  const marker = randomUUID(),
    orders: string[] = [],
    users: string[] = [];
  const tokens: Record<string, string> = {},
    ids: Record<string, string> = {};
  const phone = '09' + randomInt(10000000, 99999999);
  const api = (
    method: 'get' | 'patch' | 'post' | 'delete',
    path: string,
    role = 'ADMIN',
  ) =>
    request(app.getHttpServer())
      [method]('/api/v1/' + path)
      .auth(tokens[role], { type: 'bearer' });
  const detail = async (role = 'BUYER') =>
    (await api('get', 'admin/users/' + ids[role]).expect(200)).body;
  const edit = async (
    body: Record<string, unknown>,
    role = 'BUYER',
    actor = 'ADMIN',
  ) => {
    const expectedUpdatedAt = (await detail(role)).updatedAt;
    return api('patch', 'admin/users/' + ids[role], actor).send({
      expectedUpdatedAt,
      ...body,
    });
  };
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
    for (const role of [
      'ADMIN',
      'MANAGER',
      'WAREHOUSE',
      'SUPPORT',
      'BUYER',
      'SECOND',
    ]) {
      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({
          name: `Customer_${role}-${marker}`,
          email: `${role.toLowerCase()}-${marker}@example.test`,
          password: 'Customers-test-2026',
        })
        .expect(201);
      ids[role] = response.body.user.id;
      users.push(ids[role]);
      tokens[role] = response.body.accessToken;
      if (!['BUYER', 'SECOND'].includes(role))
        await db.user.update({
          where: { id: ids[role] },
          data: { role: role as 'ADMIN' | 'MANAGER' | 'WAREHOUSE' | 'SUPPORT' },
        });
    }
    await db.user.update({
      where: { id: ids.BUYER },
      data: { phone, createdAt: new Date(Date.now() - 40 * 86400000) },
    });
    const fixtures = [
      {
        status: 'DELIVERED',
        provider: 'cod',
        payment: 'PARTIALLY_REFUNDED',
        total: '100000',
      },
      {
        status: 'DELIVERED',
        provider: 'cod',
        payment: 'PENDING',
        total: '200000',
      },
      {
        status: 'CANCELLED',
        provider: 'vnpay',
        payment: 'REFUNDED',
        total: '300000',
      },
      {
        status: 'PENDING',
        provider: 'vnpay',
        payment: 'PAID',
        total: '400000',
      },
      {
        status: 'DELIVERED',
        provider: 'vnpay',
        payment: 'PAID',
        total: '500000',
      },
    ] as const;
    for (const f of fixtures) {
      const order = await db.order.create({
        data: {
          userId: ids.BUYER,
          status: f.status,
          idempotencyKey: randomUUID(),
          requestHash: marker,
          addressSnapshot: {
            recipient: 'Tên khi đặt đơn',
            phone,
            address: 'Địa chỉ gốc',
          },
          subtotal: f.total,
          shipping: '0',
          total: f.total,
          payment: {
            create: {
              provider: f.provider,
              status: f.payment,
              amount: f.total,
            },
          },
        },
        include: { payment: true },
      });
      orders.push(order.id);
      if (f.payment === 'PARTIALLY_REFUNDED')
        await db.refund.create({
          data: {
            paymentId: order.payment!.id,
            primary: true,
            requestKey: randomUUID(),
            payloadHash: 'a'.repeat(64),
            providerRequestId: randomUUID().replace(/-/g, ''),
            amount: '20000',
            reference: marker,
            status: 'SUCCEEDED',
            actorId: ids.ADMIN,
          },
        });
    }
  });
  afterAll(async () => {
    try {
      if (db) {
        await db.adminAuditEvent.deleteMany({
          where: { targetId: { in: users } },
        });
        await db.orderItem.deleteMany({ where: { orderId: { in: orders } } });
        await db.payment.deleteMany({ where: { orderId: { in: orders } } });
        await db.order.deleteMany({ where: { id: { in: orders } } });
        await db.user.deleteMany({ where: { id: { in: users } } });
      }
    } finally {
      await app?.close();
    }
  });

  it('lists only customers, with counts, stable sort, search, filters and pagination', async () => {
    const list = async (q = '') =>
      (await api('get', `admin/users?q=${marker}&${q}`).expect(200)).body;
    const first = await list('sort=orders_desc&limit=1');
    expect(first.total).toBe(2);
    expect(first.items[0].id).toBe(ids.BUYER);
    expect(first.items[0]._count.orders).toBe(5);
    expect((await list('sort=orders_desc&limit=1&page=2')).items[0].id).toBe(
      ids.SECOND,
    );
    expect((await list('orders=has_orders')).total).toBe(1);
    expect((await list('orders=no_orders')).total).toBe(1);
    expect(
      (await list('registered=30d')).items.map((u: { id: string }) => u.id),
    ).toEqual([ids.SECOND]);
    expect((await list('sort=oldest')).items[0].id).toBe(ids.BUYER);
    expect(
      (
        await api(
          'get',
          'admin/users?q=' + encodeURIComponent('+84 ' + phone.slice(1)),
        ).expect(200)
      ).body.items[0].id,
    ).toBe(ids.BUYER);
    expect(
      (await api('get', `admin/users?q=${ids.BUYER}`).expect(200)).body.total,
    ).toBe(1);
    expect(
      (await api('get', `admin/users?q=Customer%25${marker}`).expect(200)).body
        .total,
    ).toBe(0);
    const user = first.items[0];
    for (const key of [
      'passwordHash',
      'passwordChangedAt',
      'refreshTokens',
      'passwordResetCode',
      'addresses',
    ])
      expect(user[key]).toBeUndefined();
    for (const query of [
      'sort=bad',
      'status=SHIPPED',
      'orders=bad',
      'registered=year',
      'page=0',
      'limit=101',
    ])
      await api('get', 'admin/users?' + query).expect(400);
  });
  it('calculates global statistics and purchase totals without counting unpaid COD as paid', async () => {
    const summary = (await api('get', 'admin/users/summary').expect(200)).body;
    expect(summary.total).toBe(
      await db.user.count({ where: { role: 'CUSTOMER', deletedAt: null } }),
    );
    expect(summary.active + summary.inactive).toBe(summary.total);
    const customer = await detail();
    expect(customer.summary).toMatchObject({
      totalOrders: 5,
      deliveredOrders: 3,
      deliveredValueVnd: '800000',
      netPaidVnd: '980000',
    });
    const history = (
      await api('get', `admin/orders?customerId=${ids.BUYER}&limit=2`).expect(
        200,
      )
    ).body;
    expect(history.total).toBe(5);
    expect(history.items).toHaveLength(2);
    expect(
      history.items.every((o: { id: string }) => orders.includes(o.id)),
    ).toBe(true);
    expect(
      (await api('get', `admin/orders?customerId=${ids.SECOND}`).expect(200))
        .body.total,
    ).toBe(0);
    await api('get', 'admin/orders?customerId=bad').expect(400);
  });
  it('rejects unauthorized reads and edits, staff targets, role injection and invalid input', async () => {
    const expectedUpdatedAt = (await detail()).updatedAt;
    for (const role of ['BUYER', 'WAREHOUSE', 'SUPPORT']) {
      await api('get', 'admin/users', role).expect(403);
      await api('get', 'admin/users/summary', role).expect(403);
      await api('get', 'admin/users/' + ids.BUYER, role).expect(403);
      await api('patch', 'admin/users/' + ids.BUYER, role)
        .send({ name: 'Bad', expectedUpdatedAt })
        .expect(403);
    }
    await api('get', 'admin/users/' + ids.ADMIN).expect(404);
    await api('patch', 'admin/users/' + ids.ADMIN)
      .send({ name: 'Bad', expectedUpdatedAt: new Date().toISOString() })
      .expect(404);
    await api('get', 'admin/users/' + randomUUID()).expect(404);
    for (const body of [
      { role: 'ADMIN' },
      { email: 'bad' },
      { phone: 'abc12345678' },
      { name: '   ' },
      { name: null },
      { phone: null },
      { active: false },
    ]) {
      const r = await edit(body);
      expect(r.status).toBe(400);
    }
    await api('patch', 'admin/users/' + ids.BUYER)
      .send({ name: 'No version' })
      .expect(400);
    expect((await detail()).name).toBe(`Customer_BUYER-${marker}`);
  });
  it('validates duplicate contacts across admin and self-service, normalizes Vietnam prefixes, and allows blanks', async () => {
    const duplicate = '+84 ' + phone.slice(1, 4) + ' ' + phone.slice(4);
    expect((await edit({ phone: duplicate }, 'SECOND')).body.error.code).toBe(
      'PHONE_ALREADY_EXISTS',
    );
    expect(
      (
        await api('patch', 'users/me', 'SECOND')
          .send({ phone: duplicate })
          .expect(409)
      ).body.error.code,
    ).toBe('PHONE_ALREADY_EXISTS');
    const own = await api('patch', 'users/me', 'BUYER')
      .send({ phone: duplicate })
      .expect(200);
    expect(own.body.phone).toBe(phone);
    expect(
      (await edit({ email: `ADMIN-${marker}@example.test` }, 'SECOND')).body
        .error.code,
    ).toBe('EMAIL_ALREADY_EXISTS');
    expect((await edit({ phone: '' }, 'SECOND')).status).toBe(200);
    await api('patch', 'users/me', 'SECOND')
      .send({ phone: 'not-a-phone' })
      .expect(400);
  });
  it('serializes competing phone claims made through different endpoints', async () => {
    const shared = '08' + randomInt(10000000, 99999999);
    const timestamp = (await detail()).updatedAt;
    const results = await Promise.all([
      api('patch', 'admin/users/' + ids.BUYER).send({
        phone: shared,
        expectedUpdatedAt: timestamp,
      }),
      api('patch', 'users/me', 'SECOND').send({
        phone: '+84' + shared.slice(1),
      }),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
    expect(await db.user.count({ where: { phone: shared } })).toBe(1);
  });
  it('allows manager edits, blocks stale saves and keeps order snapshots unchanged', async () => {
    const timestamp = (await detail()).updatedAt;
    const results = await Promise.all([
      api('patch', 'admin/users/' + ids.BUYER, 'MANAGER').send({
        name: 'Tên sửa A',
        expectedUpdatedAt: timestamp,
      }),
      api('patch', 'admin/users/' + ids.BUYER, 'MANAGER').send({
        name: 'Tên sửa B',
        expectedUpdatedAt: timestamp,
      }),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
    const events = await db.adminAuditEvent.findMany({
      where: { targetId: ids.BUYER },
    });
    expect(JSON.stringify(events)).not.toContain('Tên sửa');
    expect(JSON.stringify(events)).not.toContain('@example.test');
    expect(
      (await db.order.findUniqueOrThrow({ where: { id: orders[0] } }))
        .addressSnapshot,
    ).toMatchObject({
      recipient: 'Tên khi đặt đơn',
      phone,
      address: 'Địa chỉ gốc',
    });
  });
  it('revokes sessions and old recovery codes on email change, without changing passwords or history', async () => {
    const before = await db.user.findUniqueOrThrow({
      where: { id: ids.BUYER },
    });
    await db.passwordResetToken.create({
      data: {
        userId: ids.BUYER,
        tokenHash: randomUUID(),
        expiresAt: new Date(Date.now() + 60000),
      },
    });
    await db.passwordResetCode.create({
      data: {
        userId: ids.BUYER,
        codeHash: randomUUID(),
        requestedAt: new Date(),
        expiresAt: new Date(Date.now() + 60000),
      },
    });
    const response = await edit({ email: ` Changed-${marker}@EXAMPLE.TEST ` });
    expect(response.status).toBe(200);
    expect(response.body.email).toBe(`changed-${marker}@example.test`);
    await api('get', 'users/me', 'BUYER').expect(401);
    expect(
      await db.passwordResetToken.count({
        where: { userId: ids.BUYER, consumedAt: null },
      }),
    ).toBe(0);
    expect(
      await db.passwordResetCode.count({
        where: { userId: ids.BUYER, consumedAt: null },
      }),
    ).toBe(0);
    expect(
      (await db.user.findUniqueOrThrow({ where: { id: ids.BUYER } }))
        .passwordHash,
    ).toBe(before.passwordHash);
    expect((await detail()).summary.totalOrders).toBe(5);
  });
  it('locks/unlocks customers and invalidates old sessions permanently', async () => {
    let current = await detail('SECOND');
    await api('patch', 'admin/users/' + ids.SECOND + '/status')
      .send({ active: false, expectedUpdatedAt: current.updatedAt })
      .expect(200);
    await api('get', 'users/me', 'SECOND').expect(401);
    await api('patch', 'admin/users/' + ids.SECOND + '/status')
      .send({ active: true, expectedUpdatedAt: current.updatedAt })
      .expect(409);
    current = await detail('SECOND');
    expect(current.active).toBe(false);
    const filtered = (
      await api('get', `admin/users?q=${marker}&status=hidden`).expect(200)
    ).body;
    expect(filtered.total).toBe(1);
    await api('patch', 'admin/users/' + ids.SECOND + '/status')
      .send({ active: true, expectedUpdatedAt: current.updatedAt })
      .expect(200);
    await api('get', 'users/me', 'SECOND').expect(401);
    expect((await detail('SECOND')).active).toBe(true);
  });

  it('creates a customer as manager with normalized contacts, hashed password and a private audit', async () => {
    const email = `created-${marker}@example.test`,
      password = 'New-customer-2026';
    const number = '07' + randomInt(10000000, 99999999);
    const response = await api('post', 'admin/users', 'MANAGER')
      .send({
        name: '  Khách mới  ',
        email: ` ${email.toUpperCase()} `,
        phone: '+84 ' + number.slice(1),
        password,
      })
      .expect(201);
    users.push(response.body.id);
    expect(response.body).toMatchObject({
      name: 'Khách mới',
      email,
      phone: number,
      active: true,
      role: 'CUSTOMER',
    });
    expect(response.body.passwordHash).toBeUndefined();
    expect(response.body.accessToken).toBeUndefined();
    const stored = await db.user.findUniqueOrThrow({
      where: { id: response.body.id },
    });
    expect(stored.passwordHash).not.toBe(password);
    await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email, password })
      .expect(201);
    const audit = await db.adminAuditEvent.findFirstOrThrow({
      where: { targetId: stored.id, action: 'CUSTOMER_CREATED' },
    });
    expect(JSON.stringify(audit)).not.toContain(email);
    expect(JSON.stringify(audit)).not.toContain(password);
    await api('post', 'admin/users')
      .send({ name: 'Duplicate', email, password })
      .expect(409);
    const duplicatePhone = await api('post', 'admin/users')
      .send({
        name: 'Duplicate',
        email: `phone-${email}`,
        phone: number,
        password,
      })
      .expect(409);
    expect(duplicatePhone.body.error.code).toBe('PHONE_ALREADY_EXISTS');
  });

  it('validates creation and rejects unauthorized creation/deletion and staff targets', async () => {
    const valid = {
      name: 'Khách mới',
      email: `invalid-${marker}@example.test`,
      password: 'New-customer-2026',
    };
    for (const body of [
      { name: ' ' },
      { email: 'bad' },
      { password: 'short' },
      { phone: 'bad' },
      { role: 'ADMIN' },
      { active: false },
      { deletedAt: new Date().toISOString() },
      { name: null },
    ])
      await api('post', 'admin/users')
        .send({ ...valid, ...body })
        .expect(400);
    for (const role of ['WAREHOUSE', 'SUPPORT']) {
      await api('post', 'admin/users', role).send(valid).expect(403);
      const expectedUpdatedAt = (await detail('SECOND')).updatedAt;
      await api('delete', 'admin/users/' + ids.SECOND, role)
        .send({ expectedUpdatedAt })
        .expect(403);
    }
    await request(app.getHttpServer())
      .post('/api/v1/admin/users')
      .send(valid)
      .expect(401);
    await api('delete', 'admin/users/' + ids.ADMIN)
      .send({ expectedUpdatedAt: new Date().toISOString() })
      .expect(404);
    await api('delete', 'admin/users/' + ids.SECOND)
      .send({})
      .expect(400);
  });

  it('creates staff through the access checkbox with a chosen role and admin username', async () => {
    for (const role of ['ADMIN', 'MANAGER', 'WAREHOUSE', 'SUPPORT']) {
      const username = `grant-${role.toLowerCase()}-${marker}`;
      const email = `${username}@example.test`,
        password = 'Staff-access-2026';
      const created = await api('post', 'admin/users')
        .send({
          name: 'Nhân sự mới',
          email,
          password,
          adminAccess: true,
          adminRole: role,
          username: ` ${username.toUpperCase()} `,
        })
        .expect(201);
      users.push(created.body.id);
      expect(created.body).toMatchObject({ username, role, active: true });
      const login = await request(app.getHttpServer())
        .post('/api/v1/auth/admin/login')
        .send({ username, password })
        .expect(201);
      await request(app.getHttpServer())
        .get('/api/v1/admin/orders')
        .auth(login.body.accessToken, { type: 'bearer' })
        .expect(200);
      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({ email, password })
        .expect(403);
      expect(
        (await api('get', 'admin/users?q=' + created.body.id).expect(200)).body
          .total,
      ).toBe(0);
      expect(
        (await api('get', 'admin/staff?email=' + email).expect(200)).body.total,
      ).toBe(1);
    }
  });

  it('restricts granting access to admins, validates access settings and rejects duplicate usernames', async () => {
    const valid = {
      name: 'Staff candidate',
      email: `candidate-${marker}@example.test`,
      password: 'Staff-access-2026',
    };
    const access = {
      adminAccess: true,
      adminRole: 'MANAGER',
      username: `candidate-${marker}`,
    };
    const expectedUpdatedAt = (await detail('SECOND')).updatedAt;
    for (const body of [
      { adminAccess: 'true' },
      { adminAccess: true },
      { ...access, adminRole: 'CUSTOMER' },
      { ...access, username: 'a@b' },
      { ...access, username: null },
      { adminRole: 'ADMIN' },
      { username: 'admin' },
      { ...access, adminAccess: false },
    ])
      await api('post', 'admin/users')
        .send({ ...valid, ...body })
        .expect(400);
    await api('post', 'admin/users', 'MANAGER')
      .send({ ...valid, ...access })
      .expect(403);
    await api('patch', 'admin/users/' + ids.SECOND, 'MANAGER')
      .send({ ...access, name: 'Must not change', expectedUpdatedAt })
      .expect(403);
    const existing = await db.user.findUniqueOrThrow({
      where: { id: ids.ADMIN },
    });
    await api('post', 'admin/users')
      .send({ ...valid, ...access, username: existing.username })
      .expect(409);
    await api('patch', 'admin/users/' + ids.SECOND)
      .send({
        ...access,
        username: existing.username,
        name: 'Must not change',
        expectedUpdatedAt,
      })
      .expect(409);
    expect((await detail('SECOND')).name).not.toBe('Must not change');
    expect((await detail('SECOND')).role).toBe('CUSTOMER');
  });

  it('promotes a customer atomically, revokes old sessions and supports removing access through staff administration', async () => {
    const email = `promoted-${marker}@example.test`,
      password = 'Staff-access-2026';
    const session = await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({ name: 'Khách được cấp quyền', email, password })
      .expect(201);
    const id = session.body.user.id;
    users.push(id);
    const before = (await api('get', 'admin/users/' + id).expect(200)).body;
    const access = {
      adminAccess: true,
      adminRole: 'SUPPORT',
      username: `promoted-${marker}`,
    };
    await api('patch', 'admin/users/' + id)
      .send({ ...access, expectedUpdatedAt: new Date(0).toISOString() })
      .expect(409);
    const promoted = await api('patch', 'admin/users/' + id)
      .send({
        ...access,
        name: 'Nhân viên hỗ trợ',
        expectedUpdatedAt: before.updatedAt,
      })
      .expect(200);
    expect(promoted.body).toMatchObject({
      role: 'SUPPORT',
      username: access.username,
      name: 'Nhân viên hỗ trợ',
    });
    await request(app.getHttpServer())
      .get('/api/v1/users/me')
      .auth(session.body.accessToken, { type: 'bearer' })
      .expect(401);
    await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: session.body.refreshToken })
      .expect(401);
    const staffSession = await request(app.getHttpServer())
      .post('/api/v1/auth/admin/login')
      .send({ username: access.username, password })
      .expect(201);
    await request(app.getHttpServer())
      .get('/api/v1/admin/users')
      .auth(staffSession.body.accessToken, { type: 'bearer' })
      .expect(403);
    const current = await db.user.findUniqueOrThrow({ where: { id } });
    expect(current.staffVersion).toBe(1);
    const audit = await db.adminAuditEvent.findFirstOrThrow({
      where: { targetId: id, action: 'STAFF_UPDATED' },
    });
    expect(JSON.stringify(audit.details)).toContain('SUPPORT');
    expect(JSON.stringify(audit.details)).not.toContain(access.username);
    await api('patch', 'admin/staff/' + id)
      .send({
        role: 'CUSTOMER',
        active: true,
        expectedVersion: current.staffVersion,
      })
      .expect(200);
    await request(app.getHttpServer())
      .get('/api/v1/admin/orders')
      .auth(staffSession.body.accessToken, { type: 'bearer' })
      .expect(401);
    await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email, password })
      .expect(201);
    expect((await api('get', 'admin/users/' + id).expect(200)).body.role).toBe(
      'CUSTOMER',
    );
  });

  it('deletes a customer with orders, revokes access and recovery, and removes it from lists and counts', async () => {
    const current = await detail();
    const email = current.email,
      password = 'Customers-test-2026';
    const session = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email, password })
      .expect(201);
    await db.passwordResetToken.create({
      data: {
        userId: ids.BUYER,
        tokenHash: randomUUID(),
        expiresAt: new Date(Date.now() + 60000),
      },
    });
    await db.passwordResetCode.update({
      where: { userId: ids.BUYER },
      data: { consumedAt: null },
    });
    const before = (await api('get', 'admin/users/summary').expect(200)).body;
    await api('delete', 'admin/users/' + ids.BUYER)
      .send({ expectedUpdatedAt: new Date(0).toISOString() })
      .expect(409);
    await api('delete', 'admin/users/' + ids.BUYER, 'MANAGER')
      .send({ expectedUpdatedAt: current.updatedAt })
      .expect(200);
    const stored = await db.user.findUniqueOrThrow({
      where: { id: ids.BUYER },
    });
    expect(stored.deletedAt).not.toBeNull();
    expect(stored.active).toBe(false);
    await request(app.getHttpServer())
      .get('/api/v1/users/me')
      .auth(session.body.accessToken, { type: 'bearer' })
      .expect(401);
    await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({ email, password })
      .expect(401);
    await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: session.body.refreshToken })
      .expect(401);
    expect(
      await db.passwordResetToken.count({
        where: { userId: ids.BUYER, consumedAt: null },
      }),
    ).toBe(0);
    expect(
      await db.passwordResetCode.count({
        where: { userId: ids.BUYER, consumedAt: null },
      }),
    ).toBe(0);
    await api('get', 'admin/users/' + ids.BUYER).expect(404);
    for (const suffix of ['', '&status=hidden', '&status=active']) {
      expect(
        (await api('get', `admin/users?q=${ids.BUYER}${suffix}`).expect(200))
          .body.total,
      ).toBe(0);
    }
    const after = (await api('get', 'admin/users/summary').expect(200)).body;
    expect(after.total).toBe(before.total - 1);
    expect(after.active).toBe(before.active - 1);
    expect(
      (await api('get', `admin/orders?customerId=${ids.BUYER}`).expect(200))
        .body.total,
    ).toBe(5);
    expect(
      (await db.order.findUniqueOrThrow({ where: { id: orders[0] } }))
        .addressSnapshot,
    ).toMatchObject({ recipient: 'Tên khi đặt đơn', phone });
    await api('patch', 'admin/users/' + ids.BUYER + '/status')
      .send({ active: true, expectedUpdatedAt: stored.updatedAt.toISOString() })
      .expect(404);
    await api('patch', 'admin/staff/' + ids.BUYER)
      .send({
        role: 'CUSTOMER',
        active: true,
        expectedVersion: stored.staffVersion,
      })
      .expect(404);
    expect(
      (
        await api(
          'get',
          'admin/staff?email=' + encodeURIComponent(email),
        ).expect(200)
      ).body.total,
    ).toBe(0);
    await api('delete', 'admin/users/' + ids.BUYER)
      .send({ expectedUpdatedAt: stored.updatedAt.toISOString() })
      .expect(404);
    expect(
      await db.adminAuditEvent.count({
        where: { targetId: ids.BUYER, action: 'CUSTOMER_DELETED' },
      }),
    ).toBe(1);
  });
});
