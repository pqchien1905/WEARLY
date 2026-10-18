import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { lockUser, transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import {
  CreateReviewDto,
  ReviewPageDto,
  ReviewVersionDto,
  UpdateReviewDto,
} from './review.dto';

const reviewSelect = {
  id: true,
  rating: true,
  comment: true,
  createdAt: true,
  updatedAt: true,
} as const;
type Db = Prisma.TransactionClient;

@Injectable()
export class ReviewsService {
  constructor(private readonly db: PrismaService) {}
  history(userId: string, q: ReviewPageDto) {
    return this.db.$transaction(
      async (tx) => {
        const where = { userId };
        const rows = await tx.review.findMany({
          where,
          select: {
            ...reviewSelect,
            productId: true,
            product: {
              select: {
                name: true,
                slug: true,
                active: true,
                variants: {
                  where: { active: true },
                  take: 1,
                  select: { id: true },
                },
              },
            },
          },
          skip: (q.page - 1) * q.limit,
          take: q.limit,
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        });
        const total = await tx.review.count({ where });
        const purchases = rows.length
          ? await tx.product.findMany({
              where: {
                id: { in: rows.map((r) => r.productId) },
                variants: {
                  some: {
                    orderItems: {
                      some: { order: { userId, status: 'DELIVERED' } },
                    },
                  },
                },
              },
              select: { id: true },
            })
          : [];
        const purchased = new Set(purchases.map((p) => p.id));
        return {
          items: rows.map(({ product, ...review }) => {
            const available = product.active && product.variants.length > 0;
            return {
              ...review,
              product: available
                ? { name: product.name, slug: product.slug }
                : null,
              canEdit: available && purchased.has(review.productId),
            };
          }),
          total,
          page: q.page,
          limit: q.limit,
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  private async product(tx: Db, id: string) {
    const product = await tx.product.findUnique({
      where: { id },
      select: {
        active: true,
        variants: { where: { active: true }, take: 1, select: { id: true } },
      },
    });
    if (!product) throw new NotFoundException();
    return product.active && product.variants.length > 0;
  }
  private async purchased(tx: Db, userId: string, productId: string) {
    return !!(await tx.orderItem.findFirst({
      where: { variant: { productId }, order: { userId, status: 'DELIVERED' } },
      select: { id: true },
    }));
  }
  list(productId: string, q: ReviewPageDto) {
    return this.db.$transaction(
      async (tx) => {
        if (!(await this.product(tx, productId))) throw new NotFoundException();
        const where: Prisma.ReviewWhereInput = {
          productId,
          rating: { gte: 1, lte: 5 },
          user: {
            orders: {
              some: {
                status: 'DELIVERED',
                items: { some: { variant: { productId } } },
              },
            },
          },
        };
        const items = await tx.review.findMany({
          where,
          select: reviewSelect,
          skip: (q.page - 1) * q.limit,
          take: q.limit,
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        });
        const aggregate = await tx.review.aggregate({
          where,
          _count: true,
          _avg: { rating: true },
        });
        return {
          items,
          total: aggregate._count,
          page: q.page,
          limit: q.limit,
          average:
            aggregate._avg.rating === null
              ? null
              : Math.round(aggregate._avg.rating * 10) / 10,
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  mine(userId: string, productId: string) {
    return this.db.$transaction(
      async (tx) => {
        const available = await this.product(tx, productId);
        const review = await tx.review.findUnique({
          where: { userId_productId: { userId, productId } },
          select: reviewSelect,
        });
        return {
          review,
          canReview: available && (await this.purchased(tx, userId, productId)),
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  save(
    userId: string,
    productId: string,
    dto: CreateReviewDto | UpdateReviewDto,
  ) {
    return transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      if (!(await this.product(tx, productId))) throw new NotFoundException();
      if (!(await this.purchased(tx, userId, productId)))
        fail(
          403,
          'PURCHASE_REQUIRED',
          'Bạn chỉ có thể đánh giá sản phẩm trong đơn đã giao.',
        );
      const data = { rating: dto.rating, comment: dto.comment };
      if (!('expectedUpdatedAt' in dto))
        return tx.review.create({
          data: { ...data, userId, productId },
          select: reviewSelect,
        });
      const existing = await tx.review.findUnique({
        where: { userId_productId: { userId, productId } },
      });
      if (!existing) throw new NotFoundException();
      const changed = await tx.review.updateMany({
        where: { id: existing.id, updatedAt: new Date(dto.expectedUpdatedAt) },
        data: {
          ...data,
          updatedAt: new Date(
            Math.max(Date.now(), existing.updatedAt.getTime() + 1),
          ),
        },
      });
      if (!changed.count)
        fail(
          409,
          'VERSION_CONFLICT',
          'Đánh giá đã thay đổi. Hãy tải lại trước khi sửa.',
        );
      return tx.review.findUniqueOrThrow({
        where: { id: existing.id },
        select: reviewSelect,
      });
    });
  }
  remove(userId: string, productId: string, dto: ReviewVersionDto) {
    return transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      const existing = await tx.review.findUnique({
        where: { userId_productId: { userId, productId } },
      });
      if (!existing) return { deleted: true };
      const removed = await tx.review.deleteMany({
        where: { id: existing.id, updatedAt: new Date(dto.expectedUpdatedAt) },
      });
      if (!removed.count)
        fail(
          409,
          'VERSION_CONFLICT',
          'Đánh giá đã thay đổi. Hãy tải lại trước khi xóa.',
        );
      return { deleted: true };
    });
  }
}
