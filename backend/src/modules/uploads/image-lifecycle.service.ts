import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { lockImage } from '../../common/transaction';
import { StorageService } from '../../integrations/storage/storage.service';
@Injectable()
export class ImageLifecycleService {
  private readonly logger = new Logger('ImageCleanup');
  constructor(
    private readonly db: PrismaService,
    private readonly storage: StorageService,
  ) {}
  async purge(id: string): Promise<boolean> {
    // Commit revocation before the external delete. A failed/partial S3 delete
    // leaves a durable tombstone, and publication uses the same image lock.
    const keys = await this.db.$transaction(
      async (tx) => {
        await lockImage(tx, id);
        const image = await tx.imageAsset.findUnique({
          where: { id },
          include: { jobs: { include: { result: true } } },
        });
        if (!image) return null;
        const stale =
          !image.verifiedAt &&
          image.createdAt.getTime() < Date.now() - 15 * 60000;
        if (!image.deletedAt && image.expiresAt > new Date() && !stale)
          return null;
        if (!image.deletedAt)
          await tx.imageAsset.update({
            where: { id },
            data: { deletedAt: new Date() },
          });
        await tx.aIJob.updateMany({
          where: { imageId: id, status: { in: ['PENDING', 'PROCESSING'] } },
          data: { status: 'FAILED', errorCode: 'IMAGE_UNAVAILABLE' },
        });
        await tx.aiUsage.updateMany({
          where: {
            job: { imageId: id },
            status: { in: ['RESERVED', 'PROCESSING'] },
          },
          data: {
            status: 'FAILED',
            errorCode: 'IMAGE_UNAVAILABLE',
            finishedAt: new Date(),
          },
        });
        return [
          image.objectKey,
          ...image.jobs.flatMap((job) => [
            'results/' + job.userId + '/' + job.id,
            ...(job.result ? [job.result.objectKey] : []),
          ]),
        ];
      },
      { timeout: 20000 },
    );
    if (!keys) return false;
    await this.storage.deleteObjects(keys);
    await this.db.imageAsset.update({
      where: { id },
      // A provider can complete a previously accepted PUT after DELETE.
      // Keep the revoked tombstone eligible for periodic reconciliation.
      data: {
        purgedAt: new Date(),
        purgeRetryAt: new Date(Date.now() + 86400000),
      },
    });
    return true;
  }
  async purgeExpired() {
    const candidates = await this.db.imageAsset.findMany({
      where: {
        AND: [
          {
            OR: [{ purgeRetryAt: null }, { purgeRetryAt: { lte: new Date() } }],
          },
        ],
        OR: [
          { deletedAt: { not: null } },
          { expiresAt: { lte: new Date() } },
          {
            verifiedAt: null,
            createdAt: { lt: new Date(Date.now() - 15 * 60000) },
          },
        ],
      },
      // Never-attempted work first, then oldest retry, so failing early objects
      // cannot monopolize every batch regardless of backlog size.
      orderBy: [
        { purgedAt: { sort: 'asc', nulls: 'first' } },
        { purgeRetryAt: { sort: 'asc', nulls: 'first' } },
        { expiresAt: 'asc' },
      ],
      take: 50,
      select: { id: true },
    });
    for (const candidate of candidates) {
      try {
        await this.purge(candidate.id);
      } catch {
        await this.db.imageAsset.update({
          where: { id: candidate.id },
          data: { purgeRetryAt: new Date(Date.now() + 5 * 60000) },
        });
        this.logger.warn('IMAGE_PURGE_RETRY_PENDING');
      }
    }
  }
  async deleteOwned(userId: string, id: string) {
    return this.db.$transaction(
      async (tx) => {
        await lockImage(tx, id);
        const image = await tx.imageAsset.findFirst({ where: { id, userId } });
        if (!image) throw new NotFoundException();
        if (!image.deletedAt)
          await tx.imageAsset.update({
            where: { id },
            data: { deletedAt: new Date() },
          });
        await tx.aIJob.updateMany({
          where: { imageId: id, status: { in: ['PENDING', 'PROCESSING'] } },
          data: { status: 'FAILED', errorCode: 'IMAGE_UNAVAILABLE' },
        });
        await tx.aiUsage.updateMany({
          where: {
            job: { imageId: id },
            status: { in: ['RESERVED', 'PROCESSING'] },
          },
          data: {
            status: 'FAILED',
            errorCode: 'IMAGE_UNAVAILABLE',
            finishedAt: new Date(),
          },
        });
        return { id, deleted: true };
      },
      { timeout: 20000 },
    );
  }
}
