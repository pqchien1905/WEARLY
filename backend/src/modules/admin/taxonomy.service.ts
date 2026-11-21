import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { CategoryDto, RenameTaxonomyDto } from './dto/admin.dto';
import { recordAdminActivity } from './audit';
import { Prisma } from '../../generated/prisma/client';
import { lockCatalogActor } from './catalog-write';
import { AdminCategoriesQueryDto } from './dto/admin-categories-query.dto';
import {
  categoryList,
  categorySummary,
  categoryDetail,
} from './categories-workspace';

import {
  taxonomyList,
  taxonomySummary,
  taxonomyDetail,
} from './taxonomy-workspace';
import { AdminTaxonomyQueryDto } from './dto/admin-taxonomy-query.dto';
type Kind = 'categories' | 'brands';

@Injectable()
export class TaxonomyService {
  constructor(private readonly db: PrismaService) {}

  categories(q: AdminCategoriesQueryDto) {
    return categoryList(this.db, q);
  }
  categorySummary() {
    return categorySummary(this.db);
  }
  categoryDetail(id: string) {
    return categoryDetail(this.db, id);
  }

  deleteCategory(actorId: string, id: string, expectedUpdatedAt: string) {
    return this.remove(actorId, 'categories', id, expectedUpdatedAt);
  }
  deleteBrand(actorId: string, id: string, expectedUpdatedAt: string) {
    return this.remove(actorId, 'brands', id, expectedUpdatedAt);
  }
  private remove(
    actorId: string,
    kind: Kind,
    id: string,
    expectedUpdatedAt: string,
  ) {
    const category = kind === 'categories';
    const label = category ? 'Danh mục' : 'Thương hiệu';
    const inUse = () =>
      fail(
        409,
        category ? 'CATEGORY_IN_USE' : 'BRAND_IN_USE',
        `${label} đang chứa sản phẩm. Chuyển sản phẩm trước khi xóa.`,
      );
    return transaction(this.db, async (tx) => {
      await lockCatalogActor(tx, actorId);
      // Lock the parent before checking children; concurrent FK attachment must wait.
      const table = category ? Prisma.sql`"Category"` : Prisma.sql`"Brand"`;
      await tx.$queryRaw(
        Prisma.sql`SELECT id FROM ${table} WHERE id=${id}::uuid FOR UPDATE`,
      );
      const row = category
        ? await tx.category.findUnique({ where: { id } })
        : await tx.brand.findUnique({ where: { id } });
      if (!row) throw new NotFoundException();
      if (
        row.updatedAt.toISOString() !==
        new Date(expectedUpdatedAt).toISOString()
      )
        fail(
          409,
          'VERSION_CONFLICT',
          `${label} đã thay đổi. Tải lại trước khi xóa.`,
        );
      if (
        await tx.product.count({
          where: category ? { categoryId: id } : { brandId: id },
        })
      )
        inUse();
      if (category) await tx.category.delete({ where: { id } });
      else await tx.brand.delete({ where: { id } });
      await recordAdminActivity(
        tx,
        actorId,
        category ? 'CATEGORY_DELETED' : 'BRAND_DELETED',
        id,
        {
          before: row,
        },
      );
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

  brands(q: AdminTaxonomyQueryDto) {
    return taxonomyList(this.db, 'brands', q);
  }
  brandSummary() {
    return taxonomySummary(this.db, 'brands');
  }
  brandDetail(id: string) {
    return taxonomyDetail(this.db, 'brands', id);
  }

  async create(actorId: string, kind: Kind, dto: CategoryDto) {
    const data = { name: dto.name, slug: dto.slug };
    try {
      return await transaction(this.db, async (tx) => {
        await lockCatalogActor(tx, actorId);
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
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      )
        fail(
          409,
          'TAXONOMY_SLUG_EXISTS',
          'Đường dẫn đã được sử dụng. Vui lòng chọn đường dẫn khác.',
        );
      throw error;
    }
  }

  rename(actorId: string, kind: Kind, id: string, dto: RenameTaxonomyDto) {
    return transaction(this.db, async (tx) => {
      await lockCatalogActor(tx, actorId);
      const where = { id };
      const existing =
        kind === 'categories'
          ? await tx.category.findUnique({ where })
          : await tx.brand.findUnique({ where });
      if (!existing) throw new NotFoundException();
      if (
        existing.name !== dto.expectedName ||
        (dto.expectedUpdatedAt !== undefined &&
          existing.updatedAt.toISOString() !==
            new Date(dto.expectedUpdatedAt).toISOString())
      )
        fail(
          409,
          'VERSION_CONFLICT',
          'Dữ liệu đã thay đổi. Hãy tải lại trước khi chỉnh sửa.',
        );
      if (existing.name === dto.name) return existing;
      const args = {
        where: { id, name: dto.expectedName, updatedAt: existing.updatedAt },
        data: {
          name: dto.name,
          updatedAt: new Date(
            Math.max(Date.now(), existing.updatedAt.getTime() + 1),
          ),
        },
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
