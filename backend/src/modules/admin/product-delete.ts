import { NotFoundException } from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { recordAdminActivity } from './audit';
import { checkCatalogVersion, lockCatalogActor } from './catalog-write';

const inUse = () =>
  fail(
    409,
    'PRODUCT_IN_USE',
    'Sản phẩm có đơn hàng, lịch sử kho, đánh giá, lượt thử đồ hoặc đang nằm trong giỏ hàng. Hãy dùng “Ẩn sản phẩm” để giữ dữ liệu liên quan.',
  );

export function deleteProduct(
  db: PrismaService,
  actorId: string,
  id: string,
  expectedUpdatedAt: string,
) {
  return transaction(db, async (tx) => {
    await lockCatalogActor(tx, actorId);
    await tx.$queryRaw`SELECT id FROM "Product" WHERE id=${id}::uuid FOR UPDATE`;
    const product = await tx.product.findUnique({ where: { id } });
    if (!product) throw new NotFoundException();
    checkCatalogVersion(product.updatedAt, expectedUpdatedAt);
    // Lock children before checking references so checkout, stock adjustments,
    // cart additions and new variants cannot race the removal.
    await tx.$queryRaw`SELECT id FROM "ProductVariant" WHERE "productId"=${id}::uuid ORDER BY id FOR UPDATE`;
    await tx.$queryRaw`SELECT i.id FROM "Inventory" i JOIN "ProductVariant" v ON v.id=i."variantId"
      WHERE v."productId"=${id}::uuid ORDER BY i.id FOR UPDATE OF i`;
    const variant = { productId: id };
    const references = [
      await tx.orderItem.count({ where: { variant } }),
      await tx.cartItem.count({ where: { variant } }),
      await tx.aIJob.count({ where: { variant } }),
      await tx.inventoryMovement.count({ where: { inventory: { variant } } }),
      await tx.review.count({ where: { productId: id } }),
    ];
    if (references.some((count) => count > 0)) inUse();
    await tx.inventory.deleteMany({ where: { variant } });
    await tx.productVariant.deleteMany({ where: { productId: id } });
    // Gallery/wishlist rows cascade; collection covers become null. Catalog
    // asset files remain durable and must not be purged by this transaction.
    await tx.product.delete({ where: { id } });
    await recordAdminActivity(tx, actorId, 'PRODUCT_DELETED', id, {
      before: product,
    });
    return { id, deleted: true };
  }).catch((error: unknown) => {
    if (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === 'P2003'
    )
      inUse();
    throw error;
  });
}
