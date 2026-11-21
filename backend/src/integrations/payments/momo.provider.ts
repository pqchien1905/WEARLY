import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import {
  PaymentEvent,
  RefundEvent,
  WalletAttempt,
  WalletGateway,
  WalletRefund,
  assertAmount,
  callProvider,
  digits,
  hmacSha256,
  isTransactionNo,
  sameHex,
  unavailable,
} from './wallet-gateway';

// MoMo sandbox only. Production needs a separate, reviewed configuration.
const BASE = 'https://test-payment.momo.vn/v2/gateway';
const PENDING = new Set([1000, 7000, 7002, 9000]);
const FAILED = new Set([
  1001, 1002, 1003, 1004, 1006, 1007, 1017, 1026, 4001, 4002, 4100,
]);
const NOT_FOUND = new Set([42, 1005]);
const hex = () => randomUUID().replaceAll('-', '');

export class MomoProvider implements WalletGateway {
  readonly name = 'momo' as const;
  readonly minAmount = 1000n;
  readonly maxAmount = 50000000n;
  // The sandbox ignores orderExpireTime and keeps pages open for 100 minutes
  // (observed 2026-11-09). An earlier local expiry would block reconciliation.
  readonly linkLifetimeMs = 100 * 60000;
  constructor(
    private readonly config: ConfigService,
    private readonly http: typeof fetch,
  ) {}
  get enabled() {
    return this.config.get('MOMO_ENABLED') === 'true';
  }
  assertAvailable() {
    if (!this.enabled) throw unavailable('PAYMENT_UNAVAILABLE');
  }
  private get partnerCode() {
    return this.config.getOrThrow<string>('MOMO_PARTNER_CODE');
  }
  private get accessKey() {
    return this.config.getOrThrow<string>('MOMO_ACCESS_KEY');
  }
  private sign(raw: string) {
    return hmacSha256(this.config.getOrThrow<string>('MOMO_SECRET_KEY'), raw);
  }
  reference() {
    return hex();
  }
  refundRequestId() {
    return hex();
  }
  async create(attempt: WalletAttempt) {
    this.assertAvailable();
    if (!assertAmount(this, attempt.amount))
      throw unavailable('PAYMENT_AMOUNT_UNSUPPORTED');
    const body = {
      partnerCode: this.partnerCode,
      requestId: attempt.reference,
      amount: Number(attempt.amount),
      orderId: attempt.reference,
      orderInfo: 'Thanh toan don hang ' + attempt.reference,
      redirectUrl: this.config.getOrThrow<string>('MOMO_RETURN_URL'),
      ipnUrl: this.config.getOrThrow<string>('MOMO_IPN_URL'),
      requestType: 'payWithMethod',
      extraData: '',
      lang: 'vi',
      orderExpireTime: Math.max(
        1,
        Math.floor((attempt.expiresAt.getTime() - Date.now()) / 60000),
      ),
    };
    const signature = this.sign(
      `accessKey=${this.accessKey}&amount=${body.amount}&extraData=${body.extraData}` +
        `&ipnUrl=${body.ipnUrl}&orderId=${body.orderId}&orderInfo=${body.orderInfo}` +
        `&partnerCode=${body.partnerCode}&redirectUrl=${body.redirectUrl}` +
        `&requestId=${body.requestId}&requestType=${body.requestType}`,
    );
    let reply: Record<string, unknown>;
    try {
      reply = await callProvider(this.http, `${BASE}/api/create`, {
        ...body,
        signature,
      });
    } catch {
      throw unavailable();
    }
    const url = typeof reply.payUrl === 'string' ? reply.payUrl : '';
    if (
      reply.resultCode !== 0 ||
      reply.orderId !== attempt.reference ||
      digits(reply.amount) !== attempt.amount ||
      !momoPaymentUrl(url)
    )
      throw unavailable();
    return url;
  }
  private event(
    f: Record<string, unknown>,
    reference: string,
    amount: string,
  ): PaymentEvent {
    const code = f.resultCode;
    if (
      typeof code !== 'number' ||
      f.partnerCode !== this.partnerCode ||
      f.orderId !== reference
    )
      throw new Error('Invalid MoMo result');
    if (code === 0) {
      const transactionNo = digits(f.transId);
      if (!isTransactionNo(transactionNo) || digits(f.amount) !== amount)
        throw new Error('Invalid MoMo payment');
      return { reference, amount, status: 'PAID', transactionNo };
    }
    if (PENDING.has(code)) return { reference, amount, status: 'PENDING' };
    if (FAILED.has(code)) return { reference, amount, status: 'FAILED' };
    if (NOT_FOUND.has(code)) return { reference, amount, status: 'NOT_FOUND' };
    throw new Error('Unrecognized MoMo result');
  }
  async query(attempt: WalletAttempt): Promise<PaymentEvent> {
    this.assertAvailable();
    try {
      return this.event(
        await this.queryPayment(attempt.reference),
        attempt.reference,
        attempt.amount,
      );
    } catch {
      throw unavailable('PAYMENT_VERIFICATION_UNAVAILABLE');
    }
  }
  private queryPayment(orderId: string) {
    const requestId = hex();
    return callProvider(this.http, `${BASE}/api/query`, {
      partnerCode: this.partnerCode,
      requestId,
      orderId,
      lang: 'vi',
      signature: this.sign(
        `accessKey=${this.accessKey}&orderId=${orderId}` +
          `&partnerCode=${this.partnerCode}&requestId=${requestId}`,
      ),
    });
  }
  /** IPN and browser return share the same signed field set. */
  verifyNotification(input: unknown): PaymentEvent {
    this.assertAvailable();
    if (!input || typeof input !== 'object' || Array.isArray(input))
      throw new Error('Invalid MoMo notification');
    const f = input as Record<string, unknown>;
    const v = (k: string) => {
      const value = f[k];
      if (value === undefined || value === null) return '';
      if (typeof value === 'string' || typeof value === 'number')
        return String(value);
      throw new Error('Invalid MoMo field');
    };
    const raw =
      `accessKey=${this.accessKey}&amount=${v('amount')}&extraData=${v('extraData')}` +
      `&message=${v('message')}&orderId=${v('orderId')}&orderInfo=${v('orderInfo')}` +
      `&orderType=${v('orderType')}&partnerCode=${v('partnerCode')}&payType=${v('payType')}` +
      `&requestId=${v('requestId')}&responseTime=${v('responseTime')}` +
      `&resultCode=${v('resultCode')}&transId=${v('transId')}`;
    if (!sameHex(this.sign(raw), f.signature))
      throw new Error('Invalid MoMo signature');
    const amount = v('amount'),
      orderId = v('orderId');
    if (!/^[a-f0-9]{32}$/.test(orderId) || !/^[1-9]\d{0,13}$/.test(amount))
      throw new Error('Invalid MoMo notification');
    return this.event(
      { ...f, resultCode: Number(v('resultCode')) },
      orderId,
      amount,
    );
  }
  async refund(request: WalletRefund): Promise<RefundEvent> {
    this.assertAvailable();
    const body = {
      partnerCode: this.partnerCode,
      orderId: request.requestId,
      requestId: request.requestId,
      amount: Number(request.amount),
      transId: Number(request.originalTransactionNo),
      lang: 'vi',
      description: 'Hoan tien ' + request.requestId,
    };
    try {
      const f = await callProvider(this.http, `${BASE}/api/refund`, {
        ...body,
        signature: this.sign(
          `accessKey=${this.accessKey}&amount=${body.amount}&description=${body.description}` +
            `&orderId=${body.orderId}&partnerCode=${body.partnerCode}` +
            `&requestId=${body.requestId}&transId=${body.transId}`,
        ),
      });
      if (f.partnerCode !== body.partnerCode || f.orderId !== body.orderId)
        throw new Error('Refund result mismatch');
      return this.refundEvent(f, request);
    } catch {
      throw unavailable('REFUND_VERIFICATION_UNAVAILABLE');
    }
  }
  /** Reads the refund through the original payment's refund ledger. */
  async queryRefund(request: WalletRefund): Promise<RefundEvent> {
    this.assertAvailable();
    try {
      const f = await this.queryPayment(request.reference);
      if (f.partnerCode !== this.partnerCode || f.orderId !== request.reference)
        throw new Error('Refund query mismatch');
      const rows = Array.isArray(f.refundTrans) ? f.refundTrans : [];
      const row = rows.find(
        (r): r is Record<string, unknown> =>
          !!r &&
          typeof r === 'object' &&
          (r as Record<string, unknown>).orderId === request.requestId,
      );
      if (row) return this.refundEvent(row, request);
      // No refund ledger entry long after the synchronous request: none was made.
      if (Date.now() - request.createdAt.getTime() > 5 * 60000)
        return { status: 'FAILED' };
      throw new Error('Refund not visible yet');
    } catch {
      throw unavailable('REFUND_VERIFICATION_UNAVAILABLE');
    }
  }
  private refundEvent(
    f: Record<string, unknown>,
    request: WalletRefund,
  ): RefundEvent {
    // Refund replies may omit the amount; when present it must match exactly.
    if (f.amount !== undefined && digits(f.amount) !== request.amount)
      throw new Error('Refund amount mismatch');
    const transactionNo = digits(f.transId);
    if (f.resultCode === 0) {
      if (
        !isTransactionNo(transactionNo) ||
        transactionNo === request.originalTransactionNo
      )
        throw new Error('Invalid refund transaction');
      return { status: 'SUCCEEDED', transactionNo };
    }
    if (typeof f.resultCode === 'number' && PENDING.has(f.resultCode))
      return {
        status: 'PROCESSING',
        ...(isTransactionNo(transactionNo) ? { transactionNo } : {}),
      };
    throw new Error('Refund outcome is not final or recognized');
  }
}

export function momoPaymentUrl(url: string) {
  try {
    const u = new URL(url);
    return (
      u.protocol === 'https:' &&
      u.hostname === 'test-payment.momo.vn' &&
      !u.port &&
      !u.username &&
      !u.password
    );
  } catch {
    return false;
  }
}
