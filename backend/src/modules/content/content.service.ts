import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { Prisma, StoreContent } from '../../generated/prisma/client';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { recordAdminActivity } from '../admin/audit';
import { ContentVersionDto, SaveContentDto } from './content.dto';

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
        version: row.publishedVersion,
        publishedAt: row.publishedAt,
      }
    : null;
}
function privateContent(row: StoreContent | null) {
  return {
    id: row?.id ?? null,
    banner: row?.banner ?? 'Mặc theo cách bạn.',
    policy: row?.policy ?? '',
    version: row?.version ?? 0,
    published: published(row),
  };
}

@Injectable()
export class ContentService {
  constructor(private readonly db: PrismaService) {}

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
        let row: StoreContent;
        if (dto.expectedVersion === 0) {
          row = await tx.storeContent.create({
            data: { key, banner: dto.banner, policy: dto.policy },
          });
        } else {
          const changed = await tx.storeContent.updateMany({
            where: { key, version: dto.expectedVersion },
            data: {
              banner: dto.banner,
              policy: dto.policy,
              version: { increment: 1 },
            },
          });
          if (!changed.count) conflict();
          row = await tx.storeContent.findUniqueOrThrow({ where: { key } });
        }
        await recordAdminActivity(tx, actorId, 'CONTENT_DRAFT_SAVED', row.id);
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
      const row = await tx.storeContent.findUnique({ where: { key } });
      if (!row || row.version !== dto.expectedVersion) return conflict();
      if (row.publishedVersion === row.version)
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
          publishedVersion: row.version + 1,
          publishedAt: new Date(),
          version: { increment: 1 },
        },
      });
      if (!changed.count) conflict();
      await recordAdminActivity(tx, actorId, 'CONTENT_PUBLISHED', row.id);
      return privateContent(
        await tx.storeContent.findUniqueOrThrow({ where: { key } }),
      );
    });
  }
}
