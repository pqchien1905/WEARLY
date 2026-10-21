import { Inject, Injectable, Optional } from '@nestjs/common';
import { open, realpath } from 'node:fs/promises';
import path from 'node:path';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { managedImagePattern } from '../../modules/catalog-media/catalog-reference';
import { StorageService } from '../storage/storage.service';
import {
  MAX_IMAGE_BYTES,
  normalizeImage,
  NormalizedImage,
} from '../storage/image-policy';
export const TRYON_ASSET_ROOT = Symbol('TRYON_ASSET_ROOT');
const seed = /^assets\/images\/([a-zA-Z0-9_-]+\.(?:jpg|jpeg|png))$/;

@Injectable()
export class GarmentReader {
  private readonly root: string;
  constructor(
    private readonly db: PrismaService,
    private readonly storage: StorageService,
    @Optional() @Inject(TRYON_ASSET_ROOT) root?: string,
  ) {
    this.root =
      root ?? path.resolve(__dirname, '../../../../frontend/assets/images');
  }
  private asset(
    db: PrismaService | Prisma.TransactionClient,
    id: string,
    productId: string,
  ) {
    return db.catalogAsset.findFirst({
      where: {
        id,
        productId,
        verifiedAt: { not: null },
        deletedAt: null,
        purgedAt: null,
      },
    });
  }
  async resolve(
    productId: string,
    color: string,
    db: PrismaService | Prisma.TransactionClient = this.db,
  ): Promise<string> {
    const images = await db.productImage.findMany({
      where: { productId, OR: [{ color }, { color: null }] },
      orderBy: [{ position: 'asc' }, { id: 'asc' }],
    });
    const ordered = [
      ...images.filter((i) => i.color === color),
      ...images.filter((i) => i.color === null),
    ];
    for (const image of ordered) {
      if (seed.test(image.url)) return image.url;
      const match = managedImagePattern.exec(image.url);
      if (match && (await this.asset(db, match[1], productId)))
        return image.url;
    }
    throw new Error('AI_GARMENT_UNAVAILABLE');
  }
  async read(ref: string, productId: string): Promise<NormalizedImage> {
    try {
      const managed = managedImagePattern.exec(ref);
      if (managed) {
        const asset = await this.asset(this.db, managed[1], productId);
        if (!asset) throw new Error('Missing garment');
        return await normalizeImage(
          await this.storage.readImage(asset.objectKey),
          asset.mimeType,
        );
      }
      const name = seed.exec(ref)?.[1];
      if (!name) throw new Error('Invalid garment');
      const root = await realpath(this.root),
        file = await realpath(path.join(root, name));
      const relative = path.relative(root, file);
      if (!relative || relative.startsWith('..') || path.isAbsolute(relative))
        throw new Error('Outside garment directory');
      const handle = await open(file, 'r');
      try {
        const stat = await handle.stat();
        if (!stat.isFile() || stat.size < 1 || stat.size > MAX_IMAGE_BYTES)
          throw new Error('Invalid garment file');
        const bytes = Buffer.alloc(MAX_IMAGE_BYTES + 1);
        let bytesRead = 0;
        while (bytesRead < bytes.length) {
          const part = await handle.read(
            bytes,
            bytesRead,
            bytes.length - bytesRead,
            bytesRead,
          );
          if (!part.bytesRead) break;
          bytesRead += part.bytesRead;
        }
        if (bytesRead > MAX_IMAGE_BYTES) throw new Error('Large garment');
        return await normalizeImage(
          bytes.subarray(0, bytesRead),
          name.endsWith('.png') ? 'image/png' : 'image/jpeg',
        );
      } finally {
        await handle.close();
      }
    } catch {
      throw new Error('AI_GARMENT_UNAVAILABLE');
    }
  }
}
