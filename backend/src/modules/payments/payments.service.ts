import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { isIP } from 'node:net';
import { PrismaService } from '../../database/prisma.service';
import { Prisma } from '../../generated/prisma/client';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import {
  VnpayProvider,
  VnpayEvent,
} from '../../integrations/payments/vnpay.provider';
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
@Injectable()
export class PaymentsService {
  constructor(
    private readonly db: PrismaService,
    private readonly gateway: VnpayProvider,
    private readonly config: ConfigService,
  ) {}
  methods() {
    return { cod: true, vnpay: this.gateway.enabled, sandbox: true };
  }
  private async owned(
    tx: Prisma.TransactionClient,
    userId: string,
    id: string,
  ) {
    await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid AND "userId"=${userId}::uuid FOR UPDATE`;
    const order = await tx.order.findFirst({ where: { id, userId }, include });
    if (!order) throw new NotFoundException();
    if (order.payment?.provider !== 'vnpay')
      fail(409, 'PAYMENT_METHOD_CONFLICT', 'This order does not use VNPay');
    return order;
  }
  private state(order: PaymentOrder) {
    const payment = order.payment!,
      attempt = payment.attempts[0];
    const payable =
      this.gateway.enabled &&
      order.status === 'PENDING' &&
      payment.status !== 'PAID' &&
      payment.status !== 'PARTIALLY_REFUNDED' &&
      payment.status !== 'REFUNDED' &&
      attempt?.status === 'PENDING' &&
      attempt.expiresAt.getTime() > Date.now();
    return {
      orderId: order.id,
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
      checkoutUrl: payable
        ? this.gateway.checkout({
            ...attempt,
            amount: attempt.amount.toString(),
          })
        : null,
    };
  }
  start(userId: string, id: string, remoteIp: string) {
    return transaction(this.db, async (tx) => {
      const order = await this.owned(tx, userId, id),
        payment = order.payment!;
      if (['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED'].includes(payment.status))
        return this.state(order);
      this.gateway.assertAvailable();
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
        return this.state(order);
      }
      const createdAt = new Date(),
        ip = remoteIp.replace(/^::ffff:/, '');
      const attempt = {
        reference: randomUUID().replaceAll('-', ''),
        amount: payment.amount.toString(),
        createdAt,
        expiresAt: new Date(createdAt.getTime() + 15 * 60000),
        ipAddress: isIP(ip) ? ip : '127.0.0.1',
      };
      this.gateway.checkout(attempt); // Validate before committing the attempt.
      await tx.paymentAttempt.create({
        data: { ...attempt, paymentId: payment.id },
      });
      await tx.payment.update({
        where: { id: payment.id },
        data: { status: 'PENDING' },
      });
      return this.state(
        await tx.order.findUniqueOrThrow({ where: { id }, include }),
      );
    });
  }
  async reconcile(userId: string, id: string) {
    const reserved = await transaction(this.db, async (tx) => {
      const order = await this.owned(tx, userId, id),
        payment = order.payment!;
      const pending = payment.attempts.find((a) => a.status === 'PENDING');
      if (
        !pending &&
        ['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED'].includes(payment.status)
      )
        return { state: this.state(order) };
      this.gateway.assertAvailable();
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
      return { attempt };
    });
    if ('state' in reserved) return reserved.state;
    const event = await this.gateway.query({
      ...reserved.attempt,
      amount: reserved.attempt.amount.toString(),
    });
    const result = await this.apply(event);
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
    let event: VnpayEvent;
    try {
      event = this.gateway.verifyIpn(query);
    } catch {
      return { RspCode: '97', Message: 'Invalid signature or fields' };
    }
    try {
      const result = await this.apply(event);
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
  returnUrl(query: Record<string, unknown>) {
    this.gateway.verifyIpn(query);
    return this.config.getOrThrow<string>('VNPAY_WEB_RETURN_URL');
  }
  private apply(event: VnpayEvent): Promise<'00' | '01' | '02' | '04' | '99'> {
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
        payment.provider !== 'vnpay' ||
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
        const alreadyPaid = ['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED'].includes(
          payment.status,
        );
        await tx.paymentAttempt.update({
          where: { id: attempt.id },
          data: {
            status: 'PAID',
            transactionNo: event.transactionNo,
            reviewRequired: alreadyPaid || payment.order.status === 'CANCELLED',
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
          !['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED', 'CANCELLED'].includes(
            payment.status,
          )
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
