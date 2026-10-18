import {
  BadRequestException,
  HttpException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
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
} as const;
@Injectable()
export class UploadsService {
  constructor(
    private readonly db: PrismaService,
    private readonly storage: StorageService,
  ) {}
  async upload(userId: string, file?: Express.Multer.File) {
    if (!file)
      throw new BadRequestException('One JPEG or PNG file is required');
    const image = await normalizeImage(file.buffer, file.mimetype);
    const id = randomUUID();
    const objectKey =
      'uploads/' +
      userId +
      '/' +
      id +
      (image.contentType === 'image/png' ? '.png' : '.jpg');
    const reserved = await transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
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
      return tx.imageAsset.create({
        data: {
          id,
          userId,
          objectKey,
          mimeType: image.contentType,
          size: image.bytes.length,
          width: image.width,
          height: image.height,
          sha256: createHash('sha256').update(image.bytes).digest('hex'),
          consentAt: new Date(),
          expiresAt: new Date(Date.now() + 86400000),
        },
      });
    });
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
            where: { id: reserved.id },
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
          select: { ...publicFields, objectKey: true },
        });
        if (!image) throw new NotFoundException();
        const { objectKey, ...metadata } = image;
        return {
          ...metadata,
          url: await this.storage.signedRead(objectKey),
          urlExpiresIn: 60,
        };
      },
      { timeout: 20000 },
    );
  }
}
