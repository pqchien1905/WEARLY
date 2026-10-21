import { ConfigService } from '@nestjs/config';
import {
  BadRequestException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHmac, timingSafeEqual, randomUUID } from 'node:crypto';
export type VnpayAttempt = {
  reference: string;
  amount: string;
  createdAt: Date;
  expiresAt: Date;
  ipAddress: string;
};
export type VnpayEvent = {
  reference: string;
  amount: string;
  status: 'PAID' | 'FAILED' | 'PENDING' | 'NOT_FOUND';
  transactionNo?: string;
};
export type VnpayRefund = {
  requestId: string;
  reference: string;
  amount: string;
  originalAmount: string;
  originalTransactionNo: string;
  transactionDate: Date;
  createdAt: Date;
  actorId: string;
};
export type VnpayRefundEvent = {
  status: 'SUCCEEDED' | 'PROCESSING' | 'FAILED';
  transactionNo: string;
};
export class VnpayProvider {
  constructor(
    private readonly config: ConfigService,
    private readonly http: typeof fetch,
  ) {}
  get enabled() {
    return this.config.get('VNPAY_ENABLED') === 'true';
  }
  assertAvailable() {
    if (!this.enabled)
      throw new ServiceUnavailableException({
        code: 'PAYMENT_UNAVAILABLE',
        message: 'VNPay sandbox is not configured',
      });
  }
  private hash(value: string) {
    return createHmac(
      'sha512',
      this.config.getOrThrow<string>('VNPAY_HASH_SECRET'),
    )
      .update(value, 'utf8')
      .digest('hex');
  }
  private verify(value: string, signature: string | undefined) {
    if (
      !signature ||
      !/^[a-fA-F0-9]{128}$/.test(signature) ||
      !timingSafeEqual(
        Buffer.from(this.hash(value), 'hex'),
        Buffer.from(signature, 'hex'),
      )
    )
      throw new BadRequestException({
        code: 'VNPAY_INVALID_SIGNATURE',
        message: 'Invalid payment signature',
      });
  }
  private fields(input: unknown): Record<string, string> {
    if (
      !input ||
      typeof input !== 'object' ||
      Array.isArray(input) ||
      Object.keys(input).length > 40
    )
      throw new BadRequestException('Invalid payment data');
    const result: Record<string, string> = {};
    for (const [key, value] of Object.entries(input)) {
      if (
        !/^vnp_[A-Za-z]+$/.test(key) ||
        typeof value !== 'string' ||
        value.length > 512
      )
        throw new BadRequestException('Invalid payment field');
      result[key] = value;
    }
    return result;
  }
  checkout(attempt: VnpayAttempt): string {
    this.assertAvailable();
    if (!/^[1-9]\d{0,9}$/.test(attempt.amount))
      throw new BadRequestException({
        code: 'PAYMENT_AMOUNT_UNSUPPORTED',
        message: 'VNPay amount is outside the supported range',
      });
    const params = {
      vnp_Version: '2.1.0',
      vnp_Command: 'pay',
      vnp_TmnCode: this.config.getOrThrow<string>('VNPAY_TMN_CODE'),
      vnp_Amount: (BigInt(attempt.amount) * 100n).toString(),
      vnp_CurrCode: 'VND',
      vnp_TxnRef: attempt.reference,
      vnp_OrderInfo: 'Thanh toan don hang ' + attempt.reference,
      vnp_OrderType: 'other',
      vnp_Locale: 'vn',
      vnp_ReturnUrl: this.config.getOrThrow<string>('VNPAY_RETURN_URL'),
      vnp_IpAddr: attempt.ipAddress,
      vnp_CreateDate: gatewayTime(attempt.createdAt),
      vnp_ExpireDate: gatewayTime(attempt.expiresAt),
    };
    const query = encoded(params);
    return (
      'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html?' +
      query +
      '&vnp_SecureHash=' +
      this.hash(query)
    );
  }
  verifyIpn(input: Record<string, unknown>): VnpayEvent {
    this.assertAvailable();
    const fields = this.fields(input),
      { vnp_SecureHash, ...signed } = fields;
    delete signed.vnp_SecureHashType;
    this.verify(encoded(signed), vnp_SecureHash);
    return this.event(fields);
  }
  private event(fields: Record<string, string>): VnpayEvent {
    if (
      fields.vnp_TmnCode !== this.config.get('VNPAY_TMN_CODE') ||
      !/^[a-zA-Z0-9]{1,100}$/.test(fields.vnp_TxnRef ?? '') ||
      !/^\d{1,12}$/.test(fields.vnp_Amount ?? '') ||
      BigInt(fields.vnp_Amount) % 100n !== 0n ||
      !/^\d{2}$/.test(fields.vnp_ResponseCode ?? '') ||
      !/^\d{2}$/.test(fields.vnp_TransactionStatus ?? '')
    )
      throw new BadRequestException('Invalid payment result');
    const status =
      fields.vnp_ResponseCode === '00' && fields.vnp_TransactionStatus === '00'
        ? 'PAID'
        : fields.vnp_TransactionStatus === '02'
          ? 'FAILED'
          : 'PENDING';
    if (
      status === 'PAID' &&
      !/^[1-9]\d{0,14}$/.test(fields.vnp_TransactionNo ?? '')
    )
      throw new BadRequestException('Invalid transaction number');
    return {
      reference: fields.vnp_TxnRef,
      amount: (BigInt(fields.vnp_Amount) / 100n).toString(),
      status,
      transactionNo: status === 'PAID' ? fields.vnp_TransactionNo : undefined,
    };
  }
  async query(attempt: VnpayAttempt): Promise<VnpayEvent> {
    this.assertAvailable();
    const data: Record<string, string> = {
      vnp_RequestId: randomUUID().replaceAll('-', ''),
      vnp_Version: '2.1.0',
      vnp_Command: 'querydr',
      vnp_TmnCode: this.config.getOrThrow<string>('VNPAY_TMN_CODE'),
      vnp_TxnRef: attempt.reference,
      vnp_TransactionDate: gatewayTime(attempt.createdAt),
      vnp_CreateDate: gatewayTime(new Date()),
      vnp_IpAddr: '127.0.0.1',
      vnp_OrderInfo: 'Truy van don hang ' + attempt.reference,
    };
    data.vnp_SecureHash = this.hash(Object.values(data).join('|'));
    try {
      const fields = await this.post(data);
      const order = [
        'vnp_ResponseId',
        'vnp_Command',
        'vnp_ResponseCode',
        'vnp_Message',
        'vnp_TmnCode',
        'vnp_TxnRef',
        'vnp_Amount',
        'vnp_BankCode',
        'vnp_PayDate',
        'vnp_TransactionNo',
        'vnp_TransactionType',
        'vnp_TransactionStatus',
        'vnp_OrderInfo',
        'vnp_PromotionCode',
        'vnp_PromotionAmount',
      ];
      this.verify(
        order.map((key) => fields[key] ?? '').join('|'),
        fields.vnp_SecureHash,
      );
      if (
        fields.vnp_Command !== 'querydr' ||
        fields.vnp_TmnCode !== data.vnp_TmnCode ||
        fields.vnp_TxnRef !== attempt.reference
      )
        throw new Error('Mismatched query result');
      if (fields.vnp_ResponseCode === '91')
        return {
          reference: attempt.reference,
          amount: attempt.amount,
          status: 'NOT_FOUND',
        };
      if (
        fields.vnp_ResponseCode !== '00' ||
        fields.vnp_TransactionType !== '01'
      )
        throw new Error('Query did not verify a payment');
      const event = this.event(fields);
      if (event.amount !== attempt.amount)
        throw new Error('Mismatched payment amount');
      return event;
    } catch {
      throw new ServiceUnavailableException({
        code: 'PAYMENT_VERIFICATION_UNAVAILABLE',
        message: 'Payment could not be verified; try again',
      });
    }
  }
  private async post(data: Record<string, string>) {
    const response = await this.http(
      'https://sandbox.vnpayment.vn/merchant_webapi/api/transaction',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
        signal: AbortSignal.timeout(5000),
        redirect: 'error',
      },
    );
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
    return this.fields(JSON.parse(Buffer.concat(chunks).toString('utf8')));
  }
  private refundType(request: VnpayRefund) {
    if (
      !/^[1-9]\d{0,9}$/.test(request.amount) ||
      !/^[1-9]\d{0,9}$/.test(request.originalAmount) ||
      BigInt(request.amount) > BigInt(request.originalAmount) ||
      !/^[1-9]\d{0,14}$/.test(request.originalTransactionNo)
    )
      throw new BadRequestException('Invalid refund source or amount');
    return request.amount === request.originalAmount ? '02' : '03';
  }
  async refund(request: VnpayRefund): Promise<VnpayRefundEvent> {
    this.assertAvailable();
    const data: Record<string, string> = {
      vnp_RequestId: request.requestId,
      vnp_Version: '2.1.0',
      vnp_Command: 'refund',
      vnp_TmnCode: this.config.getOrThrow<string>('VNPAY_TMN_CODE'),
      vnp_TransactionType: this.refundType(request),
      vnp_TxnRef: request.reference,
      vnp_Amount: (BigInt(request.amount) * 100n).toString(),
      vnp_TransactionNo: request.originalTransactionNo,
      vnp_TransactionDate: gatewayTime(request.transactionDate),
      vnp_CreateBy: request.actorId,
      vnp_CreateDate: gatewayTime(request.createdAt),
      vnp_IpAddr: '127.0.0.1',
      vnp_OrderInfo: 'Hoan tien ' + request.requestId,
    };
    data.vnp_SecureHash = this.hash(Object.values(data).join('|'));
    return this.refundResult(request, data, false);
  }
  async queryRefund(
    request: VnpayRefund,
    transactionNo: string,
  ): Promise<VnpayRefundEvent> {
    this.assertAvailable();
    this.refundType(request);
    if (
      !/^[1-9]\d{0,14}$/.test(transactionNo) ||
      transactionNo === request.originalTransactionNo
    )
      throw new BadRequestException('Use the refund transaction number');
    const data: Record<string, string> = {
      vnp_RequestId: randomUUID().replaceAll('-', ''),
      vnp_Version: '2.1.0',
      vnp_Command: 'querydr',
      vnp_TmnCode: this.config.getOrThrow<string>('VNPAY_TMN_CODE'),
      vnp_TxnRef: request.reference,
      vnp_TransactionDate: gatewayTime(request.transactionDate),
      vnp_CreateDate: gatewayTime(new Date()),
      vnp_IpAddr: '127.0.0.1',
      vnp_OrderInfo: 'Truy van hoan tien ' + request.requestId,
    };
    data.vnp_SecureHash = this.hash(Object.values(data).join('|'));
    data.vnp_TransactionNo = transactionNo;
    return this.refundResult(request, data, true, transactionNo);
  }
  private async refundResult(
    request: VnpayRefund,
    data: Record<string, string>,
    query: boolean,
    transactionNo?: string,
  ): Promise<VnpayRefundEvent> {
    try {
      const f = await this.post(data);
      const keys = [
        'vnp_ResponseId',
        'vnp_Command',
        'vnp_ResponseCode',
        'vnp_Message',
        'vnp_TmnCode',
        'vnp_TxnRef',
        'vnp_Amount',
        'vnp_BankCode',
        'vnp_PayDate',
        'vnp_TransactionNo',
        'vnp_TransactionType',
        'vnp_TransactionStatus',
        'vnp_OrderInfo',
        ...(query ? ['vnp_PromotionCode', 'vnp_PromotionAmount'] : []),
      ];
      this.verify(keys.map((k) => f[k] ?? '').join('|'), f.vnp_SecureHash);
      if (
        f.vnp_Command !== data.vnp_Command ||
        f.vnp_ResponseCode !== '00' ||
        f.vnp_TmnCode !== data.vnp_TmnCode ||
        f.vnp_TxnRef !== request.reference ||
        (!query && f.vnp_OrderInfo !== 'Hoan tien ' + request.requestId) ||
        f.vnp_Amount !== (BigInt(request.amount) * 100n).toString() ||
        f.vnp_TransactionType !== this.refundType(request) ||
        !/^[1-9]\d{0,14}$/.test(f.vnp_TransactionNo ?? '') ||
        f.vnp_TransactionNo === request.originalTransactionNo ||
        (query && f.vnp_TransactionNo !== transactionNo)
      )
        throw new Error('Refund result mismatch');
      const status =
        f.vnp_TransactionStatus === '00'
          ? 'SUCCEEDED'
          : ['05', '06'].includes(f.vnp_TransactionStatus)
            ? 'PROCESSING'
            : f.vnp_TransactionStatus === '09'
              ? 'FAILED'
              : null;
      if (!status) throw new Error('Refund result is not final or recognized');
      return { status, transactionNo: f.vnp_TransactionNo };
    } catch {
      throw new ServiceUnavailableException({
        code: 'REFUND_VERIFICATION_UNAVAILABLE',
        message: 'Refund outcome is unknown; verify it before any new request',
      });
    }
  }
}
function encoded(fields: Record<string, string>) {
  return Object.keys(fields)
    .sort()
    .map(
      (key) =>
        `${encodeURIComponent(key)}=${encodeURIComponent(fields[key]).replace(/%20/g, '+')}`,
    )
    .join('&');
}
export function gatewayTime(date: Date): string {
  return new Date(date.getTime() + 7 * 3600000)
    .toISOString()
    .slice(0, 19)
    .replace(/[-:T]/g, '');
}
