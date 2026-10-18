import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { lockUser, transaction } from '../../common/transaction';
import { catalogInclude, productJson } from '../products/products.service';
const LIMIT = 200;
@Injectable()
export class WishlistService {
  constructor(private readonly db: PrismaService) {}
  private async snapshot(tx: Prisma.TransactionClient, userId: string) {
    const rows = await tx.wishlistItem.findMany({ where: { userId }, orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      include: { product: { include: catalogInclude } } });
    return { items: rows.map(row => ({ productId: row.productId,
      product: row.product.active && row.product.variants.length ? productJson(row.product) : null })), limit: LIMIT };
  }
  get(userId: string) { return this.snapshot(this.db, userId); }
  set(userId: string, productId: string, saved: boolean) {
    return transaction(this.db, async tx => {
      await lockUser(tx, userId);
      if (saved) {
        const existing = await tx.wishlistItem.findUnique({ where: { userId_productId: { userId, productId } } });
        if (!existing) {
          const product = await tx.product.findFirst({ where: { id: productId, active: true, variants: { some: { active: true } } }, select: { id: true } });
          if (!product) throw new NotFoundException('Product is not available');
          if (await tx.wishlistItem.count({ where: { userId } }) >= LIMIT) throw new ConflictException({ code: 'WISHLIST_LIMIT', message: 'Wishlist limit reached' });
          await tx.wishlistItem.create({ data: { userId, productId } });
        }
      } else {
        await tx.wishlistItem.deleteMany({ where: { userId, productId } });
      }
      return this.snapshot(tx, userId);
    });
  }
}
