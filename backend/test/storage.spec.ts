import { ConfigService } from '@nestjs/config';
import { StorageService } from '../src/integrations/storage/storage.service';
import { createServer } from 'node:http';
import { AddressInfo } from 'node:net';
import { MAX_IMAGE_BYTES } from '../src/integrations/storage/image-policy';
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
  it('bounds S3 response bytes and closes a stalled response body', async () => {
    let mode: 'oversized' | 'stalled' = 'oversized';
    const ranges: string[] = [];
    const server = createServer((req, res) => {
      ranges.push(req.headers.range ?? '');
      res.writeHead(200, { 'Content-Type': 'image/jpeg' });
      if (mode === 'oversized') res.end(Buffer.alloc(MAX_IMAGE_BYTES + 1));
      else {
        res.write(Buffer.from([255, 216, 255]));
      }
    });
    await new Promise<void>((resolve) =>
      server.listen(0, '127.0.0.1', resolve),
    );
    const storage = new StorageService(
      new ConfigService({
        S3_ENDPOINT: `http://127.0.0.1:${(server.address() as AddressInfo).port}`,
        S3_REGION: 'us-east-1',
        S3_BUCKET: 'synthetic-test',
        S3_ACCESS_KEY_ID: 'synthetic',
        S3_SECRET_ACCESS_KEY: 'synthetic',
      }),
    );
    try {
      await expect(storage.readImage('oversized')).rejects.toThrow(
        'STORAGE_IMAGE_TOO_LARGE',
      );
      mode = 'stalled';
      const started = Date.now();
      await expect(storage.readImage('stalled')).rejects.toThrow();
      expect(Date.now() - started).toBeLessThan(11000);
      expect(ranges).toEqual([
        `bytes=0-${MAX_IMAGE_BYTES}`,
        `bytes=0-${MAX_IMAGE_BYTES}`,
      ]);
    } finally {
      storage.onModuleDestroy();
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
  }, 15000);
});
