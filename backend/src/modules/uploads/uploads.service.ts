import {
  BadRequestException,
  HttpException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { isUUID } from 'class-validator';
import { fail } from '../../common/errors';
import { PrismaService } from '../../database/prisma.service';
import { lockImage, lockUser, transaction } from '../../common/transaction';
import { normalizeImage } from '../../integrations/storage/image-policy';
import { StorageService } from '../../integrations/storage/storage.service';

const publicFields = {
  id: true,
  mimeType: true,
  size: true,
  width: true,
  height: true,
  createdAt: true,
  expiresAt: true,
  requestKey: true,
} as const;
@Injectable()
export class UploadsService {
  constructor(
    private readonly db: PrismaService,
    private readonly storage: StorageService,
  ) {}
  async upload(
    userId: string,
    file?: Express.Multer.File,
    requestKey?: string,
  ) {
    if (requestKey !== undefined && !isUUID(requestKey, '4'))
      fail(400, 'INVALID_IDEMPOTENCY_KEY', 'Idempotency-Key must be a UUID v4');
    if (!file)
      throw new BadRequestException('One JPEG or PNG file is required');
    const image = await normalizeImage(file.buffer, file.mimetype);
    const sha256 = createHash('sha256').update(image.bytes).digest('hex');
    const id = randomUUID();
    const objectKey =
      'uploads/' +
      userId +
      '/' +
      id +
      (image.contentType === 'image/png' ? '.png' : '.jpg');
    const reserved = await transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      if (requestKey) {
        const prior = await tx.imageAsset.findUnique({
          where: { userId_requestKey: { userId, requestKey } },
        });
        if (prior) {
          if (prior.sha256 !== sha256)
            fail(
              409,
              'IDEMPOTENCY_CONFLICT',
              'Upload key used for different image',
            );
          if (
            prior.deletedAt ||
            prior.purgedAt ||
            prior.expiresAt <= new Date()
          )
            fail(
              409,
              'UPLOAD_UNAVAILABLE',
              'The previous upload is no longer available',
            );
          if (!prior.verifiedAt)
            fail(
              409,
              'UPLOAD_IN_PROGRESS',
              'Retry the same upload key after processing',
            );
          return { row: prior, replay: true };
        }
      }
      const active = await tx.imageAsset.count({
        where: { userId, purgedAt: null },
      });
      const daily = await tx.imageAsset.count({
        where: { userId, createdAt: { gte: new Date(Date.now() - 86400000) } },
      });
      if (active >= 20 || daily >= 100)
        throw new HttpException(
          {
            code: 'IMAGE_QUOTA_EXCEEDED',
            message:
              'Image upload quota reached; delete unused images and wait for cleanup',
          },
          429,
        );
      const row = await tx.imageAsset.create({
        data: {
          id,
          requestKey,
          userId,
          objectKey,
          mimeType: image.contentType,
          size: image.bytes.length,
          width: image.width,
          height: image.height,
          sha256,
          consentAt: new Date(),
          expiresAt: new Date(Date.now() + 86400000),
        },
      });
      return { row, replay: false };
    });
    if (reserved.replay) {
      const row = reserved.row;
      return {
        id: row.id,
        mimeType: row.mimeType,
        size: row.size,
        width: row.width,
        height: row.height,
        createdAt: row.createdAt,
        expiresAt: row.expiresAt,
        requestKey: row.requestKey,
      };
    }
    try {
      return await this.db.$transaction(
        async (tx) => {
          await lockImage(tx, id);
          const latest = await tx.imageAsset.findUniqueOrThrow({
            where: { id },
          });
          if (
            latest.deletedAt ||
            latest.purgedAt ||
            latest.verifiedAt ||
            latest.expiresAt <= new Date() ||
            latest.createdAt.getTime() < Date.now() - 15 * 60000
          )
            throw new Error('UPLOAD_RESERVATION_UNAVAILABLE');
          await this.storage.putImage(objectKey, image);
          return tx.imageAsset.update({
            where: { id: reserved.row.id },
            data: { verifiedAt: new Date() },
            select: publicFields,
          });
        },
        { timeout: 15000 },
      );
    } catch {
      // Reservation survives a storage/transaction failure, including an object
      // accepted by S3 before its response was lost. Cleanup retries this key.
      await this.db.imageAsset
        .update({ where: { id }, data: { deletedAt: new Date() } })
        .catch(() => undefined);
      throw new ServiceUnavailableException({
        code: 'STORAGE_UNAVAILABLE',
        message: 'Unable to store image; please retry later',
      });
    }
  }
  async requestStatus(userId: string, requestKey: string) {
    const row = await this.db.imageAsset.findUnique({
      where: { userId_requestKey: { userId, requestKey } },
      select: {
        ...publicFields,
        verifiedAt: true,
        deletedAt: true,
        purgedAt: true,
      },
    });
    if (!row) return { state: 'missing', image: null };
    if (
      row.deletedAt ||
      row.purgedAt ||
      row.expiresAt <= new Date() ||
      (!row.verifiedAt && row.createdAt.getTime() < Date.now() - 15 * 60000)
    )
      return { state: 'unavailable', image: null };
    if (!row.verifiedAt) return { state: 'processing', image: null };
    const image = {
      id: row.id,
      mimeType: row.mimeType,
      size: row.size,
      width: row.width,
      height: row.height,
      createdAt: row.createdAt,
      expiresAt: row.expiresAt,
      requestKey: row.requestKey,
    };
    return { state: 'available', image };
  }
  async list(userId: string) {
    const items = await this.db.imageAsset.findMany({
      where: {
        userId,
        verifiedAt: { not: null },
        deletedAt: null,
        expiresAt: { gt: new Date() },
      },
      select: publicFields,
      orderBy: { createdAt: 'desc' },
      take: 20,
    });
    return { items };
  }
  async read(userId: string, id: string) {
    return this.db.$transaction(
      async (tx) => {
        await lockImage(tx, id);
        const image = await tx.imageAsset.findFirst({
          where: {
            id,
            userId,
            verifiedAt: { not: null },
            deletedAt: null,
            expiresAt: { gt: new Date() },
          },
          select: publicFields,
        });
        if (!image) throw new NotFoundException();
        return {
          ...image,
          contentPath: 'uploads/images/' + id + '/content',
        };
      },
      { timeout: 20000 },
    );
  }
  async content(userId: string, id: string) {
    return this.db.$transaction(
      async (tx) => {
        await lockImage(tx, id);
        const image = await tx.imageAsset.findFirst({
          where: {
            id,
            userId,
            verifiedAt: { not: null },
            deletedAt: null,
            purgedAt: null,
            expiresAt: { gt: new Date() },
          },
        });
        if (!image) throw new NotFoundException();
        try {
          const bytes = await this.storage.readImage(image.objectKey);
          if (image.expiresAt <= new Date()) throw new NotFoundException();
          return { bytes, contentType: image.mimeType };
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
