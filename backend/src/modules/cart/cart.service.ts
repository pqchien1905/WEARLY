import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { transaction, lockUser } from '../../common/transaction';
import { fail } from '../../common/errors';
import { totalForItems } from '../../common/money';
import {
  automaticOffers,
  automaticPrice,
  AutomaticOffer,
} from '../promotions/automatic-pricing';
export const cartInclude = {
  items: {
    orderBy: { createdAt: 'asc' as const },
    include: {
      variant: {
        include: {
          inventory: true,
          product: {
            include: { images: { orderBy: { position: 'asc' as const } } },
          },
        },
      },
    },
  },
} satisfies Prisma.CartInclude;
export function cartJson(
  cart: Prisma.CartGetPayload<{ include: typeof cartInclude }>,
  offers: AutomaticOffer[] = [],
) {
  const items = cart.items.map((i) => ({
    id: i.id,
    sku: i.variant.sku,
    slug: i.variant.product.slug,
    name: i.variant.product.name,
    image: i.variant.product.images[0]?.url ?? '',
    size: i.variant.size,
    color: i.variant.color,
    unitPrice: automaticPrice(
      i.variant.productId,
      i.variant.price,
      offers,
    ).price.toString(),
    originalUnitPrice: i.variant.price.toString(),
    promotionName:
      automaticPrice(i.variant.productId, i.variant.price, offers).promotion
        ?.name ?? null,
    quantity: i.quantity,
    available:
      i.variant.active && i.variant.product.active
        ? (i.variant.inventory?.quantity ?? 0)
        : 0,
  }));
  return {
    id: cart.id,
    version: cart.version,
    items,
    subtotal: totalForItems(
      items.map((i) => ({ price: i.unitPrice, quantity: i.quantity })),
    ).toString(),
    currency: 'VND',
  };
}
@Injectable()
export class CartService {
  constructor(private readonly db: PrismaService) {}
  async get(userId: string) {
    return cartJson(
      await this.db.cart.upsert({
        where: { userId },
        create: { userId },
        update: {},
        include: cartInclude,
      }),
      await automaticOffers(this.db),
    );
  }
  mutate(
    userId: string,
    operation: 'add' | 'update' | 'delete',
    input: { sku?: string; id?: string; quantity?: number },
  ) {
    return transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      const cart = await tx.cart.upsert({
        where: { userId },
        create: { userId },
        update: {},
        include: cartInclude,
      });
      const existing =
        operation === 'add'
          ? cart.items.find((i) => i.variant.sku === input.sku)
          : cart.items.find((i) => i.id === input.id);
      if (operation !== 'add' && !existing) throw new NotFoundException();
      if (operation === 'delete')
        await tx.cartItem.delete({ where: { id: existing!.id } });
      else {
        const variant = await tx.productVariant.findFirst({
          where:
            operation === 'add'
              ? { sku: input.sku }
              : { id: existing!.variantId },
          include: { inventory: true, product: true },
        });
        if (!variant || !variant.active || !variant.product.active)
          throw new NotFoundException('SKU unavailable');
        const quantity =
          (operation === 'add' ? (existing?.quantity ?? 0) : 0) +
          input.quantity!;
        if (quantity > 99 || quantity > (variant.inventory?.quantity ?? 0))
          fail(409, 'STOCK_CHANGED', 'Requested quantity is unavailable');
        await tx.cartItem.upsert({
          where: {
            cartId_variantId: { cartId: cart.id, variantId: variant.id },
          },
          create: { cartId: cart.id, variantId: variant.id, quantity },
          update: { quantity },
        });
      }
      const updated = await tx.cart.update({
        where: { id: cart.id },
        data: { version: { increment: 1 } },
        include: cartInclude,
      });
      return cartJson(updated, await automaticOffers(tx));
    });
  }
}
