import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { INestApplication } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { AddressInfo } from 'node:net';
import { SMTPServer } from 'smtp-server';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/database/prisma.service';
import { MailService } from '../src/modules/mail/mail.service';
import { enqueueMail } from '../src/modules/mail/outbox';
import { validateEnv } from '../src/config/env.validation';
describe('Transactional local mail with real PostgreSQL and SMTP', () => {
  let app: INestApplication,
    db: PrismaService,
    smtp: SMTPServer,
    mail: MailService,
    reject = false;
  const messages: string[] = [],
    prefix = 'mail-fixture:' + randomUUID() + ':';
  const create = () =>
    db.mailOutbox.create({
      data: {
        eventKey: prefix + randomUUID(),
        recipient: 'fixture@example.test',
        subject: 'Local notification',
        body: 'Immutable event facts',
      },
    });
  beforeAll(async () => {
    if (
      !new URL(
        process.env.TEST_DATABASE_URL ?? 'http://invalid',
      ).pathname.endsWith('_test')
    )
      throw Error('Dedicated test DB required');
    smtp = new SMTPServer({
      authOptional: true,
      disabledCommands: ['AUTH', 'STARTTLS'],
      logger: false,
      onData(stream, _session, done) {
        let text = '';
        stream.on('data', (b: Buffer) => (text += b.toString()));
        stream.on('end', () => {
          if (reject) done(Error('private smtp detail'));
          else {
            messages.push(text);
            done();
          }
        });
      },
    });
    await new Promise<void>((resolve) => smtp.listen(0, '127.0.0.1', resolve));
    const config = validateEnv({
      ...process.env,
      DATABASE_URL: process.env.TEST_DATABASE_URL,
      NODE_ENV: 'test',
      JWT_ACCESS_SECRET: 'test-access-'.repeat(5),
      JWT_REFRESH_SECRET: 'test-refresh-'.repeat(5),
      LOCAL_MAIL_ENABLED: 'true',
      SMTP_HOST: '127.0.0.1',
      SMTP_PORT: (smtp.server.address() as AddressInfo).port,
      SMTP_FROM: 'store@example.test',
      SMTP_ALLOW_INSECURE_LOCAL: 'true',
      PASSWORD_RECOVERY_ENABLED: 'false',
    });
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ConfigService)
      .useValue(new ConfigService(config))
      .compile();
    app = module.createNestApplication({ logger: false });
    await app.init();
    db = app.get(PrismaService);
    mail = app.get(MailService);
    // Drain only this dedicated test database before exercising transport failures.
    while (
      await db.mailOutbox.count({
        where: { status: 'PENDING', nextAttemptAt: { lte: new Date() } },
      })
    )
      await mail.processBatch();
  });
  afterAll(async () => {
    if (db)
      await db.mailOutbox.deleteMany({
        where: { eventKey: { startsWith: prefix } },
      });
    if (app) await app.close();
    if (smtp) await new Promise<void>((r) => smtp.close(() => r()));
  });
  it('commits an immutable event once and rolls it back with its transaction', async () => {
    const data = {
      eventKey: prefix + randomUUID(),
      recipient: 'fixture@example.test',
      subject: 'Order placed',
      body: 'Original facts',
    };
    await db.$transaction(async (tx) => {
      await enqueueMail(tx, data);
      await enqueueMail(tx, { ...data, body: 'Changed facts' });
    });
    expect(
      await db.mailOutbox.count({ where: { eventKey: data.eventKey } }),
    ).toBe(1);
    expect(
      (
        await db.mailOutbox.findUniqueOrThrow({
          where: { eventKey: data.eventKey },
        })
      ).body,
    ).toBe('Original facts');
    await expect(
      db.$transaction(async (tx) => {
        await enqueueMail(tx, {
          ...data,
          eventKey: data.eventKey + '-rollback',
        });
        throw Error('rollback');
      }),
    ).rejects.toThrow('rollback');
    expect(
      await db.mailOutbox.count({
        where: { eventKey: data.eventKey + '-rollback' },
      }),
    ).toBe(0);
    await mail.processBatch();
  });
  it('delivers through SMTP once per claim with a stable Message-ID', async () => {
    const row = await create();
    await Promise.all([mail.processBatch(), mail.processBatch()]);
    expect(
      await db.mailOutbox.findUniqueOrThrow({ where: { id: row.id } }),
    ).toMatchObject({
      status: 'SENT',
      attempts: 1,
      lastError: null,
      leaseToken: null,
    });
    const matching = messages.filter((m) =>
      m.includes('<' + row.id + '@wearly.local>'),
    );
    expect(matching).toHaveLength(1);
    expect(matching[0]).toContain('Immutable event facts');
  });
  it('persists failures without raw SMTP details and retries with backoff to a finite limit', async () => {
    const row = await create();
    reject = true;
    try {
      for (let attempt = 1; attempt <= 5; attempt++) {
        await mail.processBatch();
        let state = await db.mailOutbox.findUniqueOrThrow({
          where: { id: row.id },
        });
        expect(state).toMatchObject({
          attempts: attempt,
          status: attempt === 5 ? 'FAILED' : 'PENDING',
          lastError: 'MAIL_DELIVERY_FAILED',
        });
        await mail.processBatch();
        state = await db.mailOutbox.findUniqueOrThrow({
          where: { id: row.id },
        });
        expect(state.attempts).toBe(attempt);
        await db.mailOutbox.update({
          where: { id: row.id },
          data: { nextAttemptAt: new Date(0) },
        });
      }
    } finally {
      reject = false;
    }
  });
  it('recovers expired leases and prevents the previous owner from completing them', async () => {
    const row = await create(),
      first = (await mail.claim()).find((r) => r.id === row.id)!;
    expect(first).toBeDefined();
    await db.mailOutbox.update({
      where: { id: row.id },
      data: { leaseUntil: new Date(0) },
    });
    const second = (await mail.claim()).find((r) => r.id === row.id)!;
    expect(second.leaseToken).not.toBe(first.leaseToken);
    await mail.settle(first, true);
    expect(
      (await db.mailOutbox.findUniqueOrThrow({ where: { id: row.id } })).status,
    ).toBe('PROCESSING');
    await mail.settle(second, true);
    expect(
      (await db.mailOutbox.findUniqueOrThrow({ where: { id: row.id } })).status,
    ).toBe('SENT');
    const exhausted = await create();
    await db.mailOutbox.update({
      where: { id: exhausted.id },
      data: {
        status: 'PROCESSING',
        attempts: 5,
        leaseUntil: new Date(0),
        leaseToken: randomUUID(),
      },
    });
    await mail.claim();
    expect(
      (await db.mailOutbox.findUniqueOrThrow({ where: { id: exhausted.id } }))
        .status,
    ).toBe('FAILED');
  });
  it('waits for the whole batch before surfacing a database settlement failure', async () => {
    const rows = await Promise.all([create(), create()]),
      settle = mail.settle.bind(mail);
    let completed = false,
      calls = 0;
    const spy = jest
      .spyOn(mail, 'settle')
      .mockImplementation(async (row, success) => {
        if (calls++ === 0) throw Error('fixture database unavailable');
        await new Promise((r) => setTimeout(r, 100));
        await settle(row, success);
        completed = true;
      });
    try {
      await expect(mail.processBatch()).rejects.toThrow();
      expect(completed).toBe(true);
    } finally {
      spy.mockRestore();
      await db.mailOutbox.deleteMany({
        where: { id: { in: rows.map((r) => r.id) } },
      });
    }
  });
});
