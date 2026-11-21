import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import { PrismaService } from '../../database/prisma.service';
import { transaction, lockUser } from '../../common/transaction';
import { shippingFee, totalForItems } from '../../common/money';
import { fail } from '../../common/errors';
import { cartInclude } from '../cart/cart.service';
import { CreateOrderDto } from './dto/order.dto';
import { PageDto } from '../products/dto/query-products.dto';
import { VnpayProvider } from '../../integrations/payments/vnpay.provider';
import { WalletGateways } from '../../integrations/payments/wallet-gateways';
import {
  assertAmount,
  providerLabel,
} from '../../integrations/payments/wallet-gateway';
import { PromotionsService } from '../promotions/promotions.service';
import { orderInclude as include } from './order-includes';
import { cancelOrder } from './cancel-order';
import { queueOrderStatus } from '../mail/outbox';
import {
  automaticOffers,
  automaticPrice,
} from '../promotions/automatic-pricing';
@Injectable()
export class OrdersService {
  constructor(
    private readonly db: PrismaService,
    private readonly gateway: VnpayProvider,
    private readonly wallets: WalletGateways,
    private readonly promotions: PromotionsService,
  ) {}
  create(userId: string, key: string | undefined, dto: CreateOrderDto) {
    if (!key || !/^[a-zA-Z0-9_-]{8,128}$/.test(key))
      throw new BadRequestException(
        'Idempotency-Key (8–128 letters, numbers, underscores or hyphens) is required',
      );
    const requestHash = createHash('sha256')
      .update(
        JSON.stringify({
          addressId: dto.addressId,
          shippingMethod: dto.shippingMethod,
          expectedSubtotal: dto.expectedSubtotal,
          cartVersion: dto.cartVersion ?? null,
          // COD keeps its original hash so earlier idempotency keys still match.
          ...(dto.paymentMethod !== 'cod'
            ? { paymentMethod: dto.paymentMethod }
            : {}),
          ...(dto.couponCode
            ? {
                couponCode: dto.couponCode,
                expectedDiscount: dto.expectedDiscount,
              }
            : {}),
        }),
      )
      .digest('hex');
    return transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      const previous = await tx.order.findUnique({
        where: { userId_idempotencyKey: { userId, idempotencyKey: key } },
        include,
      });
      if (previous) {
        if (previous.requestHash !== requestHash)
          fail(
            409,
            'IDEMPOTENCY_CONFLICT',
            'This key belongs to a different request',
          );
        return previous;
      }
      const address = await tx.address.findFirst({
        where: { id: dto.addressId, userId },
      });
      if (!address) throw new NotFoundException('Address not found');
      const cart = await tx.cart.findUnique({
        where: { userId },
        include: cartInclude,
      });
      if (!cart?.items.length) throw new BadRequestException('Cart is empty');
      if (dto.cartVersion !== undefined && dto.cartVersion !== cart.version)
        fail(409, 'VERSION_CONFLICT', 'Cart changed; refresh before ordering');
      const offers = await automaticOffers(tx);
      const prices = new Map(
        cart.items.map((i) => [
          i.variantId,
          automaticPrice(i.variant.productId, i.variant.price, offers),
        ]),
      );
      const pricedItems = cart.items.map((i) => ({
        productId: i.variant.productId,
        price: prices.get(i.variantId)!.price,
        quantity: i.quantity,
      }));
      const subtotal = totalForItems(pricedItems);
      if (!subtotal.eq(dto.expectedSubtotal))
        fail(409, 'PRICE_CHANGED', 'Prices changed; refresh your cart');
      const shipping = shippingFee(subtotal, dto.shippingMethod);
      const promotion = dto.couponCode
        ? await this.promotions.discount(
            tx,
            userId,
            dto.couponCode,
            subtotal,
            pricedItems,
          )
        : null;
      const discount = promotion?.discount ?? subtotal.minus(subtotal),
        total = subtotal.plus(shipping).minus(discount);
      const wallet = this.wallets.get(dto.paymentMethod);
      if (dto.paymentMethod === 'vnpay' && total.gt(0))
        this.gateway.assertAvailable();
      if (wallet && total.gt(0)) {
        wallet.assertAvailable();
        if (!assertAmount(wallet, total.toFixed(0)))
          fail(
            400,
            'PAYMENT_AMOUNT_UNSUPPORTED',
            `${providerLabel(wallet.name)} chỉ nhận đơn từ ${wallet.minAmount.toLocaleString('vi-VN')} đến ${wallet.maxAmount.toLocaleString('vi-VN')} VND`,
          );
      }
      if (
        dto.expectedDiscount !== undefined &&
        !discount.eq(dto.expectedDiscount)
      )
        fail(
          409,
          'PROMOTION_CHANGED',
          'Discount changed; apply the code again',
        );
      if (dto.paymentMethod === 'vnpay' && total.gt('9999999999'))
        fail(
          400,
          'PAYMENT_AMOUNT_UNSUPPORTED',
          'VNPay amount is outside the supported range',
        );
      if (total.gt('99999999999999')) {
        fail(
          400,
          'ORDER_TOTAL_TOO_LARGE',
          'Order total exceeds the supported amount',
        );
      }
      // Deterministic order reduces deadlocks across carts with multiple SKUs.
      for (const item of [...cart.items].sort((a, b) =>
        a.variantId.localeCompare(b.variantId),
      )) {
        if (!item.variant.active || !item.variant.product.active)
          fail(409, 'STOCK_CHANGED', 'SKU is no longer available');
        const result = await tx.inventory.updateMany({
          where: {
            variantId: item.variantId,
            quantity: { gte: item.quantity },
          },
          data: {
            quantity: { decrement: item.quantity },
            version: { increment: 1 },
          },
        });
        if (result.count !== 1)
          fail(409, 'STOCK_CHANGED', 'Insufficient stock');
      }
      const order = await tx.order.create({
        data: {
          userId,
          idempotencyKey: key,
          requestHash,
          addressSnapshot: {
            recipient: address.recipient,
            phone: address.phone,
            address: address.address,
          },
          subtotal,
          discount,
          couponCode: promotion?.code,
          shipping,
          shippingMethod: dto.shippingMethod,
          total,
          history: {
            create: { status: 'PENDING', version: 0, actorId: userId },
          },
          items: {
            create: cart.items.map((i) => ({
              variantId: i.variantId,
              name: i.variant.product.name,
              sku: i.variant.sku,
              slug: i.variant.product.slug,
              size: i.variant.size,
              color: i.variant.color,
              image: i.variant.product.images[0]?.url ?? '',
              unitPrice: prices.get(i.variantId)!.price,
              originalUnitPrice: i.variant.price,
              promotionName: prices.get(i.variantId)!.promotion?.name,
              automaticPromotionId: prices.get(i.variantId)!.promotion?.id,
              quantity: i.quantity,
            })),
          },
          payment: {
            create: {
              provider: total.eq(0) ? 'free' : dto.paymentMethod,
              status: total.eq(0) ? 'PAID' : 'PENDING',
              amount: total,
            },
          },
        },
        include,
      });
      if (promotion)
        await tx.couponRedemption.create({
          data: {
            couponId: promotion.couponId,
            orderId: order.id,
            userId,
            discount,
          },
        });
      for (const item of cart.items)
        await tx.inventoryMovement.create({
          data: {
            inventoryId: item.variant.inventory!.id,
            delta: -item.quantity,
            reason: 'ORDER',
            orderId: order.id,
          },
        });
      await tx.cartItem.deleteMany({ where: { cartId: cart.id } });
      await tx.cart.update({
        where: { id: cart.id },
        data: { version: { increment: 1 } },
      });
      await queueOrderStatus(tx, order.id, 'PENDING', 0);
      return order;
    });
  }
  async list(userId: string, q: PageDto) {
    const [items, total] = await this.db.$transaction([
      this.db.order.findMany({
        where: { userId },
        include,
        orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
        skip: (q.page - 1) * q.limit,
        take: q.limit,
      }),
      this.db.order.count({ where: { userId } }),
    ]);
    return { items, total, page: q.page, limit: q.limit };
  }
  async get(userId: string, id: string) {
    const order = await this.db.order.findFirst({
      where: { id, userId },
      include,
    });
    if (!order) throw new NotFoundException();
    return order;
  }
  cancel(userId: string, id: string) {
    return transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id = ${id}::uuid AND "userId" = ${userId}::uuid FOR UPDATE`;
      const order = await tx.order.findFirst({
        where: { id, userId },
        include,
      });
      if (!order) throw new NotFoundException();
      if (order.status === 'CANCELLED') return order;
      if (order.status !== 'PENDING')
        fail(
          409,
          'ORDER_STATE_CONFLICT',
          'Only pending orders can be cancelled',
        );
      await cancelOrder(tx, order, userId, 'Khách hủy đơn trước xác nhận');
      return tx.order.findUniqueOrThrow({ where: { id }, include });
    });
  }
}
