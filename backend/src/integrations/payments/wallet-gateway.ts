import { ServiceUnavailableException } from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'node:crypto';

/** Online providers whose payments are confirmed by a gateway, never by staff. */
export const onlineProviders = ['vnpay', 'momo', 'zalopay'] as const;
export type OnlineProvider = (typeof onlineProviders)[number];
export const walletProviders = ['momo', 'zalopay'] as const;
export type WalletProvider = (typeof walletProviders)[number];
export const paymentProviders = ['cod', 'free', ...onlineProviders] as const;
export const isOnlineProvider = (p: string | undefined | null) =>
  (onlineProviders as readonly string[]).includes(p ?? '');
export const providerLabel = (p: string) =>
  (
    ({
      cod: 'COD',
      free: 'Miễn thanh toán',
      vnpay: 'VNPay',
      momo: 'MoMo',
      zalopay: 'ZaloPay',
    }) as Record<string, string>
  )[p] ?? p;

export type PaymentEvent = {
  reference: string;
  amount: string;
  status: 'PAID' | 'FAILED' | 'PENDING' | 'NOT_FOUND';
  transactionNo?: string;
};
export type RefundEvent = {
  status: 'SUCCEEDED' | 'PROCESSING' | 'FAILED';
  /** VNPay always returns one; a wallet may not for a rejected request. */
  transactionNo?: string;
};
export type WalletAttempt = {
  reference: string;
  amount: string;
  createdAt: Date;
  expiresAt: Date;
};
export type WalletRefund = {
  requestId: string;
  reference: string;
  amount: string;
  originalAmount: string;
  originalTransactionNo: string;
  createdAt: Date;
};
export interface WalletGateway {
  readonly name: WalletProvider;
  readonly enabled: boolean;
  readonly minAmount: bigint;
  readonly maxAmount: bigint;
  /** How long the provider keeps the payment page open; attempts expire with it. */
  readonly linkLifetimeMs: number;
  assertAvailable(): void;
  assertConfigured(): void;
  /** Provider-specific merchant reference for a new attempt (max 32 chars). */
  reference(createdAt: Date): string;
  /** Provider-specific refund identifier (max 32 chars). */
  refundRequestId(createdAt: Date): string;
  /** Registers the payment with the provider and returns its payment page. */
  create(attempt: WalletAttempt): Promise<string>;
  query(attempt: WalletAttempt): Promise<PaymentEvent>;
  /** Verifies a server-to-server notification. Throws on any invalid field. */
  verifyNotification(body: unknown): PaymentEvent;
  refund(request: WalletRefund): Promise<RefundEvent>;
  queryRefund(request: WalletRefund): Promise<RefundEvent>;
}
export const WALLET_HTTP = 'WALLET_HTTP';
export const MOMO_GATEWAY = 'MOMO_GATEWAY';
export const ZALOPAY_GATEWAY = 'ZALOPAY_GATEWAY';

export const hmacSha256 = (key: string, data: string) =>
  createHmac('sha256', key).update(data, 'utf8').digest('hex');
export function sameHex(expected: string, actual: unknown) {
  return (
    typeof actual === 'string' &&
    /^[a-fA-F0-9]{64}$/.test(actual) &&
    timingSafeEqual(Buffer.from(expected, 'hex'), Buffer.from(actual, 'hex'))
  );
}
/** yyMMdd in Vietnam time, as ZaloPay references require. */
export function vnDate(date: Date) {
  return new Date(date.getTime() + 7 * 3600000)
    .toISOString()
    .slice(2, 10)
    .replace(/-/g, '');
}
export function unavailable(code = 'PAYMENT_PROVIDER_UNAVAILABLE') {
  return new ServiceUnavailableException({
    code,
    message: 'Payment provider is temporarily unavailable; try again',
  });
}
/**
 * Bounded HTTPS call to a fixed provider endpoint. Wallet query/create replies
 * are unsigned, so the authenticated TLS channel and `redirect: 'error'` are the
 * only provenance guarantees; never follow redirects or accept other hosts.
 */
export async function callProvider(
  http: typeof fetch,
  url: string,
  body: Record<string, unknown>,
  form = false,
): Promise<Record<string, unknown>> {
  const response = await http(url, {
    method: 'POST',
    headers: {
      'Content-Type': form
        ? 'application/x-www-form-urlencoded'
        : 'application/json; charset=UTF-8',
    },
    body: form
      ? new URLSearchParams(
          Object.entries(body).map(([k, v]) => [k, String(v)]),
        ).toString()
      : JSON.stringify(body),
    signal: AbortSignal.timeout(10000),
    redirect: 'error',
  });
  if (!response.ok || !response.body) throw new Error('Provider unavailable');
  const reader = response.body.getReader(),
    chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 65536) throw new Error('Provider response too large');
      chunks.push(value);
    }
  } finally {
    await reader.cancel().catch(() => undefined);
    reader.releaseLock();
  }
  const parsed: unknown = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed))
    throw new Error('Invalid provider response');
  return parsed as Record<string, unknown>;
}
/** Integer VND string within the provider limits. */
export function assertAmount(gateway: WalletGateway, amount: string) {
  if (
    !/^[1-9]\d{0,13}$/.test(amount) ||
    BigInt(amount) < gateway.minAmount ||
    BigInt(amount) > gateway.maxAmount
  )
    return false;
  return true;
}
/** Provider numbers arrive as JSON numbers or strings; normalize to a string. */
export const digits = (value: unknown): string =>
  typeof value === 'number' && Number.isSafeInteger(value) && value > 0
    ? String(value)
    : typeof value === 'string'
      ? value
      : '';
export const isTransactionNo = (value: string, max = 15) =>
  new RegExp(`^[1-9]\\d{0,${max - 1}}$`).test(value);
