import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { isUUID } from 'class-validator';
import { PrismaService } from '../../database/prisma.service';
import { lockImage, lockUser, transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { StorageService } from '../../integrations/storage/storage.service';
import { normalizeImage } from '../../integrations/storage/image-policy';
import { recordAdminActivity } from '../admin/audit';
import { catalogReference } from './catalog-reference';
const digest = (value: Buffer | string) =>
  createHash('sha256').update(value).digest('hex');
@Injectable()
export class CatalogMediaService {
  private readonly logger = new Logger(CatalogMediaService.name);
  constructor(
    private readonly db: PrismaService,
    private readonly storage: StorageService,
  ) {}
  async upload(
    actorId: string,
    productId: string,
    requestKey: string | undefined,
    metadata: { alt: string; color?: string },
    file?: Express.Multer.File,
  ) {
    if (typeof requestKey !== 'string' || !isUUID(requestKey, '4'))
      throw new BadRequestException('Idempotency-Key must be a UUID v4');
    if (!file)
      throw new BadRequestException('One JPEG or PNG file is required');
    const inputHash = digest(
      JSON.stringify({
        productId,
        bytes: digest(file.buffer),
        mimeType: file.mimetype,
        alt: metadata.alt,
        color: metadata.color ?? null,
      }),
    );
    // Normalization is outside the database transaction and cannot be replayed
    // as part of a serializable retry. Only the first reservation owner writes S3.
    const image = await normalizeImage(file.buffer, file.mimetype);
    const reserved = await transaction(this.db, async (tx) => {
      await lockUser(tx, actorId);
      const prior = await tx.catalogAsset.findUnique({
        where: { actorId_requestKey: { actorId, requestKey } },
      });
      if (prior) {
        if (prior.inputHash !== inputHash)
          fail(
            409,
            'IDEMPOTENCY_CONFLICT',
            'Upload key was used for different input',
          );
        if (prior.verifiedAt) return { asset: prior, replay: true };
        if (prior.deletedAt)
          fail(
            409,
            'UPLOAD_FAILED',
            'Previous upload failed; reload the product before starting another upload',
          );
        fail(
          409,
          'UPLOAD_IN_PROGRESS',
          'Upload is still processing; retry with the same key',
        );
      }
      const product = await tx.$queryRaw<
        { id: string }[]
      >`SELECT id FROM "Product" WHERE id=${productId}::uuid FOR UPDATE`;
      if (!product.length) throw new NotFoundException();
      const count = await tx.productImage.count({ where: { productId } });
      const pending = await tx.catalogAsset.count({
        where: { productId, verifiedAt: null, deletedAt: null },
      });
      if (count + pending >= 20)
        fail(409, 'GALLERY_FULL', 'A product can have at most 20 images');
      const id = randomUUID();
      const asset = await tx.catalogAsset.create({
        data: {
          id,
          productId,
          actorId,
          requestKey,
          inputHash,
          objectKey: `catalog/${id}${image.contentType === 'image/png' ? '.png' : '.jpg'}`,
          sha256: digest(image.bytes),
          mimeType: image.contentType,
          size: image.bytes.length,
          width: image.width,
          height: image.height,
        },
      });
      return { asset, replay: false };
    });
    if (reserved.replay) return reserved.asset.receipt;
    const id = reserved.asset.id;
    try {
      return await this.db.$transaction(
        async (tx) => {
          await lockImage(tx, id);
          const asset = await tx.catalogAsset.findUniqueOrThrow({
            where: { id },
          });
          if (
            asset.deletedAt ||
            asset.purgedAt ||
            asset.verifiedAt ||
            asset.createdAt.getTime() < Date.now() - 15 * 60000
          )
            throw new Error('UPLOAD_RESERVATION_UNAVAILABLE');
          await this.storage.putImage(asset.objectKey, image);
          const product = await tx.$queryRaw<
            { id: string }[]
          >`SELECT id FROM "Product" WHERE id=${productId}::uuid FOR UPDATE`;
          if (!product.length) throw new NotFoundException();
          const count = await tx.productImage.count({ where: { productId } });
          if (count >= 20)
            fail(409, 'GALLERY_FULL', 'A product can have at most 20 images');
          const receipt = {
            id,
            productId,
            url: catalogReference(id),
            alt: metadata.alt,
            color: metadata.color ?? null,
            mimeType: image.contentType,
            size: image.bytes.length,
            width: image.width,
            height: image.height,
          };
          await tx.productImage.create({
            data: {
              productId,
              url: receipt.url,
              alt: metadata.alt,
              color: metadata.color,
              position: count,
            },
          });
          await tx.catalogAsset.update({
            where: { id },
            data: { verifiedAt: new Date(), receipt },
          });
          await recordAdminActivity(
            tx,
            actorId,
            'PRODUCT_IMAGE_UPLOADED',
            productId,
          );
          return receipt;
        },
        { timeout: 20000 },
      );
    } catch {
      // Never downgrade a verified record after an ambiguous database response.
      await this.db.catalogAsset
        .updateMany({
          where: { id, verifiedAt: null, deletedAt: null },
          data: { deletedAt: new Date() },
        })
        .catch(() => undefined);
      throw new ServiceUnavailableException({
        code: 'CATALOG_UPLOAD_UNCERTAIN',
        message: 'Reload the product or retry with the same upload key',
      });
    }
  }
  async read(id: string) {
    const asset = await this.db.catalogAsset.findFirst({
      where: { id, verifiedAt: { not: null }, deletedAt: null },
    });
    if (!asset) throw new NotFoundException();
    try {
      const bytes = await this.storage.readImage(asset.objectKey);
      if (bytes.length !== asset.size || digest(bytes) !== asset.sha256)
        throw new Error('CATALOG_IMAGE_CORRUPT');
      return { bytes, mimeType: asset.mimeType };
    } catch {
      throw new ServiceUnavailableException({
        code: 'STORAGE_UNAVAILABLE',
        message: 'Image is temporarily unavailable',
      });
    }
  }
  async purge(id: string) {
    const key = await this.db.$transaction(
      async (tx) => {
        await lockImage(tx, id);
        const asset = await tx.catalogAsset.findUnique({ where: { id } });
        if (
          !asset ||
          asset.verifiedAt ||
          (!asset.deletedAt &&
            asset.createdAt.getTime() >= Date.now() - 15 * 60000)
        )
          return null;
        await tx.catalogAsset.update({
          where: { id },
          data: { deletedAt: asset.deletedAt ?? new Date() },
        });
        return asset.objectKey;
      },
      { timeout: 20000 },
    );
    if (!key) return;
    await this.storage.deleteObjects([key]);
    await this.db.catalogAsset.update({
      where: { id },
      data: {
        purgedAt: new Date(),
        purgeRetryAt: new Date(Date.now() + 86400000),
      },
    });
  }
  async purgeExpired() {
    const candidates = await this.db.catalogAsset.findMany({
      where: {
        verifiedAt: null,
        AND: [
          {
            OR: [{ purgeRetryAt: null }, { purgeRetryAt: { lte: new Date() } }],
          },
        ],
        OR: [
          { deletedAt: { not: null } },
          { createdAt: { lt: new Date(Date.now() - 15 * 60000) } },
        ],
      },
      orderBy: [
        { purgeRetryAt: { sort: 'asc', nulls: 'first' } },
        { createdAt: 'asc' },
      ],
      take: 50,
      select: { id: true },
    });
    for (const candidate of candidates) {
      try {
        await this.purge(candidate.id);
      } catch {
        await this.db.catalogAsset.update({
          where: { id: candidate.id },
          data: {
            purgeRetryAt: new Date(Date.now() + 5 * 60000),
          },
        });
        this.logger.warn('CATALOG_PURGE_RETRY_PENDING');
      }
    }
  }
}
