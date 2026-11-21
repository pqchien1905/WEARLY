import { Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { isUUID } from 'class-validator';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { TryOnProvider } from '../../integrations/ai-providers/try-on.provider';
import { GarmentReader } from '../../integrations/ai-providers/garment-reader.service';
import { StorageService } from '../../integrations/storage/storage.service';
import { TryOnDto } from './dto/try-on.dto';
import { AiUsageService } from './ai-usage.service';
import { lockImage } from '../../common/transaction';
import { fail } from '../../common/errors';

const detail = {
  usage: true,
  variant: {
    include: {
      product: {
        select: {
          name: true,
          slug: true,
          active: true,
          tryOnSupported: true,
          images: {
            orderBy: { position: 'asc' },
            select: { url: true, color: true },
          },
        },
      },
    },
  },
  image: true,
  result: true,
} as const;
type JobDetail = Prisma.AIJobGetPayload<{ include: typeof detail }>;
const readable = (row: JobDetail) =>
  Boolean(
    row.status === 'COMPLETED' &&
    row.result &&
    row.result.expiresAt > new Date() &&
    row.image.verifiedAt &&
    !row.image.deletedAt &&
    !row.image.purgedAt &&
    row.image.expiresAt > new Date(),
  );

@Injectable()
export class AiService {
  constructor(
    private readonly db: PrismaService,
    private readonly provider: TryOnProvider,
    private readonly storage: StorageService,
    private readonly usage: AiUsageService,
    private readonly garments: GarmentReader,
  ) {}
  async status(userId: string) {
    await this.usage.cleanup();
    return {
      configured: this.provider.enabled,
      model: this.provider.model,
      ...(await this.usage.status(userId, 'TRY_ON')),
    };
  }
  async create(userId: string, key: string | undefined, dto: TryOnDto) {
    if (!key || !isUUID(key, '4'))
      fail(400, 'INVALID_IDEMPOTENCY_KEY', 'Idempotency-Key must be a UUID v4');
    const hash = createHash('sha256')
      .update(
        JSON.stringify({
          imageId: dto.imageId,
          sku: dto.sku.trim(),
          consent: true,
        }),
      )
      .digest('hex');
    await this.usage.cleanup();
    const prior = await this.db.aiUsage.findUnique({
      where: {
        userId_kind_requestKey: { userId, kind: 'TRY_ON', requestKey: key },
      },
    });
    if (prior) {
      if (prior.inputHash !== hash)
        fail(
          409,
          'IDEMPOTENCY_CONFLICT',
          'Request key used with different input',
        );
      const job = await this.db.aIJob.findUnique({
        where: { usageId: prior.id },
      });
      if (!job)
        fail(
          409,
          'AI_REQUEST_UNAVAILABLE',
          'Previous job is no longer available',
        );
      return this.get(userId, job.id);
    }
    if (!this.provider.enabled)
      fail(
        503,
        'AI_PROVIDER_NOT_CONFIGURED',
        'Try-On provider is not configured',
      );
    const id = await this.db.$transaction(
      async (tx) => {
        const reserved = await this.usage.reserveTx(
          tx,
          userId,
          'TRY_ON',
          key,
          hash,
          this.provider.model,
        );
        if (!reserved.isNew) {
          const old = await tx.aIJob.findUnique({
            where: { usageId: reserved.row.id },
          });
          if (!old)
            fail(
              409,
              'AI_REQUEST_UNAVAILABLE',
              'Previous job is no longer available',
            );
          return old.id;
        }
        await lockImage(tx, dto.imageId);
        const image = await tx.imageAsset.findFirst({
          where: {
            id: dto.imageId,
            userId,
            verifiedAt: { not: null },
            consentAt: { not: null },
            deletedAt: null,
            purgedAt: null,
            expiresAt: { gt: new Date() },
          },
        });
        const variant = await tx.productVariant.findFirst({
          where: {
            sku: dto.sku.trim(),
            active: true,
            inventory: { quantity: { gt: 0 } },
            product: { active: true, tryOnSupported: true },
          },
        });
        if (!image || !variant)
          throw new NotFoundException('Image or eligible SKU not found');
        if ((await tx.aIJob.count({ where: { imageId: image.id } })) >= 20)
          fail(
            429,
            'AI_IMAGE_QUOTA_EXCEEDED',
            'Try-On job limit reached for this image',
          );
        let garmentRef: string;
        try {
          garmentRef = await this.garments.resolve(
            variant.productId,
            variant.color,
            tx,
          );
        } catch {
          fail(
            409,
            'AI_GARMENT_UNAVAILABLE',
            'No eligible garment image is available',
          );
        }
        await tx.aiUsage.update({
          where: { id: reserved.row.id },
          data: { expiresAt: image.expiresAt },
        });
        return (
          await tx.aIJob.create({
            data: {
              userId,
              imageId: image.id,
              variantId: variant.id,
              consentAt: new Date(),
              usageId: reserved.row.id,
              garmentRef,
              outbox: { create: {} },
            },
          })
        ).id;
      },
      { timeout: 20000 },
    );
    return this.get(userId, id);
  }
  private present(row: JobDetail) {
    const resultAvailable = readable(row);
    return {
      id: row.id,
      requestKey: row.usage?.requestKey ?? null,
      status: row.status.toLowerCase(),
      errorCode:
        row.errorCode ??
        (row.status === 'COMPLETED' && !resultAvailable
          ? 'AI_RESULT_EXPIRED'
          : null),
      imageId: row.imageId,
      sku: row.variant.sku,
      size: row.variant.size,
      color: row.variant.color,
      product: row.variant.product.active
        ? {
            name: row.variant.product.name,
            slug: row.variant.product.slug,
            image:
              (
                row.variant.product.images.find(
                  (image) => image.color === row.variant.color,
                ) ?? row.variant.product.images[0]
              )?.url ?? null,
            tryOnSupported:
              row.variant.active && row.variant.product.tryOnSupported,
          }
        : null,
      createdAt: row.createdAt,
      expiresAt: row.image.expiresAt,
      estimatedCostVnd: row.usage?.estimatedCostVnd.toString() ?? '0',
      resultAvailable,
      resultContentPath: resultAvailable
        ? 'ai/try-on/jobs/' + row.id + '/result'
        : null,
    };
  }
  async list(userId: string) {
    await this.usage.cleanup();
    const rows = await this.db.aIJob.findMany({
      where: {
        userId,
        image: { deletedAt: null },
        createdAt: { gte: new Date(Date.now() - 86400000) },
      },
      include: detail,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: 20,
    });
    return { items: rows.map((row) => this.present(row)) };
  }
  async get(userId: string, id: string) {
    await this.usage.cleanup();
    const row = await this.db.aIJob.findFirst({
      where: { id, userId },
      include: detail,
    });
    if (!row) throw new NotFoundException();
    return this.present(row);
  }
  async result(userId: string, id: string) {
    const owned = await this.db.aIJob.findFirst({
      where: { id, userId },
      select: { imageId: true },
    });
    if (!owned) throw new NotFoundException();
    return this.db.$transaction(
      async (tx) => {
        await lockImage(tx, owned.imageId);
        const row = await tx.aIJob.findFirst({
          where: { id, userId },
          include: detail,
        });
        if (!row || !readable(row)) throw new NotFoundException();
        try {
          const bytes = await this.storage.readImage(row.result!.objectKey);
          if (!readable(row)) throw new NotFoundException();
          return {
            bytes,
            contentType: bytes[0] === 137 ? 'image/png' : 'image/jpeg',
          };
        } catch (e) {
          if (e instanceof NotFoundException) throw e;
          fail(
            503,
            'STORAGE_UNAVAILABLE',
            'Private image is temporarily unavailable',
          );
        }
      },
      { timeout: 20000 },
    );
  }
}
