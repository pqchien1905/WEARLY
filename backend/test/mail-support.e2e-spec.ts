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
  let buyerId: string, buyerEmail: string;
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
      } else {
        buyer = r.body.accessToken;
        buyerId = r.body.user.id;
        buyerEmail = r.body.user.email;
      }
    }
  });
  afterAll(async () => {
    jest.restoreAllMocks();
    if (app) await app.close();
  });
  it('paginates support and mail at ten by default, without duplicates, and clamps stale pages', async () => {
    const prefix = `paging-${randomUUID()}`;
    const tickets = Array.from({ length: 12 }, (_, i) => ({
      id: randomUUID(),
      requestKey: randomUUID(),
      payloadHash: '0'.repeat(64),
      name: `${prefix}-${i}`,
      email: 'paging@example.test',
      message: 'Pagination fixture',
    }));
    const mails = tickets.map((t) => ({
      eventKey: t.id,
      recipient: t.email,
      subject: prefix,
      body: 'Pagination fixture',
      status: 'SENT' as const,
    }));
    await db.supportTicket.createMany({ data: tickets });
    await db.mailOutbox.createMany({ data: mails });
    try {
      for (const path of ['admin/support', 'admin/mail']) {
        const first = (await call('get', path, admin).expect(200)).body;
        expect(first).toMatchObject({ page: 1, limit: 10 });
        expect(first.items).toHaveLength(10);
        const second = (await call('get', `${path}?page=2`, admin).expect(200))
          .body;
        expect(second.page).toBe(2);
        expect(second.items.length).toBeGreaterThan(0);
        expect(
          second.items.some((row: { id: string }) =>
            first.items.some((other: { id: string }) => row.id === other.id),
          ),
        ).toBe(false);
        const last = (
          await call('get', `${path}?page=10000&limit=20`, admin).expect(200)
        ).body;
        expect(last.page).toBe(Math.max(1, Math.ceil(last.total / 20)));
        expect(last.limit).toBe(20);
        await call('get', `${path}?limit=0`, admin).expect(400);
      }
    } finally {
      await db.mailOutbox.deleteMany({ where: { subject: prefix } });
      await db.supportTicket.deleteMany({
        where: { id: { in: tickets.map((t) => t.id) } },
      });
    }
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
  it('links signed-in requests to the account and keeps the thread private', async () => {
    const mine = 'users/me/support';
    await call('get', mine).expect(401);
    const request = {
      requestKey: randomUUID(),
      message: 'Đơn của tôi cần đổi size áo.',
    };
    for (const body of [
      { ...request, message: 'short' },
      { ...request, email: 'other@example.test' },
      { ...request, requestKey: 'bad' },
    ])
      await call('post', mine, buyer).send(body).expect(400);
    const created = (await call('post', mine, buyer).send(request).expect(201))
      .body;
    expect(Object.keys(created).sort()).toEqual(['createdAt', 'id']);
    expect(
      (await call('post', mine, buyer).send(request).expect(201)).body,
    ).toEqual(created);
    await call('post', mine, buyer)
      .send({ ...request, message: 'Một nội dung khác hẳn.' })
      .expect(409);
    const stored = await db.supportTicket.findUniqueOrThrow({
      where: { id: created.id },
    });
    expect(stored).toMatchObject({ userId: buyerId, email: buyerEmail });
    // A guest request with the same email is not attached to the account.
    const guest = (
      await call('post', 'support')
        .send({ ...draft(), email: buyerEmail })
        .expect(201)
    ).body;
    expect((await call('get', mine, buyer).expect(200)).body).toMatchObject({
      total: 1,
      items: [{ id: created.id, status: 'OPEN', _count: { replies: 0 } }],
    });
    await call('get', `${mine}/${guest.id}`, buyer).expect(404);
    await call('post', `${mine}/${guest.id}/replies`, buyer)
      .send({ requestKey: randomUUID(), message: 'Not mine' })
      .expect(404);
    // Another account cannot read or write the ticket.
    expect((await call('get', mine, admin).expect(200)).body.total).toBe(0);
    await call('get', `${mine}/${created.id}`, admin).expect(404);
    expect(
      (await call('get', `admin/support?userId=${buyerId}`, admin).expect(200))
        .body,
    ).toMatchObject({ total: 1, items: [{ id: created.id, userId: buyerId }] });
    await call('get', 'admin/support?userId=bad', admin).expect(400);
    // Staff replies reach the account's current email address.
    const renamed = randomUUID() + '@example.test';
    await db.user.update({ where: { id: buyerId }, data: { email: renamed } });
    const path = 'admin/support/' + created.id;
    await call('post', path + '/replies', admin)
      .send({
        requestKey: randomUUID(),
        expectedVersion: 0,
        message: 'Bạn có thể đổi size trong 7 ngày.',
      })
      .expect(201);
    const mail = await db.mailOutbox.findFirstOrThrow({
      where: { supportId: created.id },
    });
    expect(mail.recipient).toBe(renamed);
    expect(mail.body).toContain(`/#/account/support/${created.id}`);
    let thread = (await call('get', `${mine}/${created.id}`, buyer).expect(200))
      .body;
    expect(thread).toMatchObject({
      status: 'ANSWERED',
      message: request.message,
      replies: [
        { fromCustomer: false, message: 'Bạn có thể đổi size trong 7 ngày.' },
      ],
    });
    expect(Object.keys(thread.replies[0]).sort()).toEqual(
      ['createdAt', 'fromCustomer', 'id', 'message'].sort(),
    );
    expect(JSON.stringify(thread)).not.toMatch(/example\.test|actorId|mail/);
    const followUp = { requestKey: randomUUID(), message: 'Cảm ơn, tôi đổi M.' };
    const sent = (
      await call('post', `${mine}/${created.id}/replies`, buyer)
        .send(followUp)
        .expect(201)
    ).body;
    expect(
      (
        await call('post', `${mine}/${created.id}/replies`, buyer)
          .send(followUp)
          .expect(201)
      ).body,
    ).toEqual(sent);
    thread = (await call('get', `${mine}/${created.id}`, buyer).expect(200))
      .body;
    expect(thread.status).toBe('OPEN');
    expect(thread.replies.map((r: { fromCustomer: boolean }) => r.fromCustomer))
      .toEqual([false, true]);
    expect(await db.mailOutbox.count({ where: { supportId: created.id } })).toBe(
      1,
    );
    const detail = (await call('get', path, admin).expect(200)).body;
    expect(detail).toMatchObject({
      status: 'OPEN',
      version: 2,
      user: { id: buyerId, email: renamed },
    });
    expect(detail.replies[1]).toMatchObject({
      fromCustomer: true,
      actorId: buyerId,
    });
    // A staff reply key cannot replay a customer follow-up.
    await call('post', path + '/replies', admin)
      .send({
        requestKey: followUp.requestKey,
        expectedVersion: 2,
        message: followUp.message,
      })
      .expect(409);
    await call('patch', path, admin)
      .send({ expectedVersion: 2, status: 'CLOSED' })
      .expect(200);
    await call('post', `${mine}/${created.id}/replies`, buyer)
      .send({ requestKey: randomUUID(), message: 'Còn một câu hỏi.' })
      .expect(409);
  });
  it('limits public contact submissions to five per minute', async () => {
    jest.spyOn(ThrottlerGuard.prototype, 'canActivate').mockRestore();
    for (let i = 0; i < 5; i++)
      await call('post', 'support').send(draft()).expect(201);
    await call('post', 'support').send(draft()).expect(429);
  });
});
