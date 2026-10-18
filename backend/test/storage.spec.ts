import { ConfigService } from '@nestjs/config';
import { StorageService } from '../src/integrations/storage/storage.service';
describe('Private storage URLs', () => {
  it('signs the client-reachable endpoint separately from the container endpoint', async () => {
    const storage = new StorageService(
      new ConfigService({
        S3_ENDPOINT: 'http://minio:9000',
        S3_PUBLIC_ENDPOINT: 'https://images.example.test',
        S3_REGION: 'us-east-1',
        S3_BUCKET: 'private',
        S3_ACCESS_KEY_ID: 'test-access',
        S3_SECRET_ACCESS_KEY: 'test-secret',
      }),
    );
    try {
      const url = new URL(await storage.signedRead('uploads/owned/image.jpg'));
      expect(url.origin).toBe('https://images.example.test');
      expect(url.searchParams.get('X-Amz-Expires')).toBe('60');
      expect(url.searchParams.get('response-cache-control')).toBe(
        'private, no-store',
      );
    } finally {
      storage.onModuleDestroy();
    }
  });
});
