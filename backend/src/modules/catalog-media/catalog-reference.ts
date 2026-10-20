import { BadRequestException } from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';
export const catalogReference = (id: string) => 'catalog/images/' + id;
export const managedImagePattern =
  /^catalog\/images\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i;
export async function validateCatalogReferences(
  tx: Prisma.TransactionClient,
  productId: string | null,
  images: { url: string }[],
) {
  const ids = [
    ...new Set(
      images.flatMap((image) => {
        const match = managedImagePattern.exec(image.url);
        return match ? [match[1]] : [];
      }),
    ),
  ];
  if (!ids.length) return;
  if (
    !productId ||
    (await tx.catalogAsset.count({
      where: {
        id: { in: ids },
        productId,
        verifiedAt: { not: null },
        deletedAt: null,
      },
    })) !== ids.length
  )
    throw new BadRequestException({
      code: 'INVALID_CATALOG_IMAGE',
      message: 'Catalog image does not belong to this product',
    });
}
