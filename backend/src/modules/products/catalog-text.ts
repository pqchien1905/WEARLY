import { Prisma } from '../../generated/prisma/client';
import { fail } from '../../common/errors';

export const cleanProductName = (value: unknown): unknown =>
  typeof value === 'string'
    ? value.normalize('NFKC').replace(/\s+/gu, ' ').trim()
    : value;

// Serializable admin transactions also protect concurrent creates/reactivations.
export async function assertDistinctActiveProduct(
  tx: Prisma.TransactionClient,
  product: { name: string; brandId: string; active: boolean; id?: string },
) {
  if (!product.active) return;
  const duplicates = await tx.$queryRaw<{ id: string }[]>(Prisma.sql`
    SELECT id FROM "Product"
    WHERE active = true AND "brandId" = ${product.brandId}::uuid
      AND lower(translate(btrim(regexp_replace(normalize(name, NFKC), '\\s+', ' ', 'g')), ${accents.toUpperCase()}, ${accents}))
        = ${(cleanProductName(product.name) as string).toLowerCase()}
      ${product.id ? Prisma.sql`AND id <> ${product.id}::uuid` : Prisma.empty}
    LIMIT 1
  `);
  if (duplicates.length)
    fail(
      409,
      'DUPLICATE_PRODUCT',
      'An active product with this name and brand already exists',
    );
}

const accents =
  'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
// Explicit Vietnamese folding also works on PostgreSQL databases using C locale,
// where lower() alone does not convert accented uppercase characters.
const withoutAccents = (text: string) =>
  text.normalize('NFD').replace(/\p{M}/gu, '').replace(/đ/g, 'd');
const plain = withoutAccents(accents);
const literalLike = (text: string) => text.replace(/[\\%_]/g, '\\$&');

export function catalogSearch(text: string): Prisma.Sql | undefined {
  const cleaned = (cleanProductName(text) as string).toLowerCase();
  if (!cleaned) return undefined;
  const pattern = '%' + literalLike(withoutAccents(cleaned)) + '%';
  const slugPattern =
    '%' + literalLike(withoutAccents(cleaned).replace(/ /g, '-')) + '%';
  return Prisma.sql`(
    lower(translate(normalize(p.name, NFC), ${accents + accents.toUpperCase()}, ${plain + plain})) LIKE ${pattern}
    OR p.slug LIKE ${slugPattern}
  )`;
}
