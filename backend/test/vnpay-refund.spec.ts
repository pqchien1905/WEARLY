import { ConfigService } from '@nestjs/config';
import { createHmac } from 'node:crypto';
import {
  VnpayProvider,
  VnpayRefund,
} from '../src/integrations/payments/vnpay.provider';
const secret = 'synthetic-refund-signing-key';
const config = new ConfigService({
  VNPAY_ENABLED: 'true',
  VNPAY_TMN_CODE: 'TEST0001',
  VNPAY_HASH_SECRET: secret,
});
const mac = (data: string) =>
  createHmac('sha512', secret).update(data).digest('hex');
const refund: VnpayRefund = {
  requestId: '0123456789abcdef0123456789abcdef',
  reference: 'abcdef0123456789abcdef0123456789',
  amount: '465000',
  originalAmount: '960000',
  originalTransactionNo: '123456',
  transactionDate: new Date('2026-10-21T03:00:00Z'),
  createdAt: new Date('2026-10-22T04:00:00Z'),
  actorId: 'operator-test',
};
function reply(
  command = 'refund',
  patch: Record<string, string | undefined> = {},
) {
  const b: Record<string, string> = {
    vnp_ResponseId: 'response1',
    vnp_Command: command,
    vnp_ResponseCode: '00',
    vnp_Message: 'Synthetic result',
    vnp_TmnCode: 'TEST0001',
    vnp_TxnRef: refund.reference,
    vnp_Amount: '46500000',
    vnp_BankCode: 'NCB',
    vnp_PayDate: '20261022110000',
    vnp_TransactionNo: '987654',
    vnp_TransactionType: '03',
    vnp_TransactionStatus: '00',
    vnp_OrderInfo: 'Hoan tien ' + refund.requestId,
    ...(command === 'querydr'
      ? { vnp_PromotionCode: '', vnp_PromotionAmount: '' }
      : {}),
    ...Object.fromEntries(
      Object.entries(patch).filter(([, value]) => value !== undefined),
    ),
  };
  return { ...b, vnp_SecureHash: mac(Object.values(b).join('|')) };
}
describe('VNPay refund protocol', () => {
  it('does not assign an earlier equal-amount signed response to a different request', async () => {
    const later = { ...refund, requestId: 'ffffffffffffffffffffffffffffffff' };
    await expect(
      new VnpayProvider(config, async () => Response.json(reply())).refund(
        later,
      ),
    ).rejects.toThrow();
  });
  it('signs a single sandbox refund with persisted request identity and exact integer amount', async () => {
    const http: typeof fetch = async (url, init) => {
      expect(url).toBe(
        'https://sandbox.vnpayment.vn/merchant_webapi/api/transaction',
      );
      expect(init!.redirect).toBe('error');
      expect(init!.signal).toBeDefined();
      const b = JSON.parse(init!.body as string);
      expect(b).toMatchObject({
        vnp_RequestId: refund.requestId,
        vnp_Command: 'refund',
        vnp_TransactionType: '03',
        vnp_Amount: '46500000',
        vnp_TransactionNo: '123456',
        vnp_TransactionDate: '20261021100000',
        vnp_CreateDate: '20261022110000',
        vnp_CreateBy: 'operator-test',
      });
      const { vnp_SecureHash, ...signed } = b;
      expect(vnp_SecureHash).toBe(mac(Object.values(signed).join('|')));
      return Response.json(reply());
    };
    expect(await new VnpayProvider(config, http).refund(refund)).toEqual({
      status: 'SUCCEEDED',
      transactionNo: '987654',
    });
  });
  it('distinguishes final success, processing and rejection from acknowledgement', async () => {
    for (const [status, expected] of [
      ['05', 'PROCESSING'],
      ['06', 'PROCESSING'],
      ['09', 'FAILED'],
    ]) {
      const p = new VnpayProvider(config, async () =>
        Response.json(reply('refund', { vnp_TransactionStatus: status })),
      );
      expect((await p.refund(refund)).status).toBe(expected);
    }
    for (const patch of [
      { vnp_ResponseCode: '94' },
      { vnp_TransactionStatus: '01' },
      { vnp_ResponseCode: '99' },
    ]) {
      await expect(
        new VnpayProvider(config, async () =>
          Response.json(reply('refund', patch)),
        ).refund(refund),
      ).rejects.toThrow();
    }
  });
  it('rejects signed wrong source, amount, type, original transaction and tampering', async () => {
    for (const patch of [
      { vnp_TmnCode: 'OTHER001' },
      { vnp_TxnRef: 'other' },
      { vnp_Amount: '46500001' },
      { vnp_TransactionType: '02' },
      { vnp_TransactionNo: '123456' },
      { vnp_Command: 'querydr' },
    ])
      await expect(
        new VnpayProvider(config, async () =>
          Response.json(reply('refund', patch)),
        ).refund(refund),
      ).rejects.toThrow();
    await expect(
      new VnpayProvider(config, async () =>
        Response.json({ ...reply(), vnp_Amount: '100' }),
      ).refund(refund),
    ).rejects.toThrow();
  });
  it('queries a specific refund number and refuses a prior equal-amount refund result', async () => {
    const http: typeof fetch = async (_url, init) => {
      const b = JSON.parse(init!.body as string);
      expect(b.vnp_TransactionNo).toBe('987654');
      const keys = [
        'vnp_RequestId',
        'vnp_Version',
        'vnp_Command',
        'vnp_TmnCode',
        'vnp_TxnRef',
        'vnp_TransactionDate',
        'vnp_CreateDate',
        'vnp_IpAddr',
        'vnp_OrderInfo',
      ];
      expect(b.vnp_SecureHash).toBe(mac(keys.map((k) => b[k]).join('|')));
      return Response.json(reply('querydr'));
    };
    expect(
      (await new VnpayProvider(config, http).queryRefund(refund, '987654'))
        .status,
    ).toBe('SUCCEEDED');
    for (const patch of [
      { vnp_TransactionNo: '987653' },
      { vnp_TransactionType: '01' },
      { vnp_ResponseCode: '91' },
    ]) {
      await expect(
        new VnpayProvider(config, async () =>
          Response.json(reply('querydr', patch)),
        ).queryRefund(refund, '987654'),
      ).rejects.toThrow();
    }
  });
  it('bounds responses and refuses transport failure without a second send', async () => {
    for (const handler of [
      async () => new Response('x'.repeat(65537)),
      async () => new Response('', { status: 500 }),
      async () => {
        throw Error('lost response');
      },
    ]) {
      const http = jest.fn(handler);
      await expect(
        new VnpayProvider(config, http).refund(refund),
      ).rejects.toThrow();
      expect(http).toHaveBeenCalledTimes(1);
    }
  });
});
