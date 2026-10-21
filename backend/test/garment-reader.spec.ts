import { mkdtemp, mkdir, writeFile, symlink, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { GarmentReader } from '../src/integrations/ai-providers/garment-reader.service';
import { PrismaService } from '../src/database/prisma.service';
import { StorageService } from '../src/integrations/storage/storage.service';

describe('Garment input trust boundary', () => {
  let directory: string, root: string, png: Buffer;
  const id = randomUUID(),
    productId = randomUUID();
  const asset = jest.fn(),
    gallery = jest.fn(),
    readImage = jest.fn();
  const db = {
    catalogAsset: { findFirst: asset },
    productImage: { findMany: gallery },
  };
  const reader = () =>
    new GarmentReader(
      db as unknown as PrismaService,
      { readImage } as unknown as StorageService,
      root,
    );
  beforeAll(async () => {
    directory = await mkdtemp(path.join(tmpdir(), 'wearly-garment-'));
    root = path.join(directory, 'images');
    await mkdir(root);
    png = await sharp({
      create: { width: 64, height: 64, channels: 3, background: 'red' },
    })
      .png()
      .toBuffer();
    await writeFile(path.join(root, 'shirt.png'), png);
    await mkdir(path.join(directory, 'outside'));
    await symlink(
      path.join(directory, 'outside'),
      path.join(root, 'escape.png'),
      'junction',
    );
    await writeFile(
      path.join(root, 'large.png'),
      Buffer.alloc(8 * 1024 * 1024 + 1),
    );
  });
  beforeEach(() => {
    jest.clearAllMocks();
    asset.mockResolvedValue(null);
    gallery.mockResolvedValue([]);
    readImage.mockResolvedValue(png);
  });
  afterAll(async () => {
    const absolute = path.resolve(directory);
    if (
      path.dirname(absolute) !== path.resolve(tmpdir()) ||
      !path.basename(absolute).startsWith('wearly-garment-')
    )
      throw Error('Unexpected test cleanup target');
    await rm(absolute, { recursive: true, force: true });
  });
  it('reads and normalizes only a real seed image within the allowed root', async () => {
    const image = await reader().read('assets/images/shirt.png', productId);
    expect(image).toMatchObject({
      width: 64,
      height: 64,
      contentType: 'image/png',
    });
    expect(readImage).not.toHaveBeenCalled();
  });
  it.each([
    'https://elsewhere.test/photo.png',
    'assets/images/../outside.png',
    'assets/images/%2e%2e.png',
    'assets/images/escape.png',
    'assets/images/large.png',
    'assets/images/missing.png',
  ])('rejects unsafe or unavailable source %s', async (ref) => {
    await expect(reader().read(ref, productId)).rejects.toThrow(
      'AI_GARMENT_UNAVAILABLE',
    );
    expect(readImage).not.toHaveBeenCalled();
  });
  it('reads managed bytes only after verified product ownership checks', async () => {
    asset.mockResolvedValue({
      objectKey: 'catalog/owned',
      mimeType: 'image/png',
    });
    const image = await reader().read('catalog/images/' + id, productId);
    expect(image.width).toBe(64);
    expect(asset).toHaveBeenCalledWith({
      where: {
        id,
        productId,
        verifiedAt: { not: null },
        deletedAt: null,
        purgedAt: null,
      },
    });
    expect(readImage).toHaveBeenCalledWith('catalog/owned');
    asset.mockResolvedValue(null);
    readImage.mockClear();
    await expect(
      reader().read('catalog/images/' + id, randomUUID()),
    ).rejects.toThrow('AI_GARMENT_UNAVAILABLE');
    expect(readImage).not.toHaveBeenCalled();
  });
  it('selects the requested color first and never another colored garment', async () => {
    gallery.mockResolvedValue([
      { url: 'assets/images/default.png', color: null, position: 0 },
      { url: 'assets/images/red.png', color: 'Red', position: 1 },
      { url: 'assets/images/blue.png', color: 'Blue', position: 2 },
    ]);
    expect(await reader().resolve(productId, 'Blue')).toBe(
      'assets/images/blue.png',
    );
    expect(await reader().resolve(productId, 'Yellow')).toBe(
      'assets/images/default.png',
    );
    gallery.mockResolvedValue([
      { url: 'https://elsewhere.test/image.jpg', color: null, position: 0 },
    ]);
    await expect(reader().resolve(productId, 'Blue')).rejects.toThrow(
      'AI_GARMENT_UNAVAILABLE',
    );
  });
});
