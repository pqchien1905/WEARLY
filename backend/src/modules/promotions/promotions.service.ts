import { Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { automaticOffers, automaticPrice } from './automatic-pricing';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { transaction, lockUser } from '../../common/transaction';
import { fail } from '../../common/errors';
import { discountFor, shippingFee, totalForItems } from '../../common/money';
import { recordAdminActivity } from '../admin/audit';
import { cartInclude } from '../cart/cart.service';
import { can } from '../../common/permissions';
import { AdminPromotionsQueryDto } from './promotions-query.dto';
import {
  listPromotions,
  promotionsSummary,
  promotionDetail,
  promotionHistory,
} from './promotions-workspace';
import { PageDto } from '../products/dto/query-products.dto';
import {
  CreatePromotionDto,
  UpdatePromotionDto,
  PreviewPromotionDto,
} from './promotions.dto';
@Injectable()
export class PromotionsService {
  constructor(private readonly db: PrismaService) {}
  private async targeting(
    tx: Prisma.TransactionClient,
    value: {
      application: string;
      scope: string;
      name: string;
      minSubtotal: string | Prisma.Decimal;
      usageLimit?: number | null;
      perUserLimit: number;
    },
    productIds: string[],
  ) {
    if (
      value.application === 'AUTOMATIC' &&
      (!value.name.trim() ||
        !new Prisma.Decimal(value.minSubtotal).eq(0) ||
        value.usageLimit != null ||
        value.perUserLimit !== 1)
    )
      fail(
        400,
        'PROMOTION_INVALID',
        'Khuyến mãi tự động cần tên, không có điều kiện đơn tối thiểu hoặc giới hạn lượt.',
      );
    if (value.scope === 'PRODUCTS' && productIds.length === 0)
      fail(400, 'PROMOTION_INVALID', 'Chọn ít nhất một sản phẩm áp dụng.');
    if (value.scope === 'ALL' && productIds.length > 0)
      fail(
        400,
        'PROMOTION_INVALID',
        'Phạm vi toàn bộ không nhận danh sách sản phẩm riêng.',
      );
    if (
      productIds.length &&
      (await tx.product.count({ where: { id: { in: productIds } } })) !==
        productIds.length
    )
      fail(
        400,
        'PROMOTION_INVALID',
        'Một số sản phẩm không còn tồn tại. Hãy chọn lại.',
      );
  }
  private validate(value: {
    kind: string;
    amount: string | Prisma.Decimal;
    maxDiscount?: string | Prisma.Decimal | null;
    startsAt?: Date | null;
    expiresAt?: Date | null;
  }) {
    for (const date of [value.startsAt, value.expiresAt]) {
      if (
        date &&
        (!Number.isFinite(date.getTime()) ||
          date.getUTCFullYear() < 1 ||
          date.getUTCFullYear() > 9999)
      )
        fail(400, 'PROMOTION_INVALID', 'Invalid promotion date');
    }
    try {
      discountFor('1', value);
    } catch {
      fail(400, 'PROMOTION_INVALID', 'Promotion values are invalid');
    }
    if (value.startsAt && value.expiresAt && value.startsAt >= value.expiresAt)
      fail(400, 'PROMOTION_INVALID', 'Expiry must follow the start date');
  }
  private dates(dto: { startsAt?: string | null; expiresAt?: string | null }) {
    return {
      ...(dto.startsAt !== undefined
        ? { startsAt: dto.startsAt ? new Date(dto.startsAt) : null }
        : {}),
      ...(dto.expiresAt !== undefined
        ? { expiresAt: dto.expiresAt ? new Date(dto.expiresAt) : null }
        : {}),
    };
  }
  private async actor(tx: Prisma.TransactionClient, actorId: string) {
    await lockUser(tx, actorId);
    const user = await tx.user.findUnique({
      where: { id: actorId },
      select: { active: true, role: true },
    });
    if (!user?.active || !can(user.role, 'promotions.manage'))
      fail(403, 'FORBIDDEN', 'Không có quyền quản lý khuyến mãi.');
  }
  private async write<T>(
    operation: (tx: Prisma.TransactionClient) => Promise<T>,
  ) {
    try {
      return await transaction(this.db, operation);
    } catch (e) {
      if (
        e instanceof Prisma.PrismaClientKnownRequestError &&
        e.code === 'P2002'
      )
        fail(409, 'PROMOTION_CODE_EXISTS', 'Mã khuyến mãi đã tồn tại.');
      throw e;
    }
  }
  remove(actorId: string, id: string, expectedVersion: number) {
    return this.write(async (tx) => {
      await this.actor(tx, actorId);
      await tx.$queryRaw`SELECT id FROM "Coupon" WHERE id=${id}::uuid FOR UPDATE`;
      const before = await tx.coupon.findUnique({ where: { id } });
      if (!before) throw new NotFoundException();
      if (before.version !== expectedVersion)
        fail(
          409,
          'VERSION_CONFLICT',
          'Promotion changed; reload before deleting',
        );
      if (
        (await tx.couponRedemption.count({ where: { couponId: id } })) ||
        (await tx.orderItem.count({ where: { automaticPromotionId: id } }))
      )
        fail(
          409,
          'PROMOTION_IN_USE',
          'Mã đã có lịch sử đơn hàng. Hãy ngừng áp dụng để giữ lịch sử.',
        );
      await tx.coupon.delete({ where: { id } });
      await recordAdminActivity(tx, actorId, 'PROMOTION_DELETED', id, {
        before,
      });
      return { id, deleted: true };
    });
  }
  create(actorId: string, dto: CreatePromotionDto) {
    return this.write(async (tx) => {
      await this.actor(tx, actorId);
      const { productIds, ...fields } = dto;
      const data = {
        ...fields,
        code:
          dto.code || `AUTO_${randomUUID().replaceAll('-', '').slice(0, 27)}`,
        name: dto.name.trim(),
        startsAt: dto.startsAt ? new Date(dto.startsAt) : null,
        expiresAt: dto.expiresAt ? new Date(dto.expiresAt) : null,
      };
      this.validate(data);
      await this.targeting(tx, data, productIds);
      const coupon = await tx.coupon.create({
        data: {
          ...data,
          products: { create: productIds.map((productId) => ({ productId })) },
        },
      });
      await recordAdminActivity(tx, actorId, 'PROMOTION_CREATED', coupon.id, {
        after: coupon,
      });
      return coupon;
    });
  }
  update(actorId: string, id: string, dto: UpdatePromotionDto) {
    return this.write(async (tx) => {
      await this.actor(tx, actorId);
      await tx.$queryRaw`SELECT id FROM "Coupon" WHERE id=${id}::uuid FOR UPDATE`;
      const existing = await tx.coupon.findUnique({
        where: { id },
        include: { products: true },
      });
      if (!existing) throw new NotFoundException();
      const { expectedVersion, startsAt, expiresAt, productIds, ...fields } =
        dto;
      if (
        fields.application != null &&
        fields.application !== existing.application
      )
        fail(
          400,
          'PROMOTION_INVALID',
          'Không đổi cách áp dụng của chương trình đã tạo; hãy tạo chương trình mới.',
        );
      if (existing.version !== expectedVersion)
        fail(
          409,
          'VERSION_CONFLICT',
          'Promotion changed; reload before saving',
        );
      const data = { ...fields, ...this.dates({ startsAt, expiresAt }) };
      for (const key of Object.keys(data) as Array<keyof typeof data>)
        if (data[key] === undefined) delete data[key];
      for (const field of [
        'kind',
        'amount',
        'active',
        'minSubtotal',
        'perUserLimit',
        'application',
        'scope',
        'name',
      ] as const)
        if (field in data && data[field] === null)
          fail(
            400,
            'PROMOTION_INVALID',
            'Required promotion value cannot be null',
          );
      this.validate({ ...existing, ...data });
      const targets =
        productIds ??
        (data.scope === 'ALL' ? [] : existing.products.map((p) => p.productId));
      // A deleted product cascades out of the target list. Administrators must
      // still be able to turn off that program after its last product is gone.
      const disablingOnly =
        data.active === false &&
        Object.keys(data).length === 1 &&
        productIds === undefined;
      if (!disablingOnly)
        await this.targeting(tx, { ...existing, ...data }, targets);
      const updated = await tx.coupon.update({
        where: { id },
        data: {
          ...data,
          version: { increment: 1 },
          products: {
            deleteMany: {},
            create: targets.map((productId) => ({ productId })),
          },
        },
      });
      await recordAdminActivity(tx, actorId, 'PROMOTION_UPDATED', id, {
        before: existing,
        after: updated,
      });
      return updated;
    });
  }
  list(q: AdminPromotionsQueryDto) {
    return listPromotions(this.db, q);
  }
  summary() {
    return promotionsSummary(this.db);
  }
  get(id: string) {
    return promotionDetail(this.db, id);
  }
  history(id: string, q: PageDto) {
    return promotionHistory(this.db, id, q);
  }
  async discount(
    tx: Prisma.TransactionClient,
    userId: string,
    code: string,
    subtotal: Prisma.Decimal,
    items?: { productId: string; price: Prisma.Decimal; quantity: number }[],
  ) {
    await tx.$queryRaw`SELECT id FROM "Coupon" WHERE code=${code} FOR UPDATE`;
    const coupon = await tx.coupon.findUnique({
        where: { code },
        include: { products: true },
      }),
      now = new Date();
    if (
      !coupon ||
      coupon.application !== 'CODE' ||
      !coupon.active ||
      (coupon.startsAt && coupon.startsAt > now) ||
      (coupon.expiresAt && coupon.expiresAt <= now) ||
      subtotal.lt(coupon.minSubtotal)
    )
      fail(
        409,
        'PROMOTION_UNAVAILABLE',
        'Promotion is inactive, expired or does not meet the minimum spend',
      );
    const total = await tx.couponRedemption.count({
        where: { couponId: coupon.id, releasedAt: null },
      }),
      personal = await tx.couponRedemption.count({
        where: { couponId: coupon.id, userId, releasedAt: null },
      });
    if (
      (coupon.usageLimit !== null && total >= coupon.usageLimit) ||
      personal >= coupon.perUserLimit
    )
      fail(409, 'PROMOTION_LIMIT_REACHED', 'Promotion usage limit reached');
    const eligible =
      coupon.scope === 'ALL'
        ? subtotal
        : totalForItems(
            (items ?? []).filter((i) =>
              coupon.products.some((p) => p.productId === i.productId),
            ),
          );
    if (eligible.lte(0))
      fail(
        409,
        'PROMOTION_UNAVAILABLE',
        'Giỏ hàng không có sản phẩm thuộc khuyến mãi.',
      );
    return {
      couponId: coupon.id,
      code: coupon.code,
      discount: discountFor(eligible, coupon),
    };
  }
  preview(userId: string, dto: PreviewPromotionDto) {
    return transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      const cart = await tx.cart.findUnique({
        where: { userId },
        include: cartInclude,
      });
      if (!cart?.items.length) fail(400, 'CART_EMPTY', 'Cart is empty');
      if (cart.version !== dto.cartVersion)
        fail(
          409,
          'VERSION_CONFLICT',
          'Cart changed; reload before applying promotion',
        );
      const offers = await automaticOffers(tx);
      const items = cart.items.map((i) => ({
        productId: i.variant.productId,
        price: automaticPrice(i.variant.productId, i.variant.price, offers)
          .price,
        quantity: i.quantity,
      }));
      const subtotal = totalForItems(items),
        shipping = shippingFee(subtotal, dto.shippingMethod);
      const discount = await this.discount(
        tx,
        userId,
        dto.code,
        subtotal,
        items,
      );
      return {
        code: discount.code,
        discount: discount.discount,
        subtotal,
        shipping,
        total: subtotal.plus(shipping).minus(discount.discount),
        cartVersion: cart.version,
      };
    });
  }
}
