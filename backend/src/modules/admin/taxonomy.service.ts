import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { PageDto } from '../products/dto/query-products.dto';
import { CategoryDto, RenameTaxonomyDto } from './dto/admin.dto';
import { recordAdminActivity } from './audit';

type Kind = 'categories' | 'brands';

@Injectable()
export class TaxonomyService {
  constructor(private readonly db: PrismaService) {}

  list(kind: Kind, q: PageDto) {
    return this.db.$transaction(
      async (tx) => {
        const args = {
          skip: (q.page - 1) * q.limit,
          take: q.limit,
          orderBy: [{ name: 'asc' as const }, { id: 'asc' as const }],
          include: { _count: { select: { products: true } } },
        };
        const items =
          kind === 'categories'
            ? await tx.category.findMany(args)
            : await tx.brand.findMany(args);
        return {
          items,
          total:
            kind === 'categories'
              ? await tx.category.count()
              : await tx.brand.count(),
          page: q.page,
          limit: q.limit,
        };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }

  create(actorId: string, kind: Kind, dto: CategoryDto) {
    const data = { name: dto.name, slug: dto.slug };
    return transaction(this.db, async (tx) => {
      const row =
        kind === 'categories'
          ? await tx.category.create({ data })
          : await tx.brand.create({ data });
      await recordAdminActivity(
        tx,
        actorId,
        kind === 'categories' ? 'CATEGORY_CREATED' : 'BRAND_CREATED',
        row.id,
      );
      return row;
    });
  }

  rename(actorId: string, kind: Kind, id: string, dto: RenameTaxonomyDto) {
    return transaction(this.db, async (tx) => {
      const where = { id };
      const existing =
        kind === 'categories'
          ? await tx.category.findUnique({ where })
          : await tx.brand.findUnique({ where });
      if (!existing) throw new NotFoundException();
      const args = {
        where: { id, name: dto.expectedName },
        data: { name: dto.name },
      };
      const changed =
        kind === 'categories'
          ? await tx.category.updateMany(args)
          : await tx.brand.updateMany(args);
      if (!changed.count)
        fail(
          409,
          'VERSION_CONFLICT',
          'Tên đã được thay đổi. Vui lòng tải lại trước khi chỉnh sửa.',
        );
      await recordAdminActivity(
        tx,
        actorId,
        kind === 'categories' ? 'CATEGORY_RENAMED' : 'BRAND_RENAMED',
        id,
      );
      return kind === 'categories'
        ? tx.category.findUniqueOrThrow({ where })
        : tx.brand.findUniqueOrThrow({ where });
    });
  }
}
