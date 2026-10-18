import { UploadsService } from '../src/modules/uploads/uploads.service';
import { PrismaService } from '../src/database/prisma.service';
import { StorageService } from '../src/integrations/storage/storage.service';
import sharp from 'sharp';

it('does not write a resumed upload after its committed reservation was purged', async () => {
  let reservation: Record<string, unknown> = {};
  let transactions = 0;
  const tx = {
    $queryRaw: jest.fn(async () => []),
    imageAsset: {
      count: jest.fn(async () => 0),
      create: jest.fn(async (args: { data: Record<string, unknown> }) => {
        reservation = {
          ...args.data,
          createdAt: new Date(),
          verifiedAt: null,
          deletedAt: null,
          purgedAt: null,
        };
        return reservation;
      }),
      findUniqueOrThrow: jest.fn(async () => reservation),
      update: jest.fn(async () => reservation),
    },
  };
  const db = {
    $transaction: async (run: (transaction: typeof tx) => Promise<unknown>) => {
      const result = await run(tx);
      if (++transactions === 1) {
        // Simulate suspension after reservation COMMIT, while another process
        // expires and purges the stale reservation before this upload resumes.
        reservation = {
          ...reservation,
          createdAt: new Date(Date.now() - 3600000),
          deletedAt: new Date(),
          purgedAt: new Date(),
        };
      }
      return result;
    },
    imageAsset: { update: jest.fn(async () => reservation) },
  };
  const storage = { putImage: jest.fn(async () => undefined) };
  const service = new UploadsService(
    db as unknown as PrismaService,
    storage as unknown as StorageService,
  );
  const buffer = await sharp({
    create: { width: 64, height: 64, channels: 3, background: '#abc' },
  })
    .png()
    .toBuffer();
  await expect(
    service.upload('owner', {
      buffer,
      mimetype: 'image/png',
    } as Express.Multer.File),
  ).rejects.toMatchObject({ status: 503 });
  expect(storage.putImage).not.toHaveBeenCalled();
});
