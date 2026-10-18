import sharp from 'sharp';
import { normalizeImage } from '../src/integrations/storage/image-policy';

const photo = () =>
  sharp({
    create: { width: 64, height: 80, channels: 3, background: '#447766' },
  });
describe('private image policy', () => {
  it('rejects missing PNG terminators, trailing bytes and broken chunk checksums', async () => {
    const png = await photo().png().toBuffer();
    const invalidCrc = Buffer.from(png);
    invalidCrc[invalidCrc.length - 1] ^= 1;
    for (const bytes of [
      ...[1, 4, 8, 12].map((length) => png.subarray(0, png.length - length)),
      Buffer.concat([png, Buffer.from('extra')]),
      invalidCrc,
    ]) {
      await expect(normalizeImage(bytes, 'image/png')).rejects.toMatchObject({
        status: 400,
      });
    }
  });
  it('decodes JPEG, strips metadata and preserves dimensions', async () => {
    const input = await photo()
      .withMetadata({ exif: { IFD0: { Artist: 'private-name' } } })
      .jpeg()
      .toBuffer();
    expect((await sharp(input).metadata()).exif).toBeDefined();
    const result = await normalizeImage(input, 'image/jpeg');
    expect(result).toMatchObject({
      width: 64,
      height: 80,
      contentType: 'image/jpeg',
    });
    const metadata = await sharp(result.bytes).metadata();
    expect(metadata.exif).toBeUndefined();
    expect(metadata.icc).toBeUndefined();
  });
  it('rejects forged MIME, SVG, truncation, empty and oversized uploads', async () => {
    const png = await photo().png().toBuffer();
    for (const [bytes, mime] of [
      [png, 'image/jpeg'],
      [Buffer.from('<svg/>'), 'image/png'],
      [png.subarray(0, 80), 'image/png'],
      [Buffer.alloc(0), 'image/png'],
      [Buffer.alloc(8 * 1024 * 1024 + 1), 'image/png'],
    ] as const)
      await expect(normalizeImage(bytes, mime)).rejects.toMatchObject({
        status: 400,
      });
  });
  it('rejects images that are too small or have excessive decoded pixels', async () => {
    const small = await sharp({
      create: { width: 1, height: 1, channels: 3, background: 'white' },
    })
      .png()
      .toBuffer();
    const huge = await sharp({
      create: { width: 4096, height: 4096, channels: 3, background: 'white' },
    })
      .png()
      .toBuffer();
    await expect(normalizeImage(small, 'image/png')).rejects.toMatchObject({
      status: 400,
    });
    await expect(normalizeImage(huge, 'image/png')).rejects.toMatchObject({
      status: 400,
    });
  });
});
