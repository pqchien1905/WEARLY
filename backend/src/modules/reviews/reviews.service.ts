import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { lockUser, transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { recordAdminActivity } from '../admin/audit';
import {
  AdminReviewQueryDto,
  CreateReviewDto,
  OwnedReviewPageDto,
  ReviewPageDto,
  ReviewVersionDto,
  ReviewVisibilityDto,
  UpdateReviewDto,
} from './review.dto';

const reviewSelect = {
  id: true,
  rating: true,
  comment: true,
  createdAt: true,
  updatedAt: true,
} as const;
const ownedSelect = {
  ...reviewSelect,
  hiddenAt: true,
  hiddenReason: true,
} as const;
type Db = Prisma.TransactionClient;

@Injectable()
export class ReviewsService {
  constructor(private readonly db: PrismaService) {}
  history(userId: string, q: OwnedReviewPageDto) {
    return this.db.$transaction(
      async (tx) => {
        const where: Prisma.ReviewWhereInput = {
          userId,
          ...(q.rating ? { rating: q.rating } : {}),
          // Search every owned page. Hidden product metadata must not become
          // discoverable through search, even though its review is still owned.
          ...(q.q
            ? {
                AND: q.q.split(/\s+/).map((part) => {
                  const word = part.replace(/[\\%_]/g, '\\$&');
                  return {
                    OR: [
                      {
                        comment: {
                          contains: word,
                          mode: 'insensitive' as const,
                        },
                      },
                      {
                        product: {
                          active: true,
                          variants: { some: { active: true } },
                          name: {
                            contains: word,
                            mode: 'insensitive' as const,
                          },
                        },
                      },
                    ],
                  };
                }),
              }
            : {}),
        };
        const rows = await tx.review.findMany({
          where,
          select: {
            ...ownedSelect,
            productId: true,
            product: {
              select: {
                name: true,
                slug: true,
                active: true,
                images: {
                  orderBy: { position: 'asc' },
                  take: 1,
                  select: { url: true },
                },
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
                ? {
                    name: product.name,
                    slug: product.slug,
                    image: product.images[0]?.url ?? null,
                  }
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
          hiddenAt: null,
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
          select: ownedSelect,
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
          select: ownedSelect,
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
        select: ownedSelect,
      });
    });
  }
  adminList(q: AdminReviewQueryDto) {
    return this.db.$transaction(
      async (tx) => {
        const words = (q.q ?? '').split(/\s+/).filter(Boolean);
        const where: Prisma.ReviewWhereInput = {
          ...(q.rating ? { rating: q.rating } : {}),
          ...(q.productId ? { productId: q.productId } : {}),
          ...(q.visibility === 'all'
            ? {}
            : { hiddenAt: q.visibility === 'hidden' ? { not: null } : null }),
          ...(words.length
            ? {
                AND: words.map((part) => {
                  const word = part.replace(/[\\%_]/g, '\\$&');
                  const contains = { contains: word, mode: 'insensitive' as const };
                  return {
                    OR: [
                      { comment: contains },
                      { product: { name: contains } },
                      { user: { name: contains } },
                      { user: { email: contains } },
                    ],
                  };
                }),
              }
            : {}),
        };
        const [items, total, hidden, all] = await Promise.all([
          tx.review.findMany({
            where,
            select: {
              ...reviewSelect,
              hiddenAt: true,
              hiddenReason: true,
              product: { select: { id: true, name: true, slug: true } },
              user: { select: { id: true, name: true, email: true } },
            },
            skip: (q.page - 1) * q.limit,
            take: q.limit,
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
          }),
          tx.review.count({ where }),
          tx.review.count({ where: { hiddenAt: { not: null } } }),
          tx.review.count(),
        ]);
        return {
          items,
          total,
          page: q.page,
          limit: q.limit,
          counts: { all, hidden, visible: all - hidden },
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  setVisibility(actorId: string, id: string, dto: ReviewVisibilityDto) {
    return transaction(this.db, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "Review" WHERE id=${id}::uuid FOR UPDATE`;
      const before = await tx.review.findUnique({ where: { id } });
      if (!before) throw new NotFoundException();
      // A retried decision that already applied is acknowledged, not repeated.
      if (
        !!before.hiddenAt === dto.hidden &&
        (!dto.hidden || before.hiddenReason === dto.reason)
      )
        return before;
      // The moderator decided on the text they saw; an edit since then needs a
      // fresh look before the decision applies.
      if (before.updatedAt.toISOString() !== dto.expectedUpdatedAt)
        fail(
          409,
          'VERSION_CONFLICT',
          'Đánh giá đã thay đổi. Hãy tải lại trước khi kiểm duyệt.',
        );
      const after = await tx.review.update({
        where: { id },
        data: {
          hiddenAt: dto.hidden ? (before.hiddenAt ?? new Date()) : null,
          hiddenReason: dto.hidden ? dto.reason : null,
          updatedAt: new Date(
            Math.max(Date.now(), before.updatedAt.getTime() + 1),
          ),
        },
      });
      await recordAdminActivity(
        tx,
        actorId,
        dto.hidden ? 'REVIEW_HIDDEN' : 'REVIEW_RESTORED',
        id,
        { before, after },
      );
      return after;
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
