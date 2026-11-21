import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, StoreCollection } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { can } from '../../common/permissions';
import {
  AdminCollectionsQueryDto,
  CollectionCoverQueryDto,
} from '../admin/dto/admin-collections-query.dto';
import {
  listCollections,
  collectionsSummary,
  collectionAdminDetail,
  collectionCovers,
} from '../admin/collections-workspace';
import { transaction, lockUser } from '../../common/transaction';
import { fail } from '../../common/errors';
import { recordAdminActivity } from '../admin/audit';
import { ProductsService, publicProductWhere } from './products.service';
import { PageDto, QueryProductsDto } from './dto/query-products.dto';
import { CreateCollectionDto, UpdateCollectionDto } from './collections.dto';

@Injectable()
export class CollectionsService {
  constructor(
    private readonly db: PrismaService,
    private readonly products: ProductsService,
  ) {}
  adminList(q: AdminCollectionsQueryDto) {
    return listCollections(this.db, q);
  }
  adminSummary() {
    return collectionsSummary(this.db);
  }
  adminDetail(id: string) {
    return collectionAdminDetail(this.db, id);
  }
  covers(q: CollectionCoverQueryDto) {
    return collectionCovers(this.db, q);
  }
  async styles() {
    const rows = await this.db.$queryRaw<
      { style: string }[]
    >`SELECT style FROM "Product" WHERE length(btrim(style)) BETWEEN 1 AND 100 UNION SELECT style FROM "StoreCollection" ORDER BY style`;
    return { styles: rows.map((r) => r.style) };
  }
  private async actor(tx: Prisma.TransactionClient, actorId: string) {
    await lockUser(tx, actorId);
    const user = await tx.user.findUnique({
      where: { id: actorId },
      select: { active: true, role: true },
    });
    if (!user?.active || !can(user.role, 'content.manage'))
      fail(403, 'FORBIDDEN', 'Không có quyền quản lý bộ sưu tập.');
  }
  remove(actorId: string, id: string, expectedVersion: number) {
    return this.write(async (tx) => {
      await this.actor(tx, actorId);
      await tx.$queryRaw`SELECT id FROM "StoreCollection" WHERE id=${id}::uuid FOR UPDATE`;
      const before = await tx.storeCollection.findUnique({ where: { id } });
      if (!before) throw new NotFoundException();
      if (before.version !== expectedVersion)
        fail(
          409,
          'COLLECTION_CHANGED',
          'Bộ sưu tập đã thay đổi. Tải lại trước khi xóa.',
        );
      await tx.storeCollection.delete({ where: { id } });
      await recordAdminActivity(tx, actorId, 'COLLECTION_DELETED', id, {
        before,
      });
      return { id, deleted: true };
    });
  }
  private async summary(
    tx: Prisma.TransactionClient,
    collection: StoreCollection,
    productCount?: number,
  ) {
    const where = { ...publicProductWhere, style: collection.style };
    const select = {
      id: true,
      slug: true,
      name: true,
      images: {
        where: { url: { not: '' } },
        orderBy: [{ position: 'asc' as const }, { id: 'asc' as const }],
        take: 1,
      },
    };
    let cover = collection.coverProductId
      ? await tx.product.findFirst({
          where: { ...where, id: collection.coverProductId },
          select,
        })
      : null;
    cover ??= await tx.product.findFirst({
      where,
      select,
      orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
    });
    return {
      id: collection.id,
      slug: collection.slug,
      title: collection.title,
      description: collection.description,
      style: collection.style,
      productCount: productCount ?? (await tx.product.count({ where })),
      cover: cover
        ? {
            productId: cover.id,
            productSlug: cover.slug,
            url: cover.images[0].url,
            alt: cover.images[0].alt || cover.name,
          }
        : null,
    };
  }
  async list(q: PageDto, admin = false) {
    return this.db.$transaction(
      async (tx) => {
        const groups = await tx.product.groupBy({
          by: ['style'],
          where: publicProductWhere,
          _count: { _all: true },
        });
        const counts = new Map(
          groups.map((group) => [group.style, group._count._all]),
        );
        const where = admin
          ? {}
          : { active: true, style: { in: [...counts.keys()] } };
        const total = await tx.storeCollection.count({ where });
        const rows = await tx.storeCollection.findMany({
          where,
          skip: (q.page - 1) * q.limit,
          take: q.limit,
          orderBy: [{ position: 'asc' }, { id: 'asc' }],
        });
        const items = [];
        for (const row of rows) {
          const summary = await this.summary(
            tx,
            row,
            counts.get(row.style) ?? 0,
          );
          items.push(admin ? { ...row, ...summary } : summary);
        }
        return { items, total, page: q.page, limit: q.limit };
      },
      { isolationLevel: 'RepeatableRead' },
    );
  }
  async detail(slug: string, q: QueryProductsDto) {
    const collection = await this.db.$transaction(
      async (tx) => {
        const row = await tx.storeCollection.findFirst({
          where: { slug, active: true },
        });
        if (!row) throw new NotFoundException();
        return this.summary(tx, row);
      },
      { isolationLevel: 'RepeatableRead' },
    );
    // A client cannot escape this collection by overriding its style filter.
    const page = await this.products.list({ ...q, style: collection.style });
    return { collection, ...page };
  }
  private async validate(
    tx: Prisma.TransactionClient,
    data: { slug: string; style: string; coverProductId?: string | null },
    id?: string,
  ) {
    const duplicate = await tx.storeCollection.findFirst({
      where: {
        ...(id ? { id: { not: id } } : {}),
        OR: [{ slug: data.slug }, { style: data.style }],
      },
      select: { id: true },
    });
    if (duplicate)
      fail(
        409,
        'DUPLICATE_COLLECTION',
        'Collection slug or style already exists',
      );
    if (
      data.coverProductId &&
      !(await tx.product.findFirst({
        where: {
          id: data.coverProductId,
          style: data.style,
          ...publicProductWhere,
        },
        select: { id: true },
      }))
    )
      fail(
        400,
        'INVALID_COLLECTION_COVER',
        'Cover must be a published product in this collection',
      );
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
        fail(
          409,
          'DUPLICATE_COLLECTION',
          'Collection slug or style already exists',
        );
      throw e;
    }
  }
  create(actorId: string, dto: CreateCollectionDto) {
    return this.write(async (tx) => {
      await this.actor(tx, actorId);
      await this.validate(tx, dto);
      const row = await tx.storeCollection.create({ data: dto });
      await recordAdminActivity(tx, actorId, 'COLLECTION_CREATED', row.id, {
        after: row,
      });
      return row;
    });
  }
  update(actorId: string, id: string, dto: UpdateCollectionDto) {
    const { expectedVersion, ...data } = dto;
    return this.write(async (tx) => {
      await this.actor(tx, actorId);
      await tx.$queryRaw`SELECT id FROM "StoreCollection" WHERE id=${id}::uuid FOR UPDATE`;
      const before = await tx.storeCollection.findUnique({ where: { id } });
      if (!before) throw new NotFoundException();
      if (before.version !== expectedVersion)
        fail(
          409,
          'COLLECTION_CHANGED',
          'Collection changed; reload before saving',
        );
      // Existing covers may have been archived since the last edit. They fall
      // back publicly; only a new cover or changed style must validate again.
      const merged = { ...before, ...data };
      await this.validate(
        tx,
        {
          ...merged,
          coverProductId:
            data.coverProductId !== undefined ||
            (data.style !== undefined && data.style !== before.style)
              ? merged.coverProductId
              : null,
        },
        id,
      );
      const row = await tx.storeCollection.update({
        where: { id },
        data: { ...data, version: { increment: 1 } },
      });
      await recordAdminActivity(tx, actorId, 'COLLECTION_UPDATED', id, {
        before,
        after: row,
      });
      return row;
    });
  }
}
