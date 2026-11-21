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
// A wallet attempt without a link this old was never issued (crash or failure).
const UNISSUED_AFTER_MS = 60000;
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
    userId: string,
    id: string,
  ) {
    await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid AND "userId"=${userId}::uuid FOR UPDATE`;
    const order = await tx.order.findFirst({ where: { id, userId }, include });
    if (!order) throw new NotFoundException();
    if (!isOnlineProvider(order.payment?.provider))
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
      attempt = payment.attempts[0];
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
      if (settled.includes(payment.status))
        return { state: this.state(order) };
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
        const unissued =
          provider !== 'vnpay' &&
          !pending.checkoutUrl &&
          Date.now() - pending.createdAt.getTime() > UNISSUED_AFTER_MS;
        // Nobody holds a link for an unissued attempt, so it can never be paid.
        if (!unissued) return { state: this.state(order) };
        await tx.paymentAttempt.update({
          where: { id: pending.id },
          data: { status: 'CANCELLED' },
        });
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
        data: { ...attempt, paymentId: payment.id },
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
      await this.db.paymentAttempt.updateMany({
        where: { id: issue.id, status: 'PENDING', checkoutUrl: null },
        data: { status: 'CANCELLED' },
      });
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
  async reconcile(userId: string, id: string) {
    const reserved = await transaction(this.db, async (tx) => {
      const order = await this.owned(tx, userId, id),
        payment = order.payment!;
      const pending = payment.attempts.find((a) => a.status === 'PENDING');
      if (!pending && settled.includes(payment.status))
        return { state: this.state(order) };
      this.assertAvailable(payment.provider);
      const attempt = pending ?? payment.attempts[0];
      if (!attempt) fail(409, 'PAYMENT_NOT_STARTED', 'Start a payment first');
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
      return { attempt, provider: payment.provider };
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
    return transaction(this.db, async (tx) =>
      this.state(await this.owned(tx, userId, id)),
    );
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
  returnUrl(query: Record<string, unknown>) {
    this.gateway.verifyIpn(query);
    return this.config.getOrThrow<string>('VNPAY_WEB_RETURN_URL');
  }
  /** Browser returns are never proof of payment; the storefront verifies. */
  walletReturnUrl() {
    const url = this.config.get<string>('PAYMENT_WEB_RETURN_URL');
    if (!url) throw new NotFoundException();
    return url;
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
        payment.provider !== provider ||
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
        const review = alreadyPaid || payment.order.status === 'CANCELLED';
        await tx.paymentAttempt.update({
          where: { id: attempt.id },
          data: {
            status: 'PAID',
            transactionNo: event.transactionNo,
            reviewRequired: review,
          },
        });
        if (!alreadyPaid)
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
