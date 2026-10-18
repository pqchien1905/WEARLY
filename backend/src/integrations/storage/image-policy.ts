import {
  BadRequestException,
  ServiceUnavailableException,
} from '@nestjs/common';
import sharp from 'sharp';
import { crc32 } from 'node:zlib';

export const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
export type NormalizedImage = {
  bytes: Buffer;
  contentType: 'image/jpeg' | 'image/png';
  width: number;
  height: number;
};
let decoding = 0;
function completePng(bytes: Buffer) {
  let offset = 8,
    hasImageData = false;
  while (offset + 12 <= bytes.length) {
    const length = bytes.readUInt32BE(offset);
    const end = offset + 12 + length;
    if (end > bytes.length) return false;
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    if (offset === 8 && (type !== 'IHDR' || length !== 13)) return false;
    if (offset !== 8 && type === 'IHDR') return false;
    if (type === 'acTL') return false;
    if (
      crc32(bytes.subarray(offset + 4, end - 4)) !== bytes.readUInt32BE(end - 4)
    )
      return false;
    if (type === 'IDAT') hasImageData = true;
    if (type === 'IEND')
      return length === 0 && hasImageData && end === bytes.length;
    offset = end;
  }
  return false;
}
export async function normalizeImage(
  bytes: Buffer,
  contentType: string,
): Promise<NormalizedImage> {
  const invalid = () =>
    new BadRequestException({
      code: 'INVALID_IMAGE',
      message:
        'Use a valid JPEG or PNG, up to 8 MiB and 16 megapixels, with dimensions 64–8192 pixels',
    });
  if (!bytes.length || bytes.length > MAX_IMAGE_BYTES) throw invalid();
  const png = bytes
    .subarray(0, 8)
    .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  const jpeg = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  if ((!png && !jpeg) || contentType !== (png ? 'image/png' : 'image/jpeg'))
    throw invalid();
  if (png && !completePng(bytes)) throw invalid();
  if (decoding >= 2)
    throw new ServiceUnavailableException({
      code: 'IMAGE_PROCESSING_BUSY',
      message: 'Please retry the upload shortly',
    });
  decoding++;
  try {
    const pipeline = sharp(bytes, {
      limitInputPixels: 16_000_000,
      failOn: 'warning',
    }).timeout({ seconds: 5 });
    const meta = await pipeline.metadata();
    if (
      !meta.width ||
      !meta.height ||
      meta.width < 64 ||
      meta.height < 64 ||
      meta.width > 8192 ||
      meta.height > 8192 ||
      (meta.pages ?? 1) > 1 ||
      !['jpeg', 'png'].includes(meta.format)
    )
      throw invalid();
    // Re-encoding drops EXIF/GPS, ICC and trailing payloads; no withMetadata().
    const output = await (
      png ? pipeline.rotate().png() : pipeline.rotate().jpeg({ quality: 90 })
    ).toBuffer({ resolveWithObject: true });
    if (output.data.length > MAX_IMAGE_BYTES) throw invalid();
    return {
      bytes: output.data,
      contentType: png ? 'image/png' : 'image/jpeg',
      width: output.info.width,
      height: output.info.height,
    };
  } catch {
    throw invalid();
  } finally {
    decoding--;
  }
}
