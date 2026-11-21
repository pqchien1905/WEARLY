import { Injectable, NotFoundException } from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { recordAdminActivity } from '../admin/audit';
import { queueOrderMail } from '../mail/outbox';
import {
  VnpayProvider,
  VnpayRefund,
} from '../../integrations/payments/vnpay.provider';
import {
  RefundEvent,
  isOnlineProvider,
  providerLabel,
} from '../../integrations/payments/wallet-gateway';
import { WalletGateways } from '../../integrations/payments/wallet-gateways';
import { CreateRefundDto, QueryRefundDto } from './refunds.dto';
import {
  RefundOrder,
  RefundRow,
  refundOrderInclude,
  publicRefund,
  refundState,
  sources,
} from './refunds-state';

@Injectable()
export class RefundsService {
  constructor(
    private readonly db: PrismaService,
    private readonly gateway: VnpayProvider,
    private readonly wallets: WalletGateways,
  ) {}
  private assertAvailable(provider: string) {
    const wallet = this.wallets.get(provider);
    if (wallet) wallet.assertConfigured();
    else this.gateway.assertConfigured();
  }
  private send(provider: string, request: VnpayRefund) {
    const wallet = this.wallets.get(provider);
    return wallet ? wallet.refund(request) : this.gateway.refund(request);
  }
  private async publicRow(refundId: string) {
    const row = await this.db.refund.findUniqueOrThrow({
      where: { id: refundId },
      include: {
        payment: { select: { provider: true } },
        attempt: { select: { provider: true } },
      },
    });
    return publicRefund(row, row.attempt?.provider ?? row.payment.provider);
  }
  private async order(
    tx: Prisma.TransactionClient,
    id: string,
    userId?: string,
  ) {
    if (userId)
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid AND "userId"=${userId}::uuid FOR UPDATE`;
    else
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid FOR UPDATE`;
    const row = await tx.order.findFirst({
      where: { id, ...(userId ? { userId } : {}) },
      include: refundOrderInclude,
    });
    if (!row) throw new NotFoundException();
    return row;
  }
  state(id: string, userId?: string) {
    return transaction(this.db, async (tx) =>
      refundState(await this.order(tx, id, userId), !userId),
    );
  }
  private request(order: RefundOrder, row: RefundRow): VnpayRefund {
    const attempt = order.payment?.attempts.find((a) => a.id === row.attemptId);
    if (!attempt?.transactionNo)
      fail(409, 'REFUND_SOURCE_UNVERIFIED', 'Verified payment source required');
    return {
      requestId: row.providerRequestId,
      reference: attempt.reference,
      amount: row.amount.toFixed(0),
      originalAmount: attempt.amount.toFixed(0),
      originalTransactionNo: attempt.transactionNo,
      transactionDate: attempt.createdAt,
      createdAt: row.createdAt,
      actorId: row.actorId,
    };
  }
  private async refreshPayment(
    tx: Prisma.TransactionClient,
    paymentId: string,
  ) {
    const payment = await tx.payment.findUniqueOrThrow({
      where: { id: paymentId },
    });
    const total = await tx.refund.aggregate({
      where: { paymentId, primary: true, status: 'SUCCEEDED' },
      _sum: { amount: true },
    });
    const amount = total._sum.amount ?? new Prisma.Decimal(0);
    if (amount.gt(payment.amount)) throw Error('Refund ledger exceeds payment');
    if (amount.gt(0))
      await tx.payment.update({
        where: { id: paymentId },
        data: {
          status: amount.eq(payment.amount) ? 'REFUNDED' : 'PARTIALLY_REFUNDED',
        },
      });
  }
  async create(actorId: string, id: string, dto: CreateRefundDto) {
    const hash = createHash('sha256')
      .update(
        JSON.stringify([
          dto.expectedVersion,
          dto.expectedAmount,
          dto.paymentAttemptId ?? null,
          dto.reference ?? null,
        ]),
      )
      .digest('hex');
    let reserved: { row: RefundRow; provider?: string; request?: VnpayRefund };
    try {
      reserved = await transaction(this.db, async (tx) => {
        const order = await this.order(tx, id),
          p = order.payment;
        if (!p) fail(409, 'REFUND_SOURCE_UNVERIFIED', 'No payment source');
        const existing = p.refunds.find((r) => r.requestKey === dto.requestKey);
        if (existing) {
          if (existing.payloadHash !== hash)
            fail(
              409,
              'IDEMPOTENCY_CONFLICT',
              'Original refund request differs',
            );
          return { row: existing };
        }
        if (order.version !== dto.expectedVersion)
          fail(409, 'VERSION_CONFLICT', 'Reload the current order');
        if (
          p.refunds.some(
            (r) =>
              r.attemptId === (dto.paymentAttemptId ?? null) &&
              ['REVIEW', 'PROCESSING'].includes(r.status),
          )
        )
          fail(
            409,
            'REFUND_PENDING_CONFLICT',
            'Verify the existing refund for this source before creating another',
          );
        const source = sources(order).find(
          (s) => s.attemptId === (dto.paymentAttemptId ?? null),
        );
        if (
          !source ||
          source.available === '0' ||
          source.available !== dto.expectedAmount
        )
          fail(
            409,
            'REFUND_AMOUNT_CHANGED',
            'Reload the available refund entitlement',
          );
        if (source.provider === 'cod') {
          if (!dto.reference || dto.paymentAttemptId)
            fail(
              400,
              'REFUND_RECEIPT_REQUIRED',
              'Confirm the COD refund receipt reference',
            );
          if (
            await tx.refund.findUnique({ where: { reference: dto.reference } })
          )
            fail(
              409,
              'REFUND_REFERENCE_USED',
              'Refund receipt reference already exists',
            );
        } else if (isOnlineProvider(source.provider)) {
          if (!dto.paymentAttemptId || dto.reference)
            fail(
              400,
              'REFUND_SOURCE_INVALID',
              `Select a verified ${providerLabel(source.provider)} payment`,
            );
          this.assertAvailable(source.provider);
        } else
          fail(
            409,
            'REFUND_SOURCE_INVALID',
            'This payment has no refund source',
          );
        const row = await tx.refund.create({
          data: {
            paymentId: p.id,
            attemptId: source.attemptId,
            primary: source.primary,
            requestKey: dto.requestKey,
            payloadHash: hash,
            providerRequestId:
              this.wallets.get(source.provider)?.refundRequestId(new Date()) ??
              randomUUID().replaceAll('-', ''),
            amount: source.available,
            actorId,
            reference: dto.reference ?? null,
            status: source.provider === 'cod' ? 'SUCCEEDED' : 'REVIEW',
            completedAt: source.provider === 'cod' ? new Date() : null,
          },
        });
        await this.refreshPayment(tx, p.id);
        await tx.order.update({
          where: { id },
          data: { version: { increment: 1 } },
        });
        await recordAdminActivity(tx, actorId, 'REFUND_CREATED', row.id, {
          after: { ...row, provider: source.provider },
        });
        if (row.status === 'SUCCEEDED')
          await queueOrderMail(
            tx,
            id,
            'refund:' + row.id,
            'Đã ghi nhận hoàn tiền',
            `Đã xác nhận hoàn ${row.amount.toFixed(0)} VND. Mã hoàn tiền: ${row.id}.`,
          );
        return {
          row,
          provider: source.provider,
          ...(isOnlineProvider(source.provider)
            ? { request: this.request(order, row) }
            : {}),
        };
      });
    } catch (e) {
      if (
        e instanceof Prisma.PrismaClientKnownRequestError &&
        e.code === 'P2002'
      )
        fail(
          409,
          'REFUND_REFERENCE_USED',
          'Refund identity or receipt already exists',
        );
      throw e;
    }
    // Only the transaction that inserted the durable reservation may send money.
    // Replays and crash recovery return/query the reservation, never send again.
    if (reserved.request && reserved.provider) {
      try {
        const event = await this.send(reserved.provider, reserved.request);
        await this.apply(actorId, id, reserved.row.id, event);
      } catch {
        /* Keep REVIEW and reserved funds; query the provider before retrying. */
      }
    }
    return this.publicRow(reserved.row.id);
  }
  async query(
    actorId: string,
    id: string,
    refundId: string,
    dto: QueryRefundDto,
  ) {
    const reserved = await transaction(this.db, async (tx) => {
      const order = await this.order(tx, id),
        row = order.payment?.refunds.find((r) => r.id === refundId);
      if (!row) throw new NotFoundException();
      if (['SUCCEEDED', 'FAILED'].includes(row.status)) return { row };
      const provider =
        order.payment!.attempts.find((a) => a.id === row.attemptId)?.provider ??
        'cod';
      if (!row.attemptId || !isOnlineProvider(provider))
        fail(
          409,
          'REFUND_QUERY_UNAVAILABLE',
          'Only online payment refunds use provider queries',
        );
      this.assertAvailable(provider);
      const rateLimit = async () => {
        if (row.lastQueryAt && Date.now() - row.lastQueryAt.getTime() < 10000)
          fail(
            429,
            'REFUND_QUERY_RATE_LIMITED',
            'Wait ten seconds before querying again',
          );
        await tx.refund.update({
          where: { id: row.id },
          data: { lastQueryAt: new Date() },
        });
      };
      // Wallets look the refund up by its request identifier; no manual number.
      if (provider !== 'vnpay') {
        await rateLimit();
        return { row, provider, request: this.request(order, row) };
      }
      const number = row.providerTransactionNo ?? dto.transactionNo;
      if (!number)
        fail(
          409,
          'REFUND_TRANSACTION_REQUIRED',
          'Enter the refund transaction number from VNPay sandbox',
        );
      if (
        row.providerTransactionNo &&
        dto.transactionNo &&
        dto.transactionNo !== row.providerTransactionNo
      )
        fail(
          409,
          'REFUND_TRANSACTION_CONFLICT',
          'Use the recorded refund transaction number',
        );
      const request = this.request(order, row);
      if (number === request.originalTransactionNo)
        fail(
          409,
          'REFUND_TRANSACTION_CONFLICT',
          'Use a refund number, not the payment number',
        );
      const reused = await tx.refund.findUnique({
        where: { providerTransactionNo: number },
      });
      if (reused && reused.id !== row.id)
        fail(
          409,
          'REFUND_TRANSACTION_CONFLICT',
          'Refund number already assigned',
        );
      await rateLimit();
      return { row, provider, request, number };
    });
    if ('request' in reserved && reserved.request) {
      const wallet = this.wallets.get(reserved.provider);
      try {
        const event = wallet
          ? await wallet.queryRefund(reserved.request)
          : 'number' in reserved && reserved.number
            ? await this.gateway.queryRefund(reserved.request, reserved.number)
            : null;
        if (event) await this.apply(actorId, id, refundId, event);
      } catch {
        /* The current unresolved state retains the full reservation. */
      }
    }
    return this.publicRow(refundId);
  }
  private apply(
    actorId: string,
    id: string,
    refundId: string,
    event: RefundEvent,
  ) {
    return transaction(this.db, async (tx) => {
      const order = await this.order(tx, id),
        row = order.payment?.refunds.find((r) => r.id === refundId);
      if (!row) throw new NotFoundException();
      if (['SUCCEEDED', 'FAILED'].includes(row.status)) return;
      // Success must carry the provider's refund number; a rejection may not.
      if (event.status === 'SUCCEEDED' && !event.transactionNo) return;
      const number = event.transactionNo ?? row.providerTransactionNo;
      if (
        row.providerTransactionNo &&
        event.transactionNo &&
        row.providerTransactionNo !== event.transactionNo
      )
        return;
      if (number) {
        const reused = await tx.refund.findUnique({
          where: { providerTransactionNo: number },
        });
        if (reused && reused.id !== row.id) return;
      }
      if (row.status === event.status && row.providerTransactionNo === number)
        return;
      await tx.refund.update({
        where: { id: row.id },
        data: {
          status: event.status,
          providerTransactionNo: number,
          completedAt: ['SUCCEEDED', 'FAILED'].includes(event.status)
            ? new Date()
            : null,
        },
      });
      await this.refreshPayment(tx, row.paymentId);
      if (event.status === 'SUCCEEDED' && row.attemptId) {
        const refunded = await tx.refund.aggregate({
          where: { attemptId: row.attemptId, status: 'SUCCEEDED' },
          _sum: { amount: true },
        });
        const attempt = order.payment!.attempts.find(
          (a) => a.id === row.attemptId,
        )!;
        if (refunded._sum.amount?.eq(attempt.amount))
          await tx.paymentAttempt.update({
            where: { id: attempt.id },
            data: { reviewRequired: false },
          });
      }
      await tx.order.update({
        where: { id },
        data: { version: { increment: 1 } },
      });
      await recordAdminActivity(tx, actorId, 'REFUND_UPDATED', row.id, {
        before: {
          ...row,
          provider:
            order.payment!.attempts.find((a) => a.id === row.attemptId)
              ?.provider ?? 'cod',
        },
        after: {
          ...row,
          provider:
            order.payment!.attempts.find((a) => a.id === row.attemptId)
              ?.provider ?? 'cod',
          status: event.status,
        },
      });
      if (event.status === 'SUCCEEDED')
        await queueOrderMail(
          tx,
          id,
          'refund:' + row.id,
          'Đã ghi nhận hoàn tiền',
          `${providerLabel(order.payment!.attempts.find((a) => a.id === row.attemptId)?.provider ?? 'cod')} sandbox xác nhận hoàn ${row.amount.toFixed(0)} VND. Mã hoàn tiền: ${row.id}.`,
        );
    });
  }
}
