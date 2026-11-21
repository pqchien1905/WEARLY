import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { MailOutbox } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { sendLocalMail } from './send-local-mail';
@Injectable()
export class MailService implements OnModuleDestroy {
  private readonly sends = new Set<AbortController>();
  private stopping = false;
  constructor(
    private readonly db: PrismaService,
    private readonly config: ConfigService,
  ) {}
  enabled() {
    return (
      this.config.get<string>('LOCAL_MAIL_ENABLED') === 'true' ||
      this.config.get<string>('MAIL_DELIVERY_ENABLED') === 'true'
    );
  }
  async claim(): Promise<MailOutbox[]> {
    if (!this.enabled() || this.stopping) return [];
    const token = randomUUID();
    return this.db.$transaction(async (tx) => {
      await tx.$executeRaw`UPDATE "MailOutbox" SET "status"='FAILED',"lastError"='MAIL_LEASE_EXHAUSTED',"leaseToken"=NULL,"leaseUntil"=NULL,"updatedAt"=CURRENT_TIMESTAMP
        WHERE "status"='PROCESSING' AND "leaseUntil"<=CURRENT_TIMESTAMP AND "attempts">=5`;
      return tx.$queryRaw<MailOutbox[]>`WITH ready AS (
        SELECT id FROM "MailOutbox" WHERE "attempts"<5 AND
          (("status"='PENDING' AND "nextAttemptAt"<=CURRENT_TIMESTAMP) OR ("status"='PROCESSING' AND "leaseUntil"<=CURRENT_TIMESTAMP))
        ORDER BY "createdAt",id FOR UPDATE SKIP LOCKED LIMIT 10
      ) UPDATE "MailOutbox" m SET "status"='PROCESSING',"attempts"=m."attempts"+1,"leaseToken"=${token}::uuid,
        "leaseUntil"=CURRENT_TIMESTAMP+INTERVAL '120 seconds',"updatedAt"=CURRENT_TIMESTAMP FROM ready WHERE m.id=ready.id RETURNING m.*`;
    });
  }
  async settle(row: MailOutbox, success: boolean) {
    const delay = Math.min(300, 10 * 2 ** (row.attempts - 1));
    await this.db.mailOutbox.updateMany({
      where: { id: row.id, status: 'PROCESSING', leaseToken: row.leaseToken },
      data: {
        status: success ? 'SENT' : row.attempts >= 5 ? 'FAILED' : 'PENDING',
        sentAt: success ? new Date() : null,
        nextAttemptAt: new Date(Date.now() + delay * 1000),
        lastError: success ? null : 'MAIL_DELIVERY_FAILED',
        leaseToken: null,
        leaseUntil: null,
      },
    });
  }
  async processBatch() {
    const rows = await this.claim();
    if (!rows.length) return;
    const results = await Promise.allSettled(
      rows.map(async (row) => {
        let success = false;
        const controller = new AbortController();
        this.sends.add(controller);
        if (this.stopping) controller.abort();
        try {
          await sendLocalMail(
            this.config,
            {
              to: row.recipient,
              subject: row.subject,
              text: row.body,
              messageId: `<${row.id}@wearly.local>`,
            },
            controller.signal,
          );
          success = true;
        } catch {
          /* Store only the fixed error code, never SMTP responses or PII. */
        } finally {
          this.sends.delete(controller);
        }
        await this.settle(row, success);
      }),
    );
    if (results.some((r) => r.status === 'rejected'))
      throw new Error('MAIL_SETTLEMENT_PENDING');
  }
  async overview(query = { page: 1, limit: 10 }) {
    return this.db.$transaction(
      async (tx) => {
        const counts = await tx.mailOutbox.groupBy({
          by: ['status'],
          _count: { _all: true },
        });
        const total = counts.reduce((sum, c) => sum + c._count._all, 0);
        const page = Math.min(
          query.page,
          Math.max(1, Math.ceil(total / query.limit)),
        );
        const items = await tx.mailOutbox.findMany({
          take: query.limit,
          skip: (page - 1) * query.limit,
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
          select: {
            id: true,
            recipient: true,
            subject: true,
            status: true,
            attempts: true,
            lastError: true,
            sentAt: true,
            createdAt: true,
            orderId: true,
            supportId: true,
          },
        });
        return {
          enabled: this.enabled(),
          delivery:
            this.config.get<string>('LOCAL_MAIL_ENABLED') === 'true'
              ? 'local'
              : this.enabled()
                ? 'smtp'
                : null,
          counts: Object.fromEntries(
            counts.map((c) => [c.status, c._count._all]),
          ),
          items,
          total,
          page,
          limit: query.limit,
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  onModuleDestroy() {
    this.stop();
  }
  stop() {
    this.stopping = true;
    for (const controller of this.sends) controller.abort();
  }
}
