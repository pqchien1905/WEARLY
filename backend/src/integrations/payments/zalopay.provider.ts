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
  vnDate,
} from './wallet-gateway';

// ZaloPay API v2 sandbox only. Production needs a separate, reviewed configuration.
const BASE = 'https://sb-openapi.zalopay.vn/v2';
const hex = (length: number) =>
  (randomUUID() + randomUUID()).replaceAll('-', '').slice(0, length);

export class ZalopayProvider implements WalletGateway {
  readonly name = 'zalopay' as const;
  readonly minAmount = 1000n;
  readonly maxAmount = 50000000n;
  // Sent as expire_duration_seconds, so the provider closes the page with us.
  readonly linkLifetimeMs = 15 * 60000;
  constructor(
    private readonly config: ConfigService,
    private readonly http: typeof fetch,
  ) {}
  get enabled() {
    return this.config.get('ZALOPAY_ENABLED') === 'true';
  }
  assertAvailable() {
    if (!this.enabled) throw unavailable('PAYMENT_UNAVAILABLE');
    this.assertConfigured();
  }
  assertConfigured() {
    if (
      ['ZALOPAY_APP_ID', 'ZALOPAY_KEY1', 'ZALOPAY_KEY2'].some(
        (key) => !this.config.get<string>(key)?.trim(),
      )
    )
      throw unavailable('PAYMENT_UNAVAILABLE');
  }
  private get appId() {
    return this.config.getOrThrow<string>('ZALOPAY_APP_ID');
  }
  private mac(data: string) {
    return hmacSha256(this.config.getOrThrow<string>('ZALOPAY_KEY1'), data);
  }
  /** app_trans_id must start with the Vietnam date: yyMMdd_<unique>. */
  reference(createdAt: Date) {
    return `${vnDate(createdAt)}_${hex(24)}`;
  }
  /** m_refund_id format: yyMMdd_appid_<unique>, kept within 32 characters. */
  refundRequestId(createdAt: Date) {
    const prefix = `${vnDate(createdAt)}_${this.appId}_`;
    return prefix + hex(Math.max(8, 32 - prefix.length));
  }
  async create(attempt: WalletAttempt) {
    this.assertAvailable();
    if (!assertAmount(this, attempt.amount))
      throw unavailable('PAYMENT_AMOUNT_UNSUPPORTED');
    const order = {
      app_id: this.appId,
      app_user: 'wearly',
      app_trans_id: attempt.reference,
      app_time: String(attempt.createdAt.getTime()),
      amount: attempt.amount,
      item: '[]',
      embed_data: JSON.stringify({
        redirecturl: this.config.getOrThrow<string>('ZALOPAY_RETURN_URL'),
      }),
      description: 'Wearly - Thanh toan don hang ' + attempt.reference,
      bank_code: '',
      callback_url: this.config.getOrThrow<string>('ZALOPAY_CALLBACK_URL'),
      expire_duration_seconds: String(
        Math.max(
          300,
          Math.floor((attempt.expiresAt.getTime() - Date.now()) / 1000),
        ),
      ),
    };
    const mac = this.mac(
      [
        order.app_id,
        order.app_trans_id,
        order.app_user,
        order.amount,
        order.app_time,
        order.embed_data,
        order.item,
      ].join('|'),
    );
    let reply: Record<string, unknown>;
    try {
      reply = await callProvider(
        this.http,
        `${BASE}/create`,
        { ...order, mac },
        true,
      );
    } catch {
      throw unavailable();
    }
    const url = typeof reply.order_url === 'string' ? reply.order_url : '';
    if (reply.return_code !== 1 || !zalopayPaymentUrl(url)) throw unavailable();
    return url;
  }
  async query(attempt: WalletAttempt): Promise<PaymentEvent> {
    this.assertConfigured();
    const appId = this.appId,
      key1 = this.config.getOrThrow<string>('ZALOPAY_KEY1');
    try {
      const f = await callProvider(
        this.http,
        `${BASE}/query`,
        {
          app_id: appId,
          app_trans_id: attempt.reference,
          mac: this.mac([appId, attempt.reference, key1].join('|')),
        },
        true,
      );
      const base = { reference: attempt.reference, amount: attempt.amount };
      if (f.return_code === 1) {
        const transactionNo = digits(f.zp_trans_id);
        if (
          !isTransactionNo(transactionNo) ||
          digits(f.amount) !== attempt.amount
        )
          throw new Error('Invalid ZaloPay payment');
        return { ...base, status: 'PAID', transactionNo };
      }
      if (f.return_code === 3) return { ...base, status: 'PENDING' };
      if (f.return_code === 2) return { ...base, status: 'FAILED' };
      throw new Error('Unrecognized ZaloPay result');
    } catch {
      throw unavailable('PAYMENT_VERIFICATION_UNAVAILABLE');
    }
  }
  /** Callback: { data: JSON string, mac: HMAC(key2, data) }; it only reports success. */
  verifyNotification(input: unknown): PaymentEvent {
    this.assertConfigured();
    if (!input || typeof input !== 'object' || Array.isArray(input))
      throw new Error('Invalid ZaloPay callback');
    const { data, mac } = input as Record<string, unknown>;
    if (typeof data !== 'string' || data.length > 8192)
      throw new Error('Invalid ZaloPay callback');
    const expected = hmacSha256(
      this.config.getOrThrow<string>('ZALOPAY_KEY2'),
      data,
    );
    if (!sameHex(expected, mac)) throw new Error('Invalid ZaloPay signature');
    const f: unknown = JSON.parse(data);
    if (!f || typeof f !== 'object' || Array.isArray(f))
      throw new Error('Invalid ZaloPay callback');
    const fields = f as Record<string, unknown>;
    const reference = String(fields.app_trans_id ?? ''),
      amount = digits(fields.amount),
      transactionNo = digits(fields.zp_trans_id);
    if (
      String(fields.app_id ?? '') !== this.appId ||
      !/^\d{6}_[a-f0-9]{24}$/.test(reference) ||
      !/^[1-9]\d{0,13}$/.test(amount) ||
      !isTransactionNo(transactionNo)
    )
      throw new Error('Invalid ZaloPay callback');
    return { reference, amount, status: 'PAID', transactionNo };
  }
  async refund(request: WalletRefund): Promise<RefundEvent> {
    this.assertConfigured();
    const body = {
      app_id: this.appId,
      m_refund_id: request.requestId,
      zp_trans_id: request.originalTransactionNo,
      amount: request.amount,
      timestamp: String(request.createdAt.getTime()),
      description: 'Hoan tien ' + request.requestId,
    };
    try {
      const f = await callProvider(
        this.http,
        `${BASE}/refund`,
        {
          ...body,
          mac: this.mac(
            [
              body.app_id,
              body.zp_trans_id,
              body.amount,
              body.description,
              body.timestamp,
            ].join('|'),
          ),
        },
        true,
      );
      return this.refundEvent(f, request);
    } catch {
      throw unavailable('REFUND_VERIFICATION_UNAVAILABLE');
    }
  }
  async queryRefund(request: WalletRefund): Promise<RefundEvent> {
    this.assertConfigured();
    const appId = this.appId,
      timestamp = String(Date.now());
    try {
      const f = await callProvider(
        this.http,
        `${BASE}/query_refund`,
        {
          app_id: appId,
          m_refund_id: request.requestId,
          timestamp,
          mac: this.mac([appId, request.requestId, timestamp].join('|')),
        },
        true,
      );
      return this.refundEvent(f, request);
    } catch {
      throw unavailable('REFUND_VERIFICATION_UNAVAILABLE');
    }
  }
  private refundEvent(
    f: Record<string, unknown>,
    request: WalletRefund,
  ): RefundEvent {
    const transactionNo = digits(f.refund_id);
    const id = isTransactionNo(transactionNo) ? { transactionNo } : {};
    if (f.return_code === 1) {
      if (!id.transactionNo || transactionNo === request.originalTransactionNo)
        throw new Error('Invalid refund transaction');
      return { status: 'SUCCEEDED', transactionNo };
    }
    if (f.return_code === 3) return { status: 'PROCESSING', ...id };
    if (f.return_code === 2) return { status: 'FAILED', ...id };
    throw new Error('Refund outcome is not final or recognized');
  }
}

export function zalopayPaymentUrl(url: string) {
  try {
    const u = new URL(url);
    return (
      u.protocol === 'https:' &&
      (u.hostname === 'zalopay.vn' || u.hostname.endsWith('.zalopay.vn')) &&
      !u.port &&
      !u.username &&
      !u.password
    );
  } catch {
    return false;
  }
}
