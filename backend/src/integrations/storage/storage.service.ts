import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  GetObjectCommand,
  PutObjectCommand,
  DeleteObjectsCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { normalizeImage, NormalizedImage } from './image-policy';
import { MAX_IMAGE_BYTES } from './image-policy';
import { Readable } from 'node:stream';
@Injectable()
export class StorageService implements OnModuleDestroy {
  private readonly client: S3Client;
  private readonly readClient: S3Client;
  private readonly bucket: string;
  constructor(config: ConfigService) {
    this.bucket = config.getOrThrow<string>('S3_BUCKET');
    const options = {
      region: config.getOrThrow<string>('S3_REGION'),
      forcePathStyle: true,
      maxAttempts: 2,
      credentials: {
        accessKeyId: config.getOrThrow<string>('S3_ACCESS_KEY_ID'),
        secretAccessKey: config.getOrThrow<string>('S3_SECRET_ACCESS_KEY'),
      },
    };
    this.client = new S3Client({
      ...options,
      endpoint: config.getOrThrow<string>('S3_ENDPOINT'),
    });
    this.readClient = new S3Client({
      ...options,
      endpoint:
        config.get<string>('S3_PUBLIC_ENDPOINT') ||
        config.getOrThrow<string>('S3_ENDPOINT'),
    });
  }
  signedRead(objectKey: string) {
    return getSignedUrl(
      this.readClient,
      new GetObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
        ResponseCacheControl: 'private, no-store',
        ResponseContentDisposition: 'inline',
      }),
      { expiresIn: 60 },
    );
  }
  async putResult(objectKey: string, bytes: Uint8Array, contentType: string) {
    let image: NormalizedImage;
    try {
      image = await normalizeImage(Buffer.from(bytes), contentType);
    } catch {
      throw new Error('INVALID_PROVIDER_OUTPUT');
    }
    await this.putImage(objectKey, image);
  }
  async putImage(objectKey: string, image: NormalizedImage) {
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
        Body: image.bytes,
        ContentType: image.contentType,
        CacheControl: 'private, no-store',
      }),
      { abortSignal: AbortSignal.timeout(8000) },
    );
  }
  async readImage(objectKey: string) {
    const result = await this.client.send(
      new GetObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
        Range: `bytes=0-${MAX_IMAGE_BYTES}`,
      }),
      { abortSignal: AbortSignal.timeout(8000) },
    );
    const body = result.Body;
    if (!(body instanceof Readable))
      throw new Error('STORAGE_READ_UNAVAILABLE');
    const timer = setTimeout(
      () => body.destroy(new Error('STORAGE_READ_TIMEOUT')),
      8000,
    );
    try {
      const chunks: Buffer[] = [];
      let size = 0;
      for await (const chunk of body) {
        const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
        size += bytes.length;
        if (size > MAX_IMAGE_BYTES) throw new Error('STORAGE_IMAGE_TOO_LARGE');
        chunks.push(bytes);
      }
      return Buffer.concat(chunks);
    } finally {
      clearTimeout(timer);
      body.destroy();
    }
  }
  async deleteObjects(keys: string[]) {
    const unique = [...new Set(keys)];
    for (let start = 0; start < unique.length; start += 500) {
      const result = await this.client.send(
        new DeleteObjectsCommand({
          Bucket: this.bucket,
          Delete: {
            Objects: unique.slice(start, start + 500).map((Key) => ({ Key })),
            Quiet: true,
          },
        }),
        { abortSignal: AbortSignal.timeout(8000) },
      );
      if (result.Errors?.length) throw new Error('STORAGE_DELETE_FAILED');
    }
  }
  onModuleDestroy() {
    this.client.destroy();
    this.readClient.destroy();
  }
}
