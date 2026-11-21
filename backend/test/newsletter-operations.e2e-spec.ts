import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';
import { MailService } from '../src/modules/mail/mail.service';
import { sendLocalMail } from '../src/modules/mail/send-local-mail';
jest.mock('../src/modules/mail/send-local-mail', () => ({
  sendLocalMail: jest.fn().mockResolvedValue(undefined),
}));

describe('Newsletter consent and mail operations', () => {
  let app: INestApplication,
    db: PrismaService,
    mail: MailService,
    config: ConfigService;
  let admin: string,
    customer: string,
    userId: string,
    campaignId: string,
    subscriberId: string,
    token: string,
    mailId: string;
  const email = `newsletter-${randomUUID()}@example.test`;
  const call = (method: 'get' | 'post', path: string, auth?: string) => {
    const req = request(app.getHttpServer())[method]('/api/v1/' + path);
    return auth ? req.auth(auth, { type: 'bearer' }) : req;
  };
  beforeAll(async () => {
    if (
      !process.env.TEST_DATABASE_URL ||
      !new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test')
    )
      throw Error('Dedicated test database required');
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
    mail = app.get(MailService);
    config = app.get(ConfigService);
    const registered = (
      await call('post', 'auth/register')
        .send({
          name: 'Newsletter fixture',
          email,
          password: 'Newsletter-test-2026',
        })
        .expect(201)
    ).body;
    customer = registered.accessToken;
    userId = registered.user.id;
    // A separate customer remains useful to verify the API boundary after promotion.
    await call('post', 'content/newsletter')
      .send({ email, consent: true })
      .expect(201);
    const subscriber = await db.newsletterSubscription.findUniqueOrThrow({
      where: { email },
    });
    subscriberId = subscriber.id;
    token = subscriber.unsubscribeToken;
  });
  afterAll(async () => {
    jest.restoreAllMocks();
    if (db) {
      if (campaignId) {
        await db.mailOutbox.deleteMany({ where: { campaignId } });
        await db.newsletterCampaign.deleteMany({ where: { id: campaignId } });
      }
      if (mailId) await db.mailOutbox.deleteMany({ where: { id: mailId } });
      if (subscriberId)
        await db.newsletterSubscription.deleteMany({
          where: { id: subscriberId },
        });
      if (userId) await db.user.deleteMany({ where: { id: userId } });
    }
    await app?.close();
  });
  it('restricts management and creates an idempotent draft and queue', async () => {
    await call('get', 'admin/newsletter', customer).expect(403);
    await call('post', 'admin/mail/' + randomUUID(), customer)
      .send({ action: 'hold', expectedUpdatedAt: new Date().toISOString() })
      .expect(403);
    await db.user.update({ where: { id: userId }, data: { role: 'ADMIN' } });
    admin = (
        await call('post', 'auth/admin/login')
        .send({ username: (await db.user.findUniqueOrThrow({ where: { id: userId } })).username, password: 'Newsletter-test-2026' })
        .expect(201)
    ).body.accessToken;
    const draft = {
      requestKey: randomUUID(),
      subject: 'Thông báo thử',
      body: 'Nội dung thử nghiệm.',
    };
    const results = await Promise.all([
      call('post', 'admin/newsletter/campaigns', admin).send(draft).expect(201),
      call('post', 'admin/newsletter/campaigns', admin).send(draft).expect(201),
    ]);
    campaignId = results[0].body.id;
    expect(results[1].body.id).toBe(campaignId);
    const endpoint = `admin/newsletter/campaigns/${campaignId}/queue`;
    const queues = await Promise.all([
      call('post', endpoint, admin).send({ expectedVersion: 0 }).expect(201),
      call('post', endpoint, admin).send({ expectedVersion: 0 }).expect(201),
    ]);
    expect(queues[0].body.recipientCount).toBe(queues[1].body.recipientCount);
    expect(
      await db.mailOutbox.count({
        where: { campaignId, subscriptionId: subscriberId },
      }),
    ).toBe(1);
    const row = await db.mailOutbox.findFirstOrThrow({
      where: { campaignId, subscriptionId: subscriberId },
    });
    expect(row.body).toContain(`/#/newsletter/unsubscribe?token=${token}`);
    expect(sendLocalMail).not.toHaveBeenCalled();
  });
  it('cancels queued newsletters on public unsubscribe and suppresses an already claimed message', async () => {
    const row = await db.mailOutbox.findFirstOrThrow({
      where: { campaignId, subscriptionId: subscriberId },
    });
    await call('post', 'content/newsletter/unsubscribe')
      .send({ token })
      .expect(201);
    await call('post', 'content/newsletter/unsubscribe')
      .send({ token })
      .expect(201);
    expect(
      (await db.mailOutbox.findUniqueOrThrow({ where: { id: row.id } })).status,
    ).toBe('CANCELLED');
    expect(
      (
        await db.newsletterSubscription.findUniqueOrThrow({
          where: { id: subscriberId },
        })
      ).unsubscribedAt,
    ).not.toBeNull();
    const spy = jest.spyOn(mail, 'claim').mockResolvedValueOnce([row]);
    await mail.processBatch();
    spy.mockRestore();
    expect(sendLocalMail).not.toHaveBeenCalled();
    await call('post', 'admin/mail/' + row.id, admin)
      .send({
        action: 'release',
        expectedUpdatedAt: row.updatedAt.toISOString(),
      })
      .expect(409);
  });
  it('holds stale mail and requires a current preview before releasing or cancelling it', async () => {
    const row = await db.mailOutbox.create({
      data: {
        eventKey: 'mail-review:' + randomUUID(),
        recipient: email,
        subject: 'Stale fixture',
        body: 'Old notification',
        createdAt: new Date('1900-01-01'),
      },
    });
    mailId = row.id;
    config.set('MAIL_DELIVERY_ENABLED', 'true');
    const claimed = await mail.claim();
    expect(claimed.some((r) => r.id === mailId)).toBe(false);
    expect(
      (await db.mailOutbox.findUniqueOrThrow({ where: { id: mailId } })).status,
    ).toBe('HELD');
    const preview = (
      await call('get', 'admin/mail/' + mailId, admin).expect(200)
    ).body;
    expect(preview.body).toBe('Old notification');
    const released = (
      await call('post', 'admin/mail/' + mailId, admin)
        .send({ action: 'release', expectedUpdatedAt: preview.updatedAt })
        .expect(201)
    ).body;
    expect(released.status).toBe('PENDING');
    await call('post', 'admin/mail/' + mailId, admin)
      .send({ action: 'cancel', expectedUpdatedAt: preview.updatedAt })
      .expect(409);
    await call('post', 'admin/mail/' + mailId, admin)
      .send({ action: 'cancel', expectedUpdatedAt: released.updatedAt })
      .expect(201);
    expect(
      await db.adminAuditEvent.count({
        where: { targetId: mailId, action: 'MAIL_UPDATED' },
      }),
    ).toBe(2);
    config.set('MAIL_DELIVERY_ENABLED', 'false');
  });
  it('lets a former subscriber opt in again without reviving cancelled mail', async () => {
    const before = await db.newsletterSubscription.findUniqueOrThrow({
      where: { id: subscriberId },
    });
    expect(before.unsubscribedAt).not.toBeNull();
    await call('post', 'content/newsletter')
      .send({ email, consent: true })
      .expect(201);
    const after = await db.newsletterSubscription.findUniqueOrThrow({
      where: { id: subscriberId },
    });
    expect(after.unsubscribedAt).toBeNull();
    expect(after.consentedAt.getTime()).toBeGreaterThan(
      before.consentedAt.getTime(),
    );
    expect(after.unsubscribeToken).toBe(token);
    expect(
      await db.mailOutbox.count({
        where: { subscriptionId: subscriberId, status: { not: 'CANCELLED' } },
      }),
    ).toBe(0);
    // An active subscriber's repeat submission keeps the original consent.
    await call('post', 'content/newsletter')
      .send({ email, consent: true })
      .expect(201);
    expect(
      (
        await db.newsletterSubscription.findUniqueOrThrow({
          where: { id: subscriberId },
        })
      ).consentedAt,
    ).toEqual(after.consentedAt);
  });
});
