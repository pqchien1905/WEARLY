import { AdminAuditAction, Prisma } from '../../generated/prisma/client';
const product = ['active', 'tryOnSupported', 'categoryId', 'brandId'];
const sku = ['active', 'price', 'productId'];
const status = ['status', 'version'];
const promotion = [
  'kind',
  'amount',
  'minSubtotal',
  'maxDiscount',
  'usageLimit',
  'perUserLimit',
  'startsAt',
  'expiresAt',
  'active',
  'version',
];
const content = ['version', 'publishedVersion'];
const collection = [
  'slug',
  'title',
  'style',
  'active',
  'position',
  'coverProductId',
  'version',
];
const returned = ['status', 'version', 'amount'];
const refund = ['status', 'provider', 'amount', 'primary'];
const fields: Record<AdminAuditAction, readonly string[]> = {
  CUSTOMER_CREATED: ['role', 'active'],
  CUSTOMER_DELETED: ['active', 'deletedAt'],
  STAFF_UPDATED: [
    'role',
    'active',
    'staffVersion',
    'nameChanged',
    'emailChanged',
    'phoneChanged',
    'usernameChanged',
    'passwordChanged',
  ],
  PRODUCT_CREATED: product,
  PRODUCT_UPDATED: product,
  PRODUCT_DELETED: product,
  SKU_CREATED: sku,
  SKU_UPDATED: sku,
  CATEGORY_CREATED: [],
  CATEGORY_RENAMED: [],
  CATEGORY_DELETED: ['slug'],
  BRAND_DELETED: ['slug'],
  BRAND_CREATED: [],
  BRAND_RENAMED: [],
  COLLECTION_DELETED: collection,
  COLLECTION_CREATED: collection,
  COLLECTION_UPDATED: collection,
  PRODUCT_IMAGE_UPLOADED: [],
  INVENTORY_ADJUSTED: ['quantity', 'version', 'movementId', 'operation'],
  ORDER_STATUS_CHANGED: status,
  ORDER_CANCELLED: status,
  COD_SETTLED: ['status', 'amount'],
  CONTENT_DRAFT_SAVED: content,
  CONTENT_DRAFT_RESTORED: content,
  CONTENT_PUBLISHED: content,
  PROMOTION_CREATED: promotion,
  PROMOTION_UPDATED: promotion,
  PROMOTION_DELETED: promotion,
  SHIPMENT_UPDATED: status,
  RETURN_DECIDED: returned,
  RETURN_RECEIVED: returned,
  REFUND_CREATED: refund,
  REFUND_UPDATED: refund,
  SUPPORT_REPLIED: status,
  SUPPORT_STATUS_CHANGED: status,
};
/** Explicit scalar allowlists prevent accidental raw DTO / personal-data copies. */
export function auditSnapshot(
  action: AdminAuditAction,
  input: unknown,
): Prisma.InputJsonObject {
  const output: Record<string, string | number | boolean | null> = {};
  if (!input || typeof input !== 'object' || Array.isArray(input))
    return output;
  for (const key of fields[action]) {
    let value = (input as Record<string, unknown>)[key];
    if (value instanceof Date)
      value = Number.isFinite(value.getTime())
        ? value.toISOString()
        : undefined;
    if (value instanceof Prisma.Decimal) value = value.toFixed(0);
    if (
      value === null ||
      typeof value === 'boolean' ||
      (typeof value === 'number' && Number.isFinite(value)) ||
      (typeof value === 'string' && value.length <= 120)
    )
      output[key] = value as string | number | boolean | null;
  }
  return output;
}
