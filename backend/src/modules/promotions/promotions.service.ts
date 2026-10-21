import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { transaction, lockUser } from '../../common/transaction';
import { fail } from '../../common/errors';
import { discountFor, shippingFee, totalForItems } from '../../common/money';
import { recordAdminActivity } from '../admin/audit';
import { cartInclude } from '../cart/cart.service';
import { PageDto } from '../products/dto/query-products.dto';
import {
  CreatePromotionDto,
  UpdatePromotionDto,
  PreviewPromotionDto,
} from './promotions.dto';
@Injectable()
export class PromotionsService {
  constructor(private readonly db: PrismaService) {}
  private validate(value: {
    kind: string;
    amount: string | Prisma.Decimal;
    maxDiscount?: string | Prisma.Decimal | null;
    startsAt?: Date | null;
    expiresAt?: Date | null;
  }) {
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
  create(actorId: string, dto: CreatePromotionDto) {
    return transaction(this.db, async (tx) => {
      const data = {
        ...dto,
        startsAt: dto.startsAt ? new Date(dto.startsAt) : null,
        expiresAt: dto.expiresAt ? new Date(dto.expiresAt) : null,
      };
      this.validate(data);
      const coupon = await tx.coupon.create({ data });
      await recordAdminActivity(tx, actorId, 'PROMOTION_CREATED', coupon.id, {
        after: coupon,
      });
      return coupon;
    });
  }
  update(actorId: string, id: string, dto: UpdatePromotionDto) {
    return transaction(this.db, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "Coupon" WHERE id=${id}::uuid FOR UPDATE`;
      const existing = await tx.coupon.findUnique({ where: { id } });
      if (!existing) throw new NotFoundException();
      const { expectedVersion, startsAt, expiresAt, ...fields } = dto;
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
      ] as const)
        if (field in data && data[field] === null)
          fail(
            400,
            'PROMOTION_INVALID',
            'Required promotion value cannot be null',
          );
      this.validate({ ...existing, ...data });
      const updated = await tx.coupon.update({
        where: { id },
        data: { ...data, version: { increment: 1 } },
      });
      await recordAdminActivity(tx, actorId, 'PROMOTION_UPDATED', id, {
        before: existing,
        after: updated,
      });
      return updated;
    });
  }
  async list(q: PageDto) {
    const [items, total] = await this.db.$transaction([
      this.db.coupon.findMany({
        orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
        skip: (q.page - 1) * q.limit,
        take: q.limit,
        include: {
          _count: { select: { redemptions: { where: { releasedAt: null } } } },
        },
      }),
      this.db.coupon.count(),
    ]);
    return { items, total, page: q.page, limit: q.limit };
  }
  async get(id: string) {
    const coupon = await this.db.coupon.findUnique({
      where: { id },
      include: {
        _count: { select: { redemptions: { where: { releasedAt: null } } } },
      },
    });
    if (!coupon) throw new NotFoundException();
    return coupon;
  }
  async discount(
    tx: Prisma.TransactionClient,
    userId: string,
    code: string,
    subtotal: Prisma.Decimal,
  ) {
    await tx.$queryRaw`SELECT id FROM "Coupon" WHERE code=${code} FOR UPDATE`;
    const coupon = await tx.coupon.findUnique({ where: { code } }),
      now = new Date();
    if (
      !coupon ||
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
    return {
      couponId: coupon.id,
      code: coupon.code,
      discount: discountFor(subtotal, coupon),
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
      const subtotal = totalForItems(
          cart.items.map((i) => ({
            price: i.variant.price,
            quantity: i.quantity,
          })),
        ),
        shipping = shippingFee(subtotal, dto.shippingMethod);
      const discount = await this.discount(tx, userId, dto.code, subtotal);
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
