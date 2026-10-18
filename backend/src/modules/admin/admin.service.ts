import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { PageDto } from '../products/dto/query-products.dto';
import { publicUser } from '../auth/auth.service';
import {
  AdjustInventoryDto,
  CreateProductDto,
  CreateSkuDto,
  OrderStatusDto,
  UpdateProductDto,
  UpdateSkuDto,
} from './dto/admin.dto';
const adminProductInclude = {
  category: true,
  brand: true,
  images: { orderBy: { position: 'asc' as const } },
  variants: { orderBy: { sku: 'asc' as const }, include: { inventory: true } },
};
const adminOrderInclude = {
  items: true,
  payment: true,
  user: { select: { email: true, name: true } },
};
@Injectable()
export class AdminService {
  constructor(private readonly db: PrismaService) {}
  async summary() {
    const [products, inventory, orders, pendingOrders, customers] =
      await this.db.$transaction([
        this.db.product.count(),
        this.db.inventory.aggregate({ _sum: { quantity: true } }),
        this.db.order.count(),
        this.db.order.count({ where: { status: 'PENDING' } }),
        this.db.user.count({ where: { role: 'CUSTOMER' } }),
      ]);
    return {
      products,
      inventoryUnits: inventory._sum.quantity ?? 0,
      orders,
      pendingOrders,
      customers,
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
  async list(kind: 'products' | 'inventory' | 'orders' | 'users', q: PageDto) {
    const args = {
      skip: (q.page - 1) * q.limit,
      take: q.limit,
      orderBy: [{ createdAt: 'desc' as const }, { id: 'desc' as const }],
    };
    if (kind === 'products')
      return {
        items: await this.db.product.findMany({
          ...args,
          include: adminProductInclude,
        }),
        total: await this.db.product.count(),
        page: q.page,
        limit: q.limit,
      };
    if (kind === 'inventory')
      return {
        items: await this.db.inventory.findMany({
          ...args,
          include: {
            variant: {
              include: { product: { select: { name: true, active: true } } },
            },
          },
        }),
        total: await this.db.inventory.count(),
        page: q.page,
        limit: q.limit,
      };
    if (kind === 'orders')
      return {
        items: await this.db.order.findMany({
          ...args,
          include: adminOrderInclude,
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
    const { images, ...data } = dto;
    return this.db.product.create({
      data: {
        ...data,
        images: images
          ? {
              create: images.map((image, position) => ({ ...image, position })),
            }
          : undefined,
      },
      include: adminProductInclude,
    });
  }
  updateProduct(id: string, dto: UpdateProductDto) {
    const { images, ...data } = dto;
    // Explicit delete then create avoids a unique(productId,position) collision.
    // The transaction rolls back both metadata and gallery if any write fails.
    return transaction(this.db, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "Product" WHERE id = ${id}::uuid FOR UPDATE`;
      if (images !== undefined)
        await tx.productImage.deleteMany({ where: { productId: id } });
      return tx.product.update({
        where: { id },
        data: {
          ...data,
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
    });
  }
  createSku(dto: CreateSkuDto) {
    return this.db.productVariant.create({
      data: { ...dto, inventory: { create: { quantity: 0 } } },
    });
  }
  updateSku(id: string, dto: UpdateSkuDto) {
    return this.db.productVariant.update({ where: { id }, data: dto });
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
        include: adminOrderInclude,
      });
    });
  }
}
