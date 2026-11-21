import { Prisma } from '../../generated/prisma/client';
import { lockUser } from '../../common/transaction';
import { can } from '../../common/permissions';
import { fail } from '../../common/errors';

export async function lockCatalogActor(
  tx: Prisma.TransactionClient,
  actorId: string,
) {
  await lockUser(tx, actorId);
  const actor = await tx.user.findUnique({
    where: { id: actorId },
    select: { role: true, active: true },
  });
  if (!actor?.active || !can(actor.role, 'catalog.write'))
    fail(403, 'FORBIDDEN', 'Không có quyền chỉnh sửa sản phẩm.');
}
export function checkCatalogVersion(current: Date, expected?: string) {
  // Optional for compatibility; the admin UI always supplies its saved version.
  if (
    expected !== undefined &&
    current.toISOString() !== new Date(expected).toISOString()
  )
    fail(
      409,
      'PRODUCT_CONFLICT',
      'Sản phẩm hoặc biến thể đã thay đổi. Hãy tải lại trước khi lưu.',
    );
}
export function catalogWriteError(
  error: unknown,
  kind: 'product' | 'sku',
): never {
  if (
    error instanceof Prisma.PrismaClientKnownRequestError &&
    error.code === 'P2002'
  ) {
    if (kind === 'product')
      fail(
        409,
        'PRODUCT_SLUG_EXISTS',
        'Đường dẫn đã được sản phẩm khác sử dụng.',
      );
    const target = JSON.stringify(error.meta ?? {});
    if (/productId|size|color/.test(target))
      fail(
        409,
        'VARIANT_EXISTS',
        'Sản phẩm đã có biến thể với kích cỡ và màu này.',
      );
    fail(409, 'SKU_EXISTS', 'Mã SKU đã được sử dụng.');
  }
  throw error;
}
