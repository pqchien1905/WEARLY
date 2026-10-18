import {
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { TryOnProvider } from '../../integrations/ai-providers/try-on.provider';
import { StorageService } from '../../integrations/storage/storage.service';
import { TryOnDto } from './dto/try-on.dto';
@Injectable()
export class AiService {
  constructor(
    private readonly db: PrismaService,
    private readonly provider: TryOnProvider,
    private readonly storage: StorageService,
  ) {}
  async create(userId: string, dto: TryOnDto) {
    if (!this.provider.enabled)
      throw new ServiceUnavailableException({
        code: 'AI_PROVIDER_NOT_CONFIGURED',
        message: 'Try-On provider is not configured',
      });
    return this.db.$transaction(async (tx) => {
      const image = await tx.imageAsset.findFirst({
        where: {
          id: dto.imageId,
          userId,
          verifiedAt: { not: null },
          deletedAt: null,
          expiresAt: { gt: new Date() },
        },
      });
      const variant = await tx.productVariant.findFirst({
        where: {
          sku: dto.sku,
          active: true,
          product: { active: true, tryOnSupported: true },
        },
      });
      if (!image || !variant)
        throw new NotFoundException('Image or eligible SKU not found');
      const job = await tx.aIJob.create({
        data: {
          userId,
          imageId: image.id,
          variantId: variant.id,
          consentAt: new Date(),
          outbox: { create: {} },
        },
      });
      return { id: job.id, status: job.status.toLowerCase() };
    });
  }
  async get(userId: string, id: string) {
    const job = await this.db.aIJob.findFirst({
      where: { id, userId },
      include: { result: true, image: true },
    });
    if (!job) throw new NotFoundException();
    const canRead =
      job.status === 'COMPLETED' &&
      job.result &&
      job.result.expiresAt > new Date() &&
      !job.image.deletedAt &&
      job.image.expiresAt > new Date();
    return {
      id: job.id,
      status: job.status.toLowerCase(),
      errorCode: job.errorCode,
      createdAt: job.createdAt,
      resultUrl: canRead
        ? await this.storage.signedRead(job.result!.objectKey)
        : null,
    };
  }
}
