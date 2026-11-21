import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../database/prisma.service';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { recordAdminActivity } from '../admin/audit';

@Injectable()
export class NewsletterService {
  constructor(
    private readonly db: PrismaService,
    private readonly config: ConfigService,
  ) {}
  async subscriptions(page: number, limit: number) {
    const [items, total, active] = await this.db.$transaction([
      this.db.newsletterSubscription.findMany({
        orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
        skip: (page - 1) * limit,
        take: limit,
        select: {
          id: true,
          email: true,
          consentedAt: true,
          unsubscribedAt: true,
        },
      }),
      this.db.newsletterSubscription.count(),
      this.db.newsletterSubscription.count({ where: { unsubscribedAt: null } }),
    ]);
    return { items, total, active, page, limit };
  }
  async unsubscribe(token: string) {
    await this.db.$transaction(async (tx) => {
      const row = await tx.newsletterSubscription.findUnique({
        where: { unsubscribeToken: token },
      });
      if (!row) return;
      await tx.newsletterSubscription.update({
        where: { id: row.id },
        data: { unsubscribedAt: row.unsubscribedAt ?? new Date() },
      });
      await tx.mailOutbox.updateMany({
        where: {
          subscriptionId: row.id,
          status: { in: ['PENDING', 'HELD', 'FAILED'] },
        },
        data: { status: 'CANCELLED', lastError: 'NEWSLETTER_UNSUBSCRIBED' },
      });
    });
    return { accepted: true };
  }
  async remove(actorId: string, id: string) {
    return transaction(this.db, async (tx) => {
      const row = await tx.newsletterSubscription.findUnique({ where: { id } });
      if (!row) throw new NotFoundException();
      const after = await tx.newsletterSubscription.update({
        where: { id },
        data: { unsubscribedAt: row.unsubscribedAt ?? new Date() },
      });
      await tx.mailOutbox.updateMany({
        where: {
          subscriptionId: id,
          status: { in: ['PENDING', 'HELD', 'FAILED'] },
        },
        data: { status: 'CANCELLED', lastError: 'NEWSLETTER_UNSUBSCRIBED' },
      });
      await recordAdminActivity(tx, actorId, 'NEWSLETTER_UPDATED', id, {
        before: row,
        after,
      });
      return { id, unsubscribedAt: after.unsubscribedAt };
    });
  }
  campaigns() {
    return this.db.newsletterCampaign.findMany({
      orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
      take: 100,
      include: { _count: { select: { mail: true } } },
    });
  }
  save(
    actorId: string,
    dto: { requestKey: string; subject: string; body: string },
  ) {
    return transaction(
      this.db,
      async (tx) => {
        await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended(${dto.requestKey},0))::text`;
        const previous = await tx.newsletterCampaign.findUnique({
          where: { requestKey: dto.requestKey },
        });
        if (previous) {
          if (previous.subject !== dto.subject || previous.body !== dto.body)
            fail(409, 'IDEMPOTENCY_CONFLICT', 'Campaign draft differs');
          return previous;
        }
        const row = await tx.newsletterCampaign.create({ data: dto });
        await recordAdminActivity(tx, actorId, 'NEWSLETTER_UPDATED', row.id, {
          after: row,
        });
        return row;
      },
      'ReadCommitted',
    );
  }
  queue(actorId: string, id: string, expectedVersion: number) {
    return transaction(this.db, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "NewsletterCampaign" WHERE id=${id}::uuid FOR UPDATE`;
      const row = await tx.newsletterCampaign.findUnique({ where: { id } });
      if (!row) throw new NotFoundException();
      if (row.queuedAt) return row; // Retrying never duplicates messages.
      if (row.version !== expectedVersion)
        fail(409, 'VERSION_CONFLICT', 'Reload campaign');
      const subscribers = await tx.newsletterSubscription.findMany({
        where: { unsubscribedAt: null },
        take: 10001,
      });
      if (!subscribers.length)
        fail(409, 'NEWSLETTER_EMPTY', 'Chưa có người đồng ý nhận tin.');
      if (subscribers.length > 10000)
        fail(
          409,
          'NEWSLETTER_BATCH_LIMIT',
          'Campaign exceeds the 10,000 recipient limit',
        );
      const origin = this.config.getOrThrow<string>('LOCAL_STORE_ORIGIN');
      await tx.mailOutbox.createMany({
        data: subscribers.map((s) => ({
          eventKey: `newsletter:${id}:${s.id}`,
          recipient: s.email,
          subject: row.subject,
          body: `${row.body}\n\nBạn nhận thư vì đã đăng ký nhận tin Wearly.\nHủy đăng ký: ${origin}/#/newsletter/unsubscribe?token=${s.unsubscribeToken}`,
          subscriptionId: s.id,
          campaignId: id,
        })),
      });
      const after = await tx.newsletterCampaign.update({
        where: { id },
        data: {
          queuedAt: new Date(),
          version: { increment: 1 },
          recipientCount: subscribers.length,
        },
      });
      await recordAdminActivity(tx, actorId, 'NEWSLETTER_QUEUED', id, {
        before: row,
        after,
      });
      return after;
    });
  }
}
