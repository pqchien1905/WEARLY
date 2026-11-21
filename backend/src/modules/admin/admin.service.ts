import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { deleteProduct } from './product-delete';
import { Prisma } from '../../generated/prisma/client';
import { AdminListQueryDto } from './dto/admin-query.dto';
import { AdminOrdersQueryDto } from './dto/admin-orders-query.dto';
import { AdminProductsQueryDto } from './dto/admin-products-query.dto';
import {
  AdminInventoryQueryDto,
  InventoryHistoryQueryDto,
} from './dto/admin-inventory-query.dto';
import {
  inventoryList,
  inventorySummary,
  inventoryDetail,
  inventoryHistory,
  initializeInventory,
  lockInventoryActor,
} from './inventory-workspace';
import {
  adminProductInclude,
  listAdminProducts,
  adminProductsSummary,
} from './product-list';
import {
  checkCatalogVersion,
  lockCatalogActor,
  catalogWriteError,
} from './catalog-write';
import {
  adminOrderListSelect,
  orderFilters,
  orderSort,
  orderStatusFilter,
} from './order-list';
import { validateCatalogReferences } from '../catalog-media/catalog-reference';
import { assertDistinctActiveProduct } from '../products/catalog-text';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import {
  isOnlineProvider,
  paymentProviders,
  providerLabel,
} from '../../integrations/payments/wallet-gateway';
import { PageDto } from '../products/dto/query-products.dto';
import { publicUser } from '../auth/auth.service';
import { recordAdminActivity } from './audit';
import { queueOrderMail } from '../mail/outbox';
import { adminOrderInclude } from '../orders/order-includes';
import { recordFulfillment } from '../shipments/shipment-transitions';
import {
  AdjustInventoryDto,
  CreateProductDto,
  CreateSkuDto,
  OrderStatusDto,
  SettleCodDto,
  UpdateProductDto,
  UpdateSkuDto,
} from './dto/admin.dto';
@Injectable()
export class AdminService {
  constructor(private readonly db: PrismaService) {}
  inventory(q: AdminInventoryQueryDto) {
    return inventoryList(this.db, q);
  }
  inventorySummary() {
    return inventorySummary(this.db);
  }
  inventoryDetail(id: string) {
    return inventoryDetail(this.db, id);
  }
  inventoryHistory(id: string, q: InventoryHistoryQueryDto) {
    return inventoryHistory(this.db, id, q);
  }
  initializeInventory(actorId: string, variantId: string) {
    return initializeInventory(this.db, actorId, variantId);
  }
  products(q: AdminProductsQueryDto) {
    return listAdminProducts(this.db, q);
  }
  productsSummary() {
    return adminProductsSummary(this.db);
  }
  deleteProduct(actorId: string, id: string, expectedUpdatedAt: string) {
    return deleteProduct(this.db, actorId, id, expectedUpdatedAt);
  }
  audit(q: PageDto) {
    return this.db.$transaction(
      async (tx) => {
        const total = await tx.adminAuditEvent.count();
        const page = Math.min(q.page, Math.max(1, Math.ceil(total / q.limit)));
        return {
          items: await tx.adminAuditEvent.findMany({
            skip: (page - 1) * q.limit,
            take: q.limit,
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
          }),
          total,
          page,
          limit: q.limit,
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  async summary() {
    const statusGroups = this.db.order.groupBy({
      by: ['status'],
      orderBy: { status: 'asc' },
      _count: { _all: true },
    });
    const [
      products,
      inventory,
      orders,
      pendingOrders,
      customers,
      paid,
      awaiting,
      refunded,
      extra,
      legacy,
      activeProducts,
      lowStockVariants,
      outOfStockVariants,
      orderStatuses,
      recentOrders,
      dailySales,
    ] = await this.db.$transaction(
      [
        this.db.product.count(),
        this.db.inventory.aggregate({ _sum: { quantity: true } }),
        this.db.order.count(),
        this.db.order.count({ where: { status: 'PENDING' } }),
        this.db.user.count({ where: { role: 'CUSTOMER', deletedAt: null } }),
        this.db.payment.aggregate({
          where: { status: { in: ['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED'] } },
          _sum: { amount: true },
          _count: true,
        }),
        this.db.payment.aggregate({
          where: {
            provider: 'cod',
            status: 'PENDING',
            order: { status: 'DELIVERED' },
          },
          _sum: { amount: true },
        }),
        this.db.refund.aggregate({
          where: { status: 'SUCCEEDED' },
          _sum: { amount: true },
        }),
        this.db.$queryRaw<
          { amount: string }[]
        >`SELECT COALESCE(sum(a.amount),0)::text AS amount FROM "PaymentAttempt" a JOIN "Payment" p ON p.id=a."paymentId" WHERE a.status='PAID' AND a."transactionNo"<>p."providerTransactionId"`,
        this.db.payment.aggregate({
          where: {
            status: 'REFUNDED',
            refunds: { none: { primary: true, status: 'SUCCEEDED' } },
          },
          _sum: { amount: true },
        }),
        this.db.product.count({ where: { active: true } }),
        this.db.inventory.count({
          where: {
            quantity: { gt: 0, lte: 5 },
            variant: { active: true, product: { active: true } },
          },
        }),
        this.db.inventory.count({
          where: {
            quantity: 0,
            variant: { active: true, product: { active: true } },
          },
        }),
        statusGroups,
        this.db.order.findMany({
          take: 5,
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
          select: {
            id: true,
            code: true,
            status: true,
            total: true,
            createdAt: true,
            user: { select: { name: true } },
          },
        }),
        // Last 14 calendar days in Vietnam time; cancelled/returned excluded.
        this.db.$queryRaw<{ day: string; orders: number; total: string }[]>`
          WITH days AS (
            SELECT generate_series(
              timezone('Asia/Ho_Chi_Minh', now())::date - 13,
              timezone('Asia/Ho_Chi_Minh', now())::date,
              interval '1 day'
            )::date AS day
          )
          SELECT to_char(d.day, 'YYYY-MM-DD') AS day,
            count(o.id)::int AS orders,
            COALESCE(sum(o.total), 0)::text AS total
          FROM days d
          LEFT JOIN "Order" o
            ON o."createdAt" >= now() - interval '15 days'
           AND timezone('Asia/Ho_Chi_Minh', timezone('UTC', o."createdAt"))::date = d.day
           AND o.status NOT IN ('CANCELLED', 'RETURNED')
          GROUP BY d.day
          ORDER BY d.day`,
      ],
      { isolationLevel: 'RepeatableRead' },
    );
    const gross =
        BigInt(paid._sum.amount?.toFixed(0) ?? '0') + BigInt(extra[0].amount),
      returned = BigInt(refunded._sum.amount?.toFixed(0) ?? '0'),
      unverified = BigInt(legacy._sum.amount?.toFixed(0) ?? '0');
    return {
      products,
      inventoryUnits: inventory._sum.quantity ?? 0,
      orders,
      pendingOrders,
      customers,
      activeProducts,
      lowStockVariants,
      outOfStockVariants,
      orderStatuses: Object.fromEntries(
        orderStatuses.map((row) => [row.status, row._count._all]),
      ),
      recentOrders,
      dailySales,
      generatedAt: new Date().toISOString(),
      paidRevenueVnd: gross.toString(),
      refundedVnd: returned.toString(),
      netCollectedVnd: (gross - returned - unverified).toString(),
      legacyRefundUnverifiedVnd: unverified.toString(),
      extraCollectedVnd: extra[0].amount,
      paidOrders: paid._count,
      codAwaitingSettlementVnd: awaiting._sum.amount?.toFixed(0) ?? '0',
    };
  }
  async product(id: string) {
    const value = await this.db.product.findUnique({
      where: { id },
      include: adminProductInclude,
    });
    if (!value) throw new NotFoundException();
    return value;
  }
  async order(id: string) {
    const value = await this.db.order.findUnique({
      where: { id },
      include: adminOrderInclude,
    });
    if (!value) throw new NotFoundException();
    return value;
  }
  async list(
    kind: 'products' | 'inventory' | 'orders' | 'users',
    q: AdminListQueryDto,
  ) {
    if (kind === 'orders') return this.orders(q);
    if (kind === 'inventory') return this.inventory(q);
    const args = {
      skip: (q.page - 1) * q.limit,
      take: q.limit,
      orderBy: [{ createdAt: 'desc' as const }, { id: 'desc' as const }],
    };
    const statuses = {
      products: ['active', 'hidden'],
      inventory: ['in_stock', 'low', 'out'],
      orders: [
        'PENDING',
        'CONFIRMED',
        'SHIPPED',
        'DELIVERED',
        'CANCELLED',
        'RETURNED',
      ],
      users: ['active', 'hidden'],
    };
    if (q.status && !statuses[kind].includes(q.status))
      fail(400, 'INVALID_FILTER', 'Bộ lọc không phù hợp với danh sách.');
    // Escape LIKE wildcards so searching a literal SKU such as A_1 is exact.
    const contains = {
      contains: (q.q ?? '').replace(/[\\%_]/g, '\\$&'),
      mode: 'insensitive' as const,
    };
    const active = q.status ? q.status === 'active' : undefined;
    return this.db.$transaction(
      async (tx) => {
        let items: unknown[], total: number;
        if (kind === 'products') {
          const where: Prisma.ProductWhereInput = {
            active,
            ...(q.q
              ? {
                  OR: [
                    { name: contains },
                    { slug: contains },
                    { category: { name: contains } },
                    { brand: { name: contains } },
                    { variants: { some: { sku: contains } } },
                  ],
                }
              : {}),
          };
          items = await tx.product.findMany({
            ...args,
            where,
            include: adminProductInclude,
          });
          total = await tx.product.count({ where });
        } else {
          const where: Prisma.UserWhereInput = {
            role: 'CUSTOMER',
            deletedAt: null,
            active,
            ...(q.q
              ? {
                  OR: [
                    { name: contains },
                    { email: contains },
                    { phone: contains },
                  ],
                }
              : {}),
          };
          items = (await tx.user.findMany({ ...args, where })).map((user) => ({
            ...publicUser(user),
            active: user.active,
          }));
          total = await tx.user.count({ where });
        }
        return { items, total, page: q.page, limit: q.limit };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  async orders(q: AdminOrdersQueryDto) {
    const filters = orderFilters(q);
    const where = { ...filters, ...orderStatusFilter(q.status) };
    return this.db.$transaction(
      async (tx) => {
        const items = await tx.order.findMany({
          where,
          select: adminOrderListSelect,
          skip: (q.page - 1) * q.limit,
          take: q.limit,
          orderBy: orderSort(q.sort),
        });
        const total = await tx.order.count({ where });
        const counts = await tx.order.groupBy({
          by: ['status'],
          where: filters,
          _count: { _all: true },
        });
        return {
          items,
          total,
          page: q.page,
          limit: q.limit,
          statusCounts: Object.fromEntries(
            counts.map((row) => [row.status, row._count._all]),
          ),
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  createProduct(actorId: string, dto: CreateProductDto) {
    const { images, ...data } = dto;
    return transaction(this.db, async (tx) => {
      await lockCatalogActor(tx, actorId);
      await assertDistinctActiveProduct(tx, {
        ...data,
        active: data.active ?? true,
      });
      await validateCatalogReferences(tx, null, images ?? []);
      const product = await tx.product.create({
        data: {
          ...data,
          images: images
            ? {
                create: images.map((image, position) => ({
                  ...image,
                  position,
                })),
              }
            : undefined,
        },
        include: adminProductInclude,
      });
      await recordAdminActivity(tx, actorId, 'PRODUCT_CREATED', product.id, {
        after: product,
      });
      return product;
    }).catch((error) => catalogWriteError(error, 'product'));
  }
  updateProduct(actorId: string, id: string, dto: UpdateProductDto) {
    const { images, expectedUpdatedAt, ...data } = dto;
    // Explicit delete then create avoids a unique(productId,position) collision.
    // The transaction rolls back both metadata and gallery if any write fails.
    return transaction(this.db, async (tx) => {
      await lockCatalogActor(tx, actorId);
      await tx.$queryRaw`SELECT id FROM "Product" WHERE id = ${id}::uuid FOR UPDATE`;
      const before = await tx.product.findUniqueOrThrow({ where: { id } });
      checkCatalogVersion(before.updatedAt, expectedUpdatedAt);
      await assertDistinctActiveProduct(tx, { ...before, ...data });
      await validateCatalogReferences(tx, id, images ?? []);
      if (images !== undefined)
        await tx.productImage.deleteMany({ where: { productId: id } });
      const product = await tx.product.update({
        where: { id },
        data: {
          ...data,
          updatedAt: new Date(
            Math.max(Date.now(), before.updatedAt.getTime() + 1),
          ),
          images:
            images === undefined
              ? undefined
              : {
                  create: images.map((image, position) => ({
                    ...image,
                    position,
                  })),
                },
        },
        include: adminProductInclude,
      });
      await recordAdminActivity(tx, actorId, 'PRODUCT_UPDATED', id, {
        before,
        after: product,
      });
      return product;
    }).catch((error) => catalogWriteError(error, 'product'));
  }
  createSku(actorId: string, dto: CreateSkuDto) {
    return transaction(this.db, async (tx) => {
      await lockCatalogActor(tx, actorId);
      const sku = await tx.productVariant.create({
        data: { ...dto, inventory: { create: { quantity: 0 } } },
      });
      await recordAdminActivity(tx, actorId, 'SKU_CREATED', sku.id, {
        after: sku,
      });
      return sku;
    }).catch((error) => catalogWriteError(error, 'sku'));
  }
  updateSku(actorId: string, id: string, dto: UpdateSkuDto) {
    const { expectedUpdatedAt, ...data } = dto;
    return transaction(this.db, async (tx) => {
      await lockCatalogActor(tx, actorId);
      await tx.$queryRaw`SELECT id FROM "ProductVariant" WHERE id=${id}::uuid FOR UPDATE`;
      const before = await tx.productVariant.findUniqueOrThrow({
        where: { id },
      });
      checkCatalogVersion(before.updatedAt, expectedUpdatedAt);
      const sku = await tx.productVariant.update({
        where: { id },
        data: {
          ...data,
          updatedAt: new Date(
            Math.max(Date.now(), before.updatedAt.getTime() + 1),
          ),
        },
      });
      await recordAdminActivity(tx, actorId, 'SKU_UPDATED', id, {
        before,
        after: sku,
      });
      return sku;
    });
  }
  adjust(actorId: string, id: string, dto: AdjustInventoryDto) {
    if (
      (dto.operation === 'in' && dto.delta < 0) ||
      (dto.operation === 'out' && dto.delta > 0)
    )
      fail(400, 'INVALID_ADJUSTMENT', 'Số lượng không khớp loại thao tác kho.');
    return transaction(this.db, async (tx) => {
      await lockInventoryActor(tx, actorId);
      const inv = await tx.inventory.findUnique({ where: { id } });
      if (!inv) throw new NotFoundException();
      const changed = await tx.inventory.updateMany({
        where: {
          id,
          version: dto.expectedVersion,
          quantity: {
            gte: Math.max(0, -dto.delta),
            lte: 2147483647 - Math.max(0, dto.delta),
          },
        },
        data: { quantity: { increment: dto.delta }, version: { increment: 1 } },
      });
      if (changed.count !== 1)
        fail(
          409,
          'VERSION_CONFLICT',
          'Tồn kho đã thay đổi hoặc số lượng vượt giới hạn. Tải lại trước khi tiếp tục.',
        );
      const movement = await tx.inventoryMovement.create({
        data: {
          inventoryId: id,
          delta: dto.delta,
          reason: 'ADMIN: ' + dto.reason,
        },
      });
      const after = await tx.inventory.findUniqueOrThrow({ where: { id } });
      await recordAdminActivity(tx, actorId, 'INVENTORY_ADJUSTED', id, {
        before: inv,
        after: {
          ...after,
          movementId: movement.id,
          operation: dto.operation ?? 'delta',
        },
      });
      return after;
    });
  }
  status(actorId: string, id: string, dto: OrderStatusDto) {
    return transaction(this.db, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id = ${id}::uuid FOR UPDATE`;
      const before = await tx.order.findUnique({ where: { id } });
      if (!before) throw new NotFoundException();
      const payment = await tx.payment.findUnique({ where: { orderId: id } });
      if (
        !payment ||
        !payment.amount.eq(before.total) ||
        !(paymentProviders as readonly string[]).includes(payment.provider)
      )
        fail(
          409,
          'ORDER_PAYMENT_INVALID',
          'Thông tin thanh toán của đơn chưa hợp lệ.',
        );
      if (
        payment.provider === 'cod' &&
        !['PENDING', 'PAID', 'PARTIALLY_REFUNDED'].includes(payment.status)
      )
        fail(
          409,
          'PAYMENT_REQUIRED',
          'Thanh toán của đơn không còn hợp lệ để giao hàng.',
        );
      if (
        payment.provider === 'free' &&
        (payment.status !== 'PAID' || !before.total.eq(0))
      )
        fail(
          409,
          'ORDER_PAYMENT_INVALID',
          'Đơn miễn thanh toán phải có tổng tiền bằng 0.',
        );
      if (
        isOnlineProvider(payment?.provider) &&
        !['PAID', 'PARTIALLY_REFUNDED'].includes(payment.status)
      )
        fail(
          409,
          'PAYMENT_REQUIRED',
          `${providerLabel(payment.provider)} must be verified before fulfilling the order`,
        );
      const from = {
        CONFIRMED: 'PENDING',
        SHIPPED: 'CONFIRMED',
        DELIVERED: 'SHIPPED',
      } as const;
      const changed = await tx.order.updateMany({
        where: { id, status: from[dto.status], version: dto.expectedVersion },
        data: { status: dto.status, version: { increment: 1 } },
      });
      if (!changed.count)
        fail(
          409,
          'ORDER_STATE_CONFLICT',
          'Order changed or transition is invalid',
        );
      await recordFulfillment(
        tx,
        id,
        dto.status,
        dto.expectedVersion + 1,
        actorId,
      );
      await recordAdminActivity(tx, actorId, 'ORDER_STATUS_CHANGED', id, {
        before,
        after: { status: dto.status, version: dto.expectedVersion + 1 },
      });
      // Delivery is not proof of payment: payment stays PENDING until a separate
      // settlement is explicitly recorded.
      return tx.order.findUniqueOrThrow({
        where: { id },
        include: adminOrderInclude,
      });
    });
  }
  settleCod(actorId: string, id: string, dto: SettleCodDto) {
    return transaction(this.db, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id = ${id}::uuid FOR UPDATE`;
      const order = await tx.order.findUnique({
        where: { id },
        include: adminOrderInclude,
      });
      if (!order) throw new NotFoundException();
      const payment = order.payment;
      const existing = payment?.settlement;
      // A lost response may be retried with the original version. Never collect twice.
      if (existing) {
        if (
          !existing.amount.eq(dto.amount) ||
          existing.reference !== dto.reference
        )
          fail(
            409,
            'SETTLEMENT_CONFLICT',
            'A different settlement was already recorded',
          );
        return order;
      }
      if (
        order.status !== 'DELIVERED' ||
        payment?.provider !== 'cod' ||
        payment.status !== 'PENDING'
      )
        fail(
          409,
          'ORDER_STATE_CONFLICT',
          'Only delivered unpaid COD orders can be settled',
        );
      if (!payment.amount.eq(dto.amount))
        fail(
          409,
          'AMOUNT_MISMATCH',
          'Collected amount must match the full payment amount',
        );
      const changed = await tx.order.updateMany({
        where: { id, version: dto.expectedVersion },
        data: { version: { increment: 1 } },
      });
      if (!changed.count)
        fail(409, 'VERSION_CONFLICT', 'Order changed; reload before settling');
      await tx.payment.update({
        where: { id: payment.id },
        data: {
          status: 'PAID',
          settlement: {
            create: {
              actorId,
              amount: payment.amount,
              reference: dto.reference,
            },
          },
        },
      });
      await recordAdminActivity(tx, actorId, 'COD_SETTLED', id, {
        before: payment,
        after: { status: 'PAID', amount: payment.amount },
      });
      await queueOrderMail(
        tx,
        id,
        'cod-settled:' + payment.id,
        'Đã ghi nhận thu tiền COD',
        `Đã xác nhận thu ${payment.amount.toFixed(0)} VND cho đơn hàng.`,
      );
      return tx.order.findUniqueOrThrow({
        where: { id },
        include: adminOrderInclude,
      });
    });
  }
}
