import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { PageDto } from '../products/dto/query-products.dto';
import { catalogInclude } from '../products/products.service';
import { publicUser } from '../auth/auth.service';
import {
  AdjustInventoryDto,
  CategoryDto,
  CreateProductDto,
  CreateSkuDto,
  OrderStatusDto,
  UpdateProductDto,
  UpdateSkuDto,
} from './dto/admin.dto';
@Injectable()
export class AdminService {
  constructor(private readonly db: PrismaService) {}
  async list(kind: 'products' | 'inventory' | 'orders' | 'users', q: PageDto) {
    const args = {
      skip: (q.page - 1) * q.limit,
      take: q.limit,
      orderBy: { createdAt: 'desc' as const },
    };
    if (kind === 'products')
      return {
        items: await this.db.product.findMany({
          ...args,
          include: catalogInclude,
        }),
        total: await this.db.product.count(),
        page: q.page,
        limit: q.limit,
      };
    if (kind === 'inventory')
      return {
        items: await this.db.inventory.findMany({
          ...args,
          include: { variant: true },
        }),
        total: await this.db.inventory.count(),
        page: q.page,
        limit: q.limit,
      };
    if (kind === 'orders')
      return {
        items: await this.db.order.findMany({
          ...args,
          include: { items: true, payment: true },
        }),
        total: await this.db.order.count(),
        page: q.page,
        limit: q.limit,
      };
    return {
      items: (await this.db.user.findMany(args)).map(publicUser),
      total: await this.db.user.count(),
      page: q.page,
      limit: q.limit,
    };
  }
  createProduct(dto: CreateProductDto) {
    return this.db.product.create({ data: dto });
  }
  updateProduct(id: string, dto: UpdateProductDto) {
    return this.db.product.update({ where: { id }, data: dto });
  }
  createSku(dto: CreateSkuDto) {
    return this.db.productVariant.create({
      data: { ...dto, inventory: { create: { quantity: 0 } } },
    });
  }
  updateSku(id: string, dto: UpdateSkuDto) {
    return this.db.productVariant.update({ where: { id }, data: dto });
  }
  category(dto: CategoryDto) {
    return this.db.category.create({ data: dto });
  }
  adjust(id: string, dto: AdjustInventoryDto) {
    return transaction(this.db, async (tx) => {
      const inv = await tx.inventory.findUnique({ where: { id } });
      if (!inv) throw new NotFoundException();
      const changed = await tx.inventory.updateMany({
        where: {
          id,
          version: dto.expectedVersion,
          quantity: { gte: Math.max(0, -dto.delta) },
        },
        data: { quantity: { increment: dto.delta }, version: { increment: 1 } },
      });
      if (changed.count !== 1)
        fail(
          409,
          'VERSION_CONFLICT',
          'Inventory changed or quantity would be negative',
        );
      await tx.inventoryMovement.create({
        data: {
          inventoryId: id,
          delta: dto.delta,
          reason: 'ADMIN: ' + dto.reason,
        },
      });
      return tx.inventory.findUniqueOrThrow({ where: { id } });
    });
  }
  status(id: string, dto: OrderStatusDto) {
    return transaction(this.db, async (tx) => {
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
      // Delivery is not proof of payment: payment stays PENDING until a separate
      // settlement workflow is implemented.
      return tx.order.findUniqueOrThrow({
        where: { id },
        include: { items: true, payment: true },
      });
    });
  }
}
