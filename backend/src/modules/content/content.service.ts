import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { Prisma, StoreContent } from '../../generated/prisma/client';
import { can } from '../../common/permissions';
import { PageDto } from '../products/dto/query-products.dto';
import { transaction, lockUser } from '../../common/transaction';
import { fail } from '../../common/errors';
import { recordAdminActivity } from '../admin/audit';
import { ContentVersionDto, SaveContentDto } from './content.dto';
import { storeDetails } from './store-details';

const key = 'storefront';
const conflict = () =>
  fail(
    409,
    'VERSION_CONFLICT',
    'Content changed. Reload before saving or publishing.',
  );
const publishedSelect = {
  publishedBanner: true,
  publishedPolicy: true,
  publishedDetails: true,
  publishedVersion: true,
  publishedAt: true,
} as const;
function published(
  row: Pick<StoreContent, keyof typeof publishedSelect> | null,
) {
  return row?.publishedAt
    ? {
        banner: row.publishedBanner,
        policy: row.publishedPolicy,
        details: storeDetails(row.publishedDetails),
        version: row.publishedVersion,
        publishedAt: row.publishedAt,
      }
    : null;
}
function hasChanges(row: StoreContent | null) {
  if (!row?.publishedAt) return true;
  const draft = storeDetails(row.details),
    live = storeDetails(row.publishedDetails);
  return (
    row.banner !== row.publishedBanner ||
    row.policy !== row.publishedPolicy ||
    Object.keys(draft).some(
      (k) => draft[k as keyof typeof draft] !== live[k as keyof typeof live],
    )
  );
}
function privateContent(row: StoreContent | null) {
  return {
    id: row?.id ?? null,
    banner: row?.banner ?? 'Mặc theo cách bạn.',
    policy: row?.policy ?? '',
    details: storeDetails(row?.details),
    version: row?.version ?? 0,
    published: published(row),
    createdAt: row?.createdAt ?? null,
    updatedAt: row?.updatedAt ?? null,
    hasUnpublishedChanges: hasChanges(row),
  };
}

@Injectable()
export class ContentService {
  constructor(private readonly db: PrismaService) {}

  private async lock(tx: Prisma.TransactionClient, actorId: string) {
    await lockUser(tx, actorId);
    const actor = await tx.user.findUnique({
      where: { id: actorId },
      select: { role: true, active: true },
    });
    if (!actor?.active || !can(actor.role, 'content.manage'))
      fail(403, 'FORBIDDEN', 'Không có quyền quản lý nội dung.');
    await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended('content:storefront',0))::text`;
  }
  history(q: PageDto) {
    return this.db.$transaction(
      async (tx) => {
        const row = await tx.storeContent.findUnique({
          where: { key },
          select: { id: true },
        });
        if (!row) return { items: [], total: 0, page: 1, limit: q.limit };
        const where: Prisma.AdminAuditEventWhereInput = {
          targetId: row.id,
          action: {
            in: [
              'CONTENT_DRAFT_SAVED',
              'CONTENT_PUBLISHED',
              'CONTENT_DRAFT_RESTORED',
            ],
          },
        };
        const total = await tx.adminAuditEvent.count({ where });
        const page = Math.min(q.page, Math.max(1, Math.ceil(total / q.limit)));
        const items = await tx.adminAuditEvent.findMany({
          where,
          orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
          skip: (page - 1) * q.limit,
          take: q.limit,
          select: {
            id: true,
            action: true,
            actorId: true,
            createdAt: true,
            details: true,
          },
        });
        return { items, total, page, limit: q.limit };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  restore(actorId: string, dto: ContentVersionDto) {
    return transaction(this.db, async (tx) => {
      await this.lock(tx, actorId);
      const before = await tx.storeContent.findUnique({ where: { key } });
      if (!before || before.version !== dto.expectedVersion) return conflict();
      if (
        !before.publishedAt ||
        before.publishedBanner === null ||
        before.publishedPolicy === null
      )
        fail(
          409,
          'CONTENT_NOT_PUBLISHED',
          'Chưa có bản công khai để khôi phục.',
        );
      if (!hasChanges(before))
        fail(409, 'CONTENT_UNCHANGED', 'Bản nháp đã giống nội dung công khai.');
      const row = await tx.storeContent.update({
        where: { key },
        data: {
          banner: before.publishedBanner,
          policy: before.publishedPolicy,
          details: before.publishedDetails ?? Prisma.DbNull,
          version: { increment: 1 },
        },
      });
      await recordAdminActivity(tx, actorId, 'CONTENT_DRAFT_RESTORED', row.id, {
        before,
        after: row,
      });
      return privateContent(row);
    });
  }
  async subscribe(email: string) {
    // Same acknowledgement for existing/new subscribers. Repeated submissions
    // preserve the original consent and never enqueue unsolicited email.
    await this.db.newsletterSubscription.createMany({
      data: [{ email }],
      skipDuplicates: true,
    });
    return { accepted: true };
  }

  async readPublished() {
    return {
      content: published(
        await this.db.storeContent.findUnique({
          where: { key },
          select: publishedSelect,
        }),
      ),
    };
  }
  async readDraft() {
    return privateContent(
      await this.db.storeContent.findUnique({ where: { key } }),
    );
  }
  async save(actorId: string, dto: SaveContentDto) {
    try {
      return await transaction(this.db, async (tx) => {
        await this.lock(tx, actorId);
        const before = await tx.storeContent.findUnique({ where: { key } });
        let row: StoreContent;
        if (dto.expectedVersion === 0) {
          row = await tx.storeContent.create({
            data: {
              key,
              banner: dto.banner,
              policy: dto.policy,
              ...(dto.details === undefined
                ? {}
                : { details: { ...dto.details } }),
            },
          });
        } else {
          const changed = await tx.storeContent.updateMany({
            where: { key, version: dto.expectedVersion },
            data: {
              banner: dto.banner,
              policy: dto.policy,
              ...(dto.details === undefined
                ? {}
                : { details: { ...dto.details } }),
              version: { increment: 1 },
            },
          });
          if (!changed.count) conflict();
          row = await tx.storeContent.findUniqueOrThrow({ where: { key } });
        }
        await recordAdminActivity(tx, actorId, 'CONTENT_DRAFT_SAVED', row.id, {
          before,
          after: row,
        });
        return privateContent(row);
      });
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      )
        conflict();
      throw error;
    }
  }
  publish(actorId: string, dto: ContentVersionDto) {
    return transaction(this.db, async (tx) => {
      await this.lock(tx, actorId);
      const row = await tx.storeContent.findUnique({ where: { key } });
      if (!row || row.version !== dto.expectedVersion) return conflict();
      if (row.publishedVersion === row.version || !hasChanges(row))
        fail(
          409,
          'ALREADY_PUBLISHED',
          'This saved content is already published.',
        );
      const changed = await tx.storeContent.updateMany({
        where: { key, version: dto.expectedVersion },
        data: {
          publishedBanner: row.banner,
          publishedPolicy: row.policy,
          publishedDetails: row.details ?? Prisma.DbNull,
          publishedVersion: row.version + 1,
          publishedAt: new Date(),
          version: { increment: 1 },
        },
      });
      if (!changed.count) conflict();
      await recordAdminActivity(tx, actorId, 'CONTENT_PUBLISHED', row.id, {
        before: row,
        after: { version: row.version + 1, publishedVersion: row.version + 1 },
      });
      return privateContent(
        await tx.storeContent.findUniqueOrThrow({ where: { key } }),
      );
    });
  }
}
