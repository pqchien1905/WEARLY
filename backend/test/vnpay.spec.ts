import { ConfigService } from '@nestjs/config';
import { createHmac } from 'node:crypto';
import {
  VnpayProvider,
  VnpayAttempt,
} from '../src/integrations/payments/vnpay.provider';

const secret = 'sandbox-test-secret-not-a-real-key';
const config = new ConfigService({
  VNPAY_ENABLED: 'true',
  VNPAY_TMN_CODE: 'TEST0001',
  VNPAY_HASH_SECRET: secret,
  VNPAY_RETURN_URL: 'http://localhost:3000/api/v1/payments/vnpay/return',
});
const attempt: VnpayAttempt = {
  reference: '0123456789abcdef0123456789abcdef',
  amount: '520000',
  createdAt: new Date('2026-10-21T03:00:00Z'),
  expiresAt: new Date('2026-10-21T03:15:00Z'),
  ipAddress: '127.0.0.1',
};
const mac = (value: string) =>
  createHmac('sha512', secret).update(value).digest('hex');
function signedIpn(patch: Record<string, string> = {}) {
  const body: Record<string, string> = {
    vnp_TmnCode: 'TEST0001',
    vnp_TxnRef: attempt.reference,
    vnp_Amount: '52000000',
    vnp_TransactionNo: '12345678',
    vnp_ResponseCode: '00',
    vnp_TransactionStatus: '00',
    ...patch,
  };
  const sorted = new URLSearchParams();
  Object.keys(body)
    .sort()
    .forEach((key) => sorted.set(key, body[key]));
  return { ...body, vnp_SecureHash: mac(sorted.toString()) };
}
function queryReply(patch: Record<string, string> = {}) {
  const fields = [
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
  const body: Record<string, string> = {
    vnp_ResponseId: 'response1',
    vnp_Command: 'querydr',
    vnp_ResponseCode: '00',
    vnp_Message: 'Success',
    vnp_TmnCode: 'TEST0001',
    vnp_TxnRef: attempt.reference,
    vnp_Amount: '52000000',
    vnp_BankCode: 'NCB',
    vnp_PayDate: '20261021100100',
    vnp_TransactionNo: '12345678',
    vnp_TransactionType: '01',
    vnp_TransactionStatus: '00',
    vnp_OrderInfo: 'Thanh toan don hang',
    vnp_PromotionCode: '',
    vnp_PromotionAmount: '',
    ...patch,
  };
  return {
    ...body,
    vnp_SecureHash: mac(fields.map((key) => body[key]).join('|')),
  };
}
describe('VNPay sandbox protocol', () => {
  it('signs a fixed sandbox URL with exact VND scaling, sorted fields and GMT+7 dates', () => {
    const url = new URL(new VnpayProvider(config, fetch).checkout(attempt));
    expect(url.origin + url.pathname).toBe(
      'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html',
    );
    expect(Object.fromEntries(url.searchParams)).toMatchObject({
      vnp_Amount: '52000000',
      vnp_CreateDate: '20261021100000',
      vnp_ExpireDate: '20261021101500',
      vnp_TmnCode: 'TEST0001',
      vnp_TxnRef: attempt.reference,
      vnp_Version: '2.1.0',
    });
    const signature = url.searchParams.get('vnp_SecureHash');
    url.searchParams.delete('vnp_SecureHash');
    expect(signature).toBe(mac(url.searchParams.toString()));
    expect([...url.searchParams.keys()]).toEqual(
      [...url.searchParams.keys()].sort(),
    );
    expect(url.toString()).not.toContain(secret);
    expect(
      new URL(
        new VnpayProvider(config, fetch).checkout({
          ...attempt,
          amount: '9999999999',
        }),
      ).searchParams.get('vnp_Amount'),
    ).toBe('999999999900');
    for (const amount of ['0', '-1', '1.5', '10000000000'])
      expect(() =>
        new VnpayProvider(config, fetch).checkout({ ...attempt, amount }),
      ).toThrow();
  });
  it('does not enable sandbox payments implicitly or expose secrets in errors', () => {
    const provider = new VnpayProvider(
      new ConfigService({ VNPAY_ENABLED: 'false' }),
      fetch,
    );
    expect(provider.enabled).toBe(false);
    expect(() => provider.checkout(attempt)).toThrow(
      'VNPay sandbox is not configured',
    );
  });
  it('verifies signed callbacks and rejects tampering, duplicate values and another merchant', () => {
    const provider = new VnpayProvider(config, fetch),
      valid = signedIpn();
    expect(provider.verifyIpn(valid)).toMatchObject({
      reference: attempt.reference,
      amount: '520000',
      status: 'PAID',
      transactionNo: '12345678',
    });
    for (const body of [
      { ...valid, vnp_Amount: '100' },
      { ...valid, vnp_SecureHash: 'a' },
      { ...valid, vnp_TxnRef: [attempt.reference, 'other'] },
      signedIpn({ vnp_TmnCode: 'OTHER001' }),
      signedIpn({ vnp_Amount: '52000001' }),
      signedIpn({ vnp_TransactionNo: '0' }),
    ])
      expect(() => provider.verifyIpn(body)).toThrow();
    expect(
      provider.verifyIpn(
        signedIpn({
          vnp_ResponseCode: '24',
          vnp_TransactionStatus: '02',
          vnp_TransactionNo: '0',
        }),
      ).status,
    ).toBe('FAILED');
    expect(
      provider.verifyIpn(signedIpn({ vnp_TransactionStatus: '01' })).status,
    ).toBe('PENDING');
  });
  it('signs querydr requests and accepts only authenticated replies for this attempt', async () => {
    const http: typeof fetch = async (url, init) => {
      expect(url).toBe(
        'https://sandbox.vnpayment.vn/merchant_webapi/api/transaction',
      );
      const b = JSON.parse(init!.body as string);
      expect(b.vnp_TransactionDate).toBe('20261021100000');
      expect(b.vnp_TxnRef).toBe(attempt.reference);
      expect(b.vnp_SecureHash).toBe(
        mac(
          [
            b.vnp_RequestId,
            '2.1.0',
            'querydr',
            'TEST0001',
            attempt.reference,
            '20261021100000',
            b.vnp_CreateDate,
            '127.0.0.1',
            b.vnp_OrderInfo,
          ].join('|'),
        ),
      );
      return Response.json(queryReply());
    };
    await expect(
      new VnpayProvider(config, http).query(attempt),
    ).resolves.toMatchObject({ status: 'PAID', amount: '520000' });
    for (const body of [
      { ...queryReply(), vnp_Amount: '1' },
      queryReply({ vnp_TxnRef: 'other' }),
      queryReply({ vnp_TransactionType: '02' }),
      queryReply({ vnp_Amount: '100' }),
    ]) {
      await expect(
        new VnpayProvider(config, async () => Response.json(body)).query(
          attempt,
        ),
      ).rejects.toThrow();
    }
    await expect(
      new VnpayProvider(config, async () =>
        Response.json(
          queryReply({
            vnp_ResponseCode: '91',
            vnp_Amount: '0',
            vnp_TransactionNo: '0',
            vnp_TransactionStatus: '',
          }),
        ),
      ).query(attempt),
    ).resolves.toMatchObject({ status: 'NOT_FOUND' });
  });
  it('bounds provider response size and refuses HTTP errors or failed transports', async () => {
    for (const http of [
      async () => new Response('x'.repeat(65537)),
      async () => new Response('upstream', { status: 500 }),
      async () => {
        throw new Error('Transport failed');
      },
    ]) {
      await expect(
        new VnpayProvider(config, http).query(attempt),
      ).rejects.toThrow();
    }
  });
  it('aborts a stalled provider request after five seconds', async () => {
    const started = Date.now();
    const http: typeof fetch = (_url, init) =>
      new Promise((_resolve, reject) => {
        init!.signal!.addEventListener(
          'abort',
          () => reject(new Error('Aborted')),
          { once: true },
        );
      });
    await expect(
      new VnpayProvider(config, http).query(attempt),
    ).rejects.toThrow('Payment could not be verified');
    expect(Date.now() - started).toBeLessThan(7000);
  }, 8000);
});
