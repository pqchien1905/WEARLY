import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
@Injectable()
export class StorageService {
  private readonly client: S3Client;
  private readonly bucket: string;
  constructor(config: ConfigService) {
    this.bucket = config.getOrThrow<string>('S3_BUCKET');
    this.client = new S3Client({
      endpoint: config.getOrThrow<string>('S3_ENDPOINT'),
      region: config.getOrThrow<string>('S3_REGION'),
      forcePathStyle: true,
      credentials: {
        accessKeyId: config.getOrThrow<string>('S3_ACCESS_KEY_ID'),
        secretAccessKey: config.getOrThrow<string>('S3_SECRET_ACCESS_KEY'),
      },
    });
  }
  signedRead(objectKey: string) {
    return getSignedUrl(
      this.client,
      new GetObjectCommand({ Bucket: this.bucket, Key: objectKey }),
      { expiresIn: 60 },
    );
  }
  async putResult(objectKey: string, bytes: Uint8Array, contentType: string) {
    if (
      bytes.length === 0 ||
      bytes.length > 8 * 1024 * 1024 ||
      !['image/jpeg', 'image/png'].includes(contentType)
    )
      throw new Error('INVALID_PROVIDER_OUTPUT');
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
        Body: bytes,
        ContentType: contentType,
      }),
    );
  }
}
