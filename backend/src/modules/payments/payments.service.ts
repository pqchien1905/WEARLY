import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { isIP } from 'node:net';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { queueOrderMail } from '../mail/outbox';
import { VnpayProvider } from '../../integrations/payments/vnpay.provider';
import {
  OnlineProvider,
  PaymentEvent,
  WalletAttempt,
  assertAmount,
  isOnlineProvider,
  providerLabel,
} from '../../integrations/payments/wallet-gateway';
import { WalletGateways } from '../../integrations/payments/wallet-gateways';
import { orderInclude } from '../orders/order-includes';
import { recordAdminActivity } from '../admin/audit';
import { cancelOrder } from '../orders/cancel-order';
const include = {
  payment: {
    include: {
      attempts: {
        orderBy: [{ createdAt: 'desc' as const }, { id: 'desc' as const }],
      },
    },
  },
};
type PaymentOrder = Prisma.OrderGetPayload<{ include: typeof include }>;
export type ApplyResult = '00' | '01' | '02' | '04' | '99';
const settled = ['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED'];
@Injectable()
export class PaymentsService {
  constructor(
    private readonly db: PrismaService,
    private readonly gateway: VnpayProvider,
    private readonly wallets: WalletGateways,
    private readonly config: ConfigService,
  ) {}
  methods() {
    return {
      cod: true,
      vnpay: this.gateway.enabled,
      momo: this.wallets.enabled('momo'),
      zalopay: this.wallets.enabled('zalopay'),
      sandbox: true,
    };
  }
  private overdueWhere(): Prisma.OrderWhereInput {
    const minutes = Number(
      this.config.get('PAYMENT_RESERVATION_MINUTES') ?? 180,
    );
    return {
      status: 'PENDING',
      createdAt: { lt: new Date(Date.now() - minutes * 60000) },
      payment: {
        provider: { in: ['momo', 'zalopay', 'vnpay'] },
        status: { in: ['PENDING', 'FAILED'] },
      },
    };
  }
  overdue() {
    return this.db.order.findMany({
      where: this.overdueWhere(),
      orderBy: { createdAt: 'asc' },
      take: 100,
      select: {
        id: true,
        code: true,
        createdAt: true,
        payment: {
          select: {
            provider: true,
            status: true,
            attempts: {
              select: {
                id: true,
                provider: true,
                status: true,
                expiresAt: true,
                reviewRequired: true,
              },
            },
          },
        },
      },
    });
  }
  async expireUnpaid(orderId?: string) {
    const candidates = await this.db.order.findMany({
      where: { ...this.overdueWhere(), ...(orderId ? { id: orderId } : {}) },
      orderBy: { updatedAt: 'asc' },
      take: 25,
      include,
    });
    for (const candidate of candidates) {
      try {
        for (const attempt of candidate.payment!.attempts.filter(
          (a) => !['PAID', 'REFUNDED'].includes(a.status),
        )) {
          if (attempt.expiresAt.getTime() > Date.now()) continue;
          const result = await this.reconcile(
            undefined,
            candidate.id,
            undefined,
            attempt.id,
          );
          if (
            !result ||
            !('verificationStatus' in result) ||
            (result.verificationStatus !== 'FAILED' &&
              result.verificationStatus !== 'NOT_FOUND')
          )
            throw new Error('PAYMENT_STILL_UNCERTAIN');
        }
        await transaction(this.db, async (tx) => {
          await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${candidate.id}::uuid FOR UPDATE`;
          const order = await tx.order.findFirst({
            where: { ...this.overdueWhere(), id: candidate.id },
            include: { items: true, payment: { include: { attempts: true } } },
          });
          if (
            !order?.payment ||
            order.payment.attempts.some(
              (a) =>
                !['FAILED', 'CANCELLED'].includes(a.status) ||
                a.expiresAt.getTime() > Date.now() ||
                !a.provider,
            )
          )
            return;
          await cancelOrder(
            tx,
            order,
            null,
            'Hết thời gian giữ hàng; các giao dịch đã được xác minh không thu tiền.',
          );
        });
      } catch {
        // Unknown provider outcomes retain the reservation for staff review.
      } finally {
        await this.db.order.updateMany({
          where: { id: candidate.id, status: 'PENDING' },
          data: { updatedAt: new Date() },
        });
      }
    }
  }
  private enabled(provider: string) {
    return provider === 'vnpay'
      ? this.gateway.enabled
      : !!this.wallets.get(provider)?.enabled;
  }
  private assertAvailable(provider: string) {
    if (provider === 'vnpay') this.gateway.assertAvailable();
    else this.wallets.get(provider)!.assertAvailable();
  }
  private async owned(
    tx: Prisma.TransactionClient,
    userId: string | undefined,
    id: string,
    allowOffline = false,
  ) {
    if (userId)
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid AND "userId"=${userId}::uuid FOR UPDATE`;
    else
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid FOR UPDATE`;
    const order = await tx.order.findFirst({ where: { id, userId }, include });
    if (!order) throw new NotFoundException();
    if (!allowOffline && !isOnlineProvider(order.payment?.provider))
      fail(
        409,
        'PAYMENT_METHOD_CONFLICT',
        'This order does not use online payment',
      );
    return order;
  }
  private state(order: PaymentOrder) {
    const payment = order.payment!,
      provider = payment.provider as OnlineProvider,
      attempt = payment.attempts.find((a) => a.provider === provider);
    const payable =
      this.enabled(provider) &&
      order.status === 'PENDING' &&
      !settled.includes(payment.status) &&
      attempt?.status === 'PENDING' &&
      attempt.expiresAt.getTime() > Date.now();
    return {
      orderId: order.id,
      provider,
      paymentStatus: payment.status,
      sandbox: true,
      reviewRequired: payment.attempts.some((a) => a.reviewRequired),
      attempt: attempt
        ? {
            reference: attempt.reference,
            status: attempt.status,
            expiresAt: attempt.expiresAt,
            reviewRequired: attempt.reviewRequired,
          }
        : null,
      checkoutUrl: !payable
        ? null
        : provider === 'vnpay'
          ? this.gateway.checkout({
              ...attempt,
              amount: attempt.amount.toString(),
            })
          : attempt.checkoutUrl,
    };
  }
  async start(userId: string, id: string, remoteIp: string) {
    const prepared = await transaction(this.db, async (tx) => {
      const order = await this.owned(tx, userId, id),
        payment = order.payment!,
        provider = payment.provider;
      if (settled.includes(payment.status)) return { state: this.state(order) };
      this.assertAvailable(provider);
      if (order.status !== 'PENDING')
        fail(409, 'ORDER_STATE_CONFLICT', 'Order is not payable');
      const pending = payment.attempts.find((a) => a.status === 'PENDING');
      if (pending) {
        if (pending.expiresAt.getTime() <= Date.now())
          fail(
            409,
            'PAYMENT_RECONCILIATION_REQUIRED',
            'Verify the previous payment before retrying',
          );
        return { state: this.state(order) };
      }
      const createdAt = new Date(),
        ip = remoteIp.replace(/^::ffff:/, ''),
        wallet = this.wallets.get(provider);
      const attempt = {
        reference: wallet
          ? wallet.reference(createdAt)
          : randomUUID().replaceAll('-', ''),
        amount: payment.amount.toString(),
        createdAt,
        expiresAt: new Date(
          createdAt.getTime() + (wallet?.linkLifetimeMs ?? 15 * 60000),
        ),
        ipAddress: isIP(ip) ? ip : '127.0.0.1',
      };
      // Validate before committing the attempt.
      if (!wallet) this.gateway.checkout(attempt);
      else if (!assertAmount(wallet, attempt.amount))
        fail(
          400,
          'PAYMENT_AMOUNT_UNSUPPORTED',
          `${providerLabel(provider)} amount is outside the supported range`,
        );
      const row = await tx.paymentAttempt.create({
        data: { ...attempt, provider, paymentId: payment.id },
      });
      await tx.payment.update({
        where: { id: payment.id },
        data: { status: 'PENDING' },
      });
      if (!wallet)
        return {
          state: this.state(
            await tx.order.findUniqueOrThrow({ where: { id }, include }),
          ),
        };
      return { issue: { id: row.id, provider, attempt } };
    });
    if ('state' in prepared) return prepared.state;
    // The provider call stays outside the order lock and its transaction.
    const { issue } = prepared,
      wallet = this.wallets.get(issue.provider)!;
    let url: string;
    try {
      url = await wallet.create(issue.attempt);
    } catch (e) {
      // A timeout may happen after the gateway accepted the request. Query the
      // same reference before releasing it or issuing another payment link.
      throw e;
    }
    await this.db.paymentAttempt.updateMany({
      where: { id: issue.id, status: 'PENDING' },
      data: { checkoutUrl: url },
    });
    return transaction(this.db, async (tx) =>
      this.state(await this.owned(tx, userId, id)),
    );
  }
  /**
   * Switches an unpaid, unconfirmed order to another method. An open gateway
   * link is verified first and must have closed: a link that could still be
   * paid would otherwise collect money for a method the order no longer uses.
   */
  async changeMethod(
    userId: string,
    id: string,
    method: 'cod' | OnlineProvider,
  ) {
    const before = await this.db.order.findFirst({
      where: { id, userId },
      include,
    });
    if (!before) throw new NotFoundException();
    const current = before.payment;
    const open = current?.attempts.find((a) => a.status === 'PENDING');
    if (open && !isOnlineProvider(open.provider))
      fail(
        409,
        'PAYMENT_SOURCE_UNKNOWN',
        'Legacy payment source requires review',
      );
    if (current && open && isOnlineProvider(open.provider)) {
      const attempt = { ...open, amount: open.amount.toString() };
      const wallet = this.wallets.get(open.provider);
      let event: PaymentEvent;
      try {
        event = wallet
          ? await wallet.query(attempt satisfies WalletAttempt)
          : await this.gateway.query(attempt);
      } catch {
        fail(
          503,
          'PAYMENT_VERIFICATION_UNAVAILABLE',
          'Could not verify the open payment; try again shortly',
        );
      }
      const result = await this.apply(event, open.provider!);
      if (result !== '00' && result !== '02')
        fail(
          409,
          'PAYMENT_RESULT_CONFLICT',
          'Payment result requires operator review',
        );
    }
    return transaction(this.db, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid AND "userId"=${userId}::uuid FOR UPDATE`;
      const order = await tx.order.findFirst({
        where: { id, userId },
        include,
      });
      if (!order?.payment) throw new NotFoundException();
      const payment = order.payment;
      if (order.status !== 'PENDING')
        fail(
          409,
          'ORDER_STATE_CONFLICT',
          'The payment method can only change before the order is confirmed',
        );
      if (payment.provider === 'free' || payment.amount.eq(0))
        fail(409, 'PAYMENT_METHOD_CONFLICT', 'This order needs no payment');
      if (settled.includes(payment.status))
        fail(409, 'PAYMENT_ALREADY_SETTLED', 'This order is already paid');
      if (payment.provider !== method) {
        if (method !== 'cod') {
          this.assertAvailable(method);
          const wallet = this.wallets.get(method);
          if (wallet && !assertAmount(wallet, payment.amount.toFixed(0)))
            fail(
              400,
              'PAYMENT_AMOUNT_UNSUPPORTED',
              `${providerLabel(method)} chỉ nhận đơn từ ${wallet.minAmount.toLocaleString('vi-VN')} đến ${wallet.maxAmount.toLocaleString('vi-VN')} VND`,
            );
          if (method === 'vnpay' && payment.amount.gt('9999999999'))
            fail(
              400,
              'PAYMENT_AMOUNT_UNSUPPORTED',
              'VNPay amount is outside the supported range',
            );
        }
        const pending = payment.attempts.find((a) => a.status === 'PENDING');
        if (pending) {
          fail(
            409,
            'PAYMENT_IN_PROGRESS',
            `Giao dịch ${providerLabel(payment.provider)} đang mở đến ${pending.expiresAt.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Ho_Chi_Minh' })}. Hoàn tất hoặc chờ hết hạn rồi đổi phương thức.`,
          );
        }
        const version = order.version + 1;
        await tx.payment.update({
          where: { id: payment.id },
          data: { provider: method, status: 'PENDING' },
        });
        await tx.order.update({ where: { id }, data: { version } });
        await tx.orderEvent.create({
          data: {
            orderId: id,
            status: order.status,
            version,
            actorId: userId,
            note: `Khách đổi phương thức thanh toán: ${providerLabel(payment.provider)} → ${providerLabel(method)}`,
          },
        });
      }
      return tx.order.findUniqueOrThrow({
        where: { id },
        include: orderInclude,
      });
    });
  }
  async reconcile(
    userId: string | undefined,
    id: string,
    actorId?: string,
    attemptId?: string,
  ) {
    const reserved = await transaction(this.db, async (tx) => {
      const order = await this.owned(tx, userId, id, true),
        payment = order.payment!;
      if (!payment) throw new NotFoundException();
      const pending = payment.attempts.find((a) => a.status === 'PENDING');
      if (!attemptId && !pending && settled.includes(payment.status))
        return { state: this.state(order) };
      const attempt = attemptId
        ? payment.attempts.find((a) => a.id === attemptId)
        : (pending ?? payment.attempts[0]);
      if (!attempt) fail(409, 'PAYMENT_NOT_STARTED', 'Start a payment first');
      if (!isOnlineProvider(attempt.provider))
        fail(
          409,
          'PAYMENT_SOURCE_UNKNOWN',
          'Legacy payment source requires review',
        );
      if (
        attempt.lastQueryAt &&
        Date.now() - attempt.lastQueryAt.getTime() < 10000
      )
        fail(
          429,
          'PAYMENT_QUERY_RATE_LIMITED',
          'Wait ten seconds before verifying again',
        );
      await tx.paymentAttempt.update({
        where: { id: attempt.id },
        data: { lastQueryAt: new Date() },
      });
      if (actorId)
        await recordAdminActivity(tx, actorId, 'PAYMENT_RECONCILED', id, {
          before: this.state(order),
          after: { provider: attempt.provider },
        });
      return { attempt, provider: attempt.provider! };
    });
    if ('state' in reserved) return reserved.state;
    const attempt = {
      ...reserved.attempt,
      amount: reserved.attempt.amount.toString(),
    };
    const wallet = this.wallets.get(reserved.provider);
    const event = wallet
      ? await wallet.query(attempt satisfies WalletAttempt)
      : await this.gateway.query(attempt);
    const result = await this.apply(event, reserved.provider);
    if (result !== '00' && result !== '02')
      fail(
        409,
        'PAYMENT_RESULT_CONFLICT',
        'Payment result requires operator review',
      );
    return transaction(this.db, async (tx) => ({
      ...this.state(await this.owned(tx, userId, id, true)),
      verificationStatus: event.status,
    }));
  }
  async ipn(query: Record<string, unknown>) {
    let event: PaymentEvent;
    try {
      event = this.gateway.verifyIpn(query);
    } catch {
      return { RspCode: '97', Message: 'Invalid signature or fields' };
    }
    try {
      const result = await this.apply(event, 'vnpay');
      return {
        RspCode: result,
        Message: (
          {
            '00': 'Confirmed',
            '01': 'Order not found',
            '02': 'Already confirmed',
            '04': 'Invalid amount',
            '99': 'Unable to confirm',
          } as const
        )[result],
      };
    } catch {
      return { RspCode: '99', Message: 'Unable to confirm' };
    }
  }
  /**
   * Verified wallet notification. Returns null for an invalid signature or
   * field set; otherwise the ledger outcome, which the controller maps to the
   * provider's acknowledgement format.
   */
  async walletNotification(
    provider: 'momo' | 'zalopay',
    body: unknown,
  ): Promise<ApplyResult | null> {
    const wallet = this.wallets.get(provider)!;
    let event: PaymentEvent;
    try {
      event = wallet.verifyNotification(body);
    } catch {
      return null;
    }
    try {
      return await this.apply(event, provider);
    } catch {
      return '99';
    }
  }
  async returnUrl(query: Record<string, unknown>) {
    this.gateway.verifyIpn(query);
    return this.withOrder(
      this.config.getOrThrow<string>('VNPAY_WEB_RETURN_URL'),
      query.vnp_TxnRef,
    );
  }
  /**
   * Browser returns are never proof of payment: the redirect only names the
   * order so the storefront can ask the provider (reconcile) right away.
   * ZaloPay sends `apptransid`, MoMo sends `orderId`; both are our reference.
   */
  async walletReturnUrl(query: Record<string, unknown> = {}) {
    const url = this.config.get<string>('PAYMENT_WEB_RETURN_URL');
    if (!url) throw new NotFoundException();
    // A gateway that reports cancel/failure lets the page offer a retry at
    // once. Only a hint for wording: success is never taken from the query.
    const declined =
      (query.status !== undefined && String(query.status) !== '1') ||
      (query.resultCode !== undefined && String(query.resultCode) !== '0');
    return this.withOrder(url, query.apptransid ?? query.orderId, declined);
  }
  private async withOrder(url: string, reference: unknown, declined = false) {
    if (
      typeof reference !== 'string' ||
      !/^[A-Za-z0-9_]{6,32}$/.test(reference)
    )
      return url;
    const attempt = await this.db.paymentAttempt.findUnique({
      where: { reference },
      select: { payment: { select: { orderId: true } } },
    });
    if (!attempt) return url;
    const separator = url.includes('?') ? '&' : '?';
    const order = `order=${encodeURIComponent(attempt.payment.orderId)}`;
    return `${url}${separator}${order}${declined ? '&declined=1' : ''}`;
  }
  private apply(event: PaymentEvent, provider: string): Promise<ApplyResult> {
    return transaction(this.db, async (tx) => {
      const initial = await tx.paymentAttempt.findUnique({
        where: { reference: event.reference },
        include: { payment: true },
      });
      if (!initial) return '01';
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${initial.payment.orderId}::uuid FOR UPDATE`;
      const attempt = await tx.paymentAttempt.findUniqueOrThrow({
        where: { id: initial.id },
      });
      const payment = await tx.payment.findUniqueOrThrow({
        where: { id: attempt.paymentId },
        include: { order: true },
      });
      if (
        attempt.provider !== provider ||
        !attempt.amount.eq(event.amount) ||
        !payment.amount.eq(event.amount)
      )
        return '04';
      if (attempt.status === 'PAID' || attempt.status === 'REFUNDED') {
        if (
          event.status === 'PAID' &&
          event.transactionNo !== attempt.transactionNo
        )
          return '99';
        return '02';
      }
      if (event.status === 'PAID') {
        if (!event.transactionNo) return '99';
        const duplicate = await tx.paymentAttempt.findUnique({
          where: { transactionNo: event.transactionNo },
        });
        if (duplicate && duplicate.id !== attempt.id) return '99';
        const alreadyPaid = settled.includes(payment.status);
        const switched = payment.provider !== provider;
        const review =
          switched || alreadyPaid || payment.order.status === 'CANCELLED';
        await tx.paymentAttempt.update({
          where: { id: attempt.id },
          data: {
            status: 'PAID',
            transactionNo: event.transactionNo,
            reviewRequired: review,
          },
        });
        if (!alreadyPaid && !switched)
          await tx.payment.update({
            where: { id: payment.id },
            data: {
              status: 'PAID',
              providerTransactionId: event.transactionNo,
            },
          });
        await tx.order.update({
          where: { id: payment.orderId },
          data: { version: { increment: 1 } },
        });
        const label = providerLabel(provider);
        await queueOrderMail(
          tx,
          payment.orderId,
          `${provider}-paid:${attempt.id}`,
          `Đã ghi nhận thanh toán ${label}`,
          `${label} sandbox xác nhận thu ${attempt.amount.toFixed(0)} VND. Giao dịch: ${event.transactionNo}.${review ? ' Khoản thu cần được quản trị viên đối soát; trạng thái giao hàng không thay đổi.' : ''}`,
        );
      } else if (
        event.status === 'FAILED' ||
        (event.status === 'NOT_FOUND' &&
          attempt.expiresAt.getTime() <= Date.now())
      ) {
        const status = event.status === 'FAILED' ? 'FAILED' : 'CANCELLED';
        if (attempt.status === status) return '02';
        await tx.paymentAttempt.update({
          where: { id: attempt.id },
          data: { status },
        });
        // An older attempt must not overwrite the state of a newer payment attempt.
        const latest = await tx.paymentAttempt.findFirst({
          where: { paymentId: payment.id },
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        });
        if (
          latest?.id === attempt.id &&
          payment.provider === provider &&
          ![...settled, 'CANCELLED'].includes(payment.status)
        )
          await tx.payment.update({
            where: { id: payment.id },
            data: { status: 'FAILED' },
          });
      }
      return '00';
    });
  }
}
