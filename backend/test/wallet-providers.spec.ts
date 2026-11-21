import { ConfigService } from '@nestjs/config';
import { createHmac } from 'node:crypto';
import {
  MomoProvider,
  momoPaymentUrl,
} from '../src/integrations/payments/momo.provider';
import {
  ZalopayProvider,
  zalopayPaymentUrl,
} from '../src/integrations/payments/zalopay.provider';
import {
  WalletAttempt,
  WalletRefund,
} from '../src/integrations/payments/wallet-gateway';

const momoSecret = 'momo-fixture-secret-not-a-key';
const key1 = 'zalopay-fixture-key1-not-a-key';
const key2 = 'zalopay-fixture-key2-not-a-key';
const config = new ConfigService({
  MOMO_ENABLED: 'true',
  MOMO_PARTNER_CODE: 'MOMOTEST',
  MOMO_ACCESS_KEY: 'ACCESSKEY01',
  MOMO_SECRET_KEY: momoSecret,
  MOMO_RETURN_URL: 'http://localhost:3000/api/v1/payments/momo/return',
  MOMO_IPN_URL: 'http://localhost:3000/api/v1/payments/momo/ipn',
  ZALOPAY_ENABLED: 'true',
  ZALOPAY_APP_ID: '2553',
  ZALOPAY_KEY1: key1,
  ZALOPAY_KEY2: key2,
  ZALOPAY_RETURN_URL: 'http://localhost:3000/api/v1/payments/zalopay/return',
  ZALOPAY_CALLBACK_URL: 'http://localhost:3000/api/v1/payments/zalopay/callback',
});
const sha256 = (key: string, value: string) =>
  createHmac('sha256', key).update(value).digest('hex');
const reply = (body: unknown) =>
  Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));
const future = () => new Date(Date.now() + 15 * 60000);

describe('MomoProvider', () => {
  const http = jest.fn<ReturnType<typeof fetch>, Parameters<typeof fetch>>();
  const momo = new MomoProvider(config, http);
  const attempt: WalletAttempt = {
    reference: '0123456789abcdef0123456789abcdef',
    amount: '520000',
    createdAt: new Date(),
    expiresAt: future(),
  };
  beforeEach(() => http.mockReset());
  const sent = () =>
    JSON.parse(String(http.mock.calls[0][1]!.body)) as Record<string, unknown>;
  function notification(patch: Record<string, string | number> = {}) {
    const f: Record<string, string | number> = {
      partnerCode: 'MOMOTEST',
      orderId: attempt.reference,
      requestId: attempt.reference,
      amount: 520000,
      orderInfo: 'Thanh toan don hang ' + attempt.reference,
      orderType: 'momo_wallet',
      transId: 4088878653,
      resultCode: 0,
      message: 'Thành công.',
      payType: 'napas',
      responseTime: 1794155468096,
      extraData: '',
      ...patch,
    };
    const raw =
      `accessKey=ACCESSKEY01&amount=${f.amount}&extraData=${f.extraData}&message=${f.message}` +
      `&orderId=${f.orderId}&orderInfo=${f.orderInfo}&orderType=${f.orderType}` +
      `&partnerCode=${f.partnerCode}&payType=${f.payType}&requestId=${f.requestId}` +
      `&responseTime=${f.responseTime}&resultCode=${f.resultCode}&transId=${f.transId}`;
    return { ...f, signature: sha256(momoSecret, raw) };
  }

  it('signs the create request and accepts only a MoMo sandbox payment page', async () => {
    http.mockReturnValueOnce(
      reply({
        resultCode: 0,
        orderId: attempt.reference,
        amount: 520000,
        payUrl: 'https://test-payment.momo.vn/v2/gateway/pay?t=abc',
      }),
    );
    await expect(momo.create(attempt)).resolves.toBe(
      'https://test-payment.momo.vn/v2/gateway/pay?t=abc',
    );
    expect(http.mock.calls[0][0]).toBe(
      'https://test-payment.momo.vn/v2/gateway/api/create',
    );
    expect(http.mock.calls[0][1]).toMatchObject({ redirect: 'error' });
    const body = sent();
    const raw =
      `accessKey=ACCESSKEY01&amount=520000&extraData=&ipnUrl=${String(body.ipnUrl)}` +
      `&orderId=${attempt.reference}&orderInfo=${String(body.orderInfo)}` +
      `&partnerCode=MOMOTEST&redirectUrl=${String(body.redirectUrl)}` +
      `&requestId=${attempt.reference}&requestType=payWithMethod`;
    expect(body.signature).toBe(sha256(momoSecret, raw));
    expect(body.orderExpireTime).toBeGreaterThanOrEqual(14);

    for (const bad of [
      { resultCode: 0, orderId: attempt.reference, amount: 520000, payUrl: 'https://evil.example/pay' },
      { resultCode: 0, orderId: 'other', amount: 520000, payUrl: 'https://test-payment.momo.vn/x' },
      { resultCode: 0, orderId: attempt.reference, amount: 1, payUrl: 'https://test-payment.momo.vn/x' },
      { resultCode: 22, message: 'amount' },
    ]) {
      http.mockReturnValueOnce(reply(bad));
      await expect(momo.create(attempt)).rejects.toMatchObject({ status: 503 });
    }
  });

  it('rejects amounts outside the MoMo range before calling the provider', async () => {
    await expect(momo.create({ ...attempt, amount: '999' })).rejects.toBeTruthy();
    await expect(
      momo.create({ ...attempt, amount: '50000001' }),
    ).rejects.toBeTruthy();
    expect(http).not.toHaveBeenCalled();
  });

  it('maps query results conservatively', async () => {
    const q = (patch: Record<string, unknown>) => {
      http.mockReturnValueOnce(
        reply({ partnerCode: 'MOMOTEST', orderId: attempt.reference, amount: 520000, ...patch }),
      );
      return momo.query(attempt);
    };
    await expect(q({ resultCode: 0, transId: 4088878653 })).resolves.toMatchObject({
      status: 'PAID',
      transactionNo: '4088878653',
    });
    await expect(q({ resultCode: 1000, transId: 0 })).resolves.toMatchObject({ status: 'PENDING' });
    await expect(q({ resultCode: 1006 })).resolves.toMatchObject({ status: 'FAILED' });
    await expect(q({ resultCode: 1005 })).resolves.toMatchObject({ status: 'NOT_FOUND' });
    // Unknown codes, a paid result without a transaction or a wrong amount are never trusted.
    await expect(q({ resultCode: 99 })).rejects.toMatchObject({ status: 503 });
    await expect(q({ resultCode: 0, transId: 0 })).rejects.toMatchObject({ status: 503 });
    await expect(q({ resultCode: 0, transId: 1, amount: 1 })).rejects.toMatchObject({ status: 503 });
    const body = JSON.parse(String(http.mock.calls[0][1]!.body)) as Record<string, string>;
    expect(body.signature).toBe(
      sha256(
        momoSecret,
        `accessKey=ACCESSKEY01&orderId=${attempt.reference}&partnerCode=MOMOTEST&requestId=${body.requestId}`,
      ),
    );
  });

  it('verifies IPN signatures and fields', () => {
    expect(momo.verifyNotification(notification())).toEqual({
      reference: attempt.reference,
      amount: '520000',
      status: 'PAID',
      transactionNo: '4088878653',
    });
    expect(momo.verifyNotification(notification({ resultCode: 1006, transId: 0 }))).toMatchObject({
      status: 'FAILED',
    });
    const forged = { ...notification(), amount: 1 };
    expect(() => momo.verifyNotification(forged)).toThrow();
    expect(() =>
      momo.verifyNotification({ ...notification(), signature: 'f'.repeat(64) }),
    ).toThrow();
    expect(() => momo.verifyNotification(notification({ partnerCode: 'OTHER' }))).toThrow();
    expect(() => momo.verifyNotification('x')).toThrow();
  });

  it('signs refunds and only settles verified outcomes', async () => {
    const refund: WalletRefund = {
      requestId: 'fedcba9876543210fedcba9876543210',
      reference: attempt.reference,
      amount: '520000',
      originalAmount: '520000',
      originalTransactionNo: '4088878653',
      createdAt: new Date(),
    };
    http.mockReturnValueOnce(
      reply({ partnerCode: 'MOMOTEST', orderId: refund.requestId, resultCode: 0, transId: 4088879999, amount: 520000 }),
    );
    await expect(momo.refund(refund)).resolves.toEqual({
      status: 'SUCCEEDED',
      transactionNo: '4088879999',
    });
    const body = sent();
    expect(body.signature).toBe(
      sha256(
        momoSecret,
        `accessKey=ACCESSKEY01&amount=520000&description=Hoan tien ${refund.requestId}` +
          `&orderId=${refund.requestId}&partnerCode=MOMOTEST&requestId=${refund.requestId}&transId=4088878653`,
      ),
    );
    http.mockReturnValueOnce(
      reply({ partnerCode: 'MOMOTEST', orderId: refund.requestId, resultCode: 43 }),
    );
    await expect(momo.refund(refund)).rejects.toMatchObject({ status: 503 });
    // The query reads the refund from the original payment's refund ledger.
    http.mockReturnValueOnce(
      reply({
        partnerCode: 'MOMOTEST',
        orderId: attempt.reference,
        resultCode: 0,
        refundTrans: [{ orderId: refund.requestId, amount: 520000, resultCode: 0, transId: 4088879999 }],
      }),
    );
    await expect(momo.queryRefund(refund)).resolves.toMatchObject({ status: 'SUCCEEDED' });
    http.mockReturnValueOnce(
      reply({ partnerCode: 'MOMOTEST', orderId: attempt.reference, resultCode: 0, refundTrans: [] }),
    );
    await expect(momo.queryRefund(refund)).rejects.toMatchObject({ status: 503 });
    http.mockReturnValueOnce(
      reply({ partnerCode: 'MOMOTEST', orderId: attempt.reference, resultCode: 0, refundTrans: [] }),
    );
    await expect(
      momo.queryRefund({ ...refund, createdAt: new Date(Date.now() - 10 * 60000) }),
    ).resolves.toEqual({ status: 'FAILED' });
  });

  it('accepts only https MoMo sandbox pages', () => {
    expect(momoPaymentUrl('https://test-payment.momo.vn/v2/gateway/pay?t=1')).toBe(true);
    expect(momoPaymentUrl('http://test-payment.momo.vn/pay')).toBe(false);
    expect(momoPaymentUrl('https://payment.momo.vn/pay')).toBe(false);
    expect(momoPaymentUrl('https://u:p@test-payment.momo.vn/pay')).toBe(false);
  });
});

describe('ZalopayProvider', () => {
  const http = jest.fn<ReturnType<typeof fetch>, Parameters<typeof fetch>>();
  const zalo = new ZalopayProvider(config, http);
  const createdAt = new Date();
  const attempt: WalletAttempt = {
    reference: zalo.reference(createdAt),
    amount: '520000',
    createdAt,
    expiresAt: future(),
  };
  beforeEach(() => http.mockReset());
  const form = () => new URLSearchParams(String(http.mock.calls[0][1]!.body));

  it('formats references and refund ids within the stored length', () => {
    expect(attempt.reference).toMatch(/^\d{6}_[a-f0-9]{24}$/);
    const id = zalo.refundRequestId(createdAt);
    expect(id).toMatch(/^\d{6}_2553_[a-f0-9]+$/);
    expect(id.length).toBeLessThanOrEqual(32);
  });

  it('signs the create order with key1', async () => {
    http.mockReturnValueOnce(
      reply({ return_code: 1, order_url: 'https://qcgateway.zalopay.vn/openinapp?order=x' }),
    );
    await expect(zalo.create(attempt)).resolves.toContain('zalopay.vn');
    expect(http.mock.calls[0][0]).toBe('https://sb-openapi.zalopay.vn/v2/create');
    const f = form();
    expect(f.get('mac')).toBe(
      sha256(
        key1,
        ['2553', attempt.reference, 'wearly', '520000', f.get('app_time'), f.get('embed_data'), '[]'].join('|'),
      ),
    );
    expect(JSON.parse(f.get('embed_data')!)).toEqual({
      redirecturl: 'http://localhost:3000/api/v1/payments/zalopay/return',
    });
    http.mockReturnValueOnce(reply({ return_code: 1, order_url: 'https://evil.example/x' }));
    await expect(zalo.create(attempt)).rejects.toMatchObject({ status: 503 });
    http.mockReturnValueOnce(reply({ return_code: 2, return_message: 'fail' }));
    await expect(zalo.create(attempt)).rejects.toMatchObject({ status: 503 });
  });

  it('maps query results and checks amount and transaction', async () => {
    const q = (body: unknown) => {
      http.mockReturnValueOnce(reply(body));
      return zalo.query(attempt);
    };
    await expect(q({ return_code: 1, zp_trans_id: 240808000012345, amount: 520000 })).resolves.toMatchObject({
      status: 'PAID',
      transactionNo: '240808000012345',
    });
    await expect(q({ return_code: 3 })).resolves.toMatchObject({ status: 'PENDING' });
    await expect(q({ return_code: 2 })).resolves.toMatchObject({ status: 'FAILED' });
    await expect(q({ return_code: 1, zp_trans_id: 1, amount: 1 })).rejects.toMatchObject({ status: 503 });
    await expect(q({ return_code: 9 })).rejects.toMatchObject({ status: 503 });
    expect(form().get('mac')).toBe(sha256(key1, ['2553', attempt.reference, key1].join('|')));
  });

  it('verifies callbacks with key2', () => {
    const data = JSON.stringify({
      app_id: 2553,
      app_trans_id: attempt.reference,
      amount: 520000,
      zp_trans_id: 240808000012345,
    });
    expect(zalo.verifyNotification({ data, mac: sha256(key2, data), type: 1 })).toEqual({
      reference: attempt.reference,
      amount: '520000',
      status: 'PAID',
      transactionNo: '240808000012345',
    });
    expect(() => zalo.verifyNotification({ data, mac: sha256(key1, data) })).toThrow();
    const otherApp = JSON.stringify({ app_id: 1, app_trans_id: attempt.reference, amount: 1, zp_trans_id: 5 });
    expect(() => zalo.verifyNotification({ data: otherApp, mac: sha256(key2, otherApp) })).toThrow();
  });

  it('signs refunds and refund queries', async () => {
    const refund: WalletRefund = {
      requestId: zalo.refundRequestId(createdAt),
      reference: attempt.reference,
      amount: '100000',
      originalAmount: '520000',
      originalTransactionNo: '240808000012345',
      createdAt,
    };
    http.mockReturnValueOnce(reply({ return_code: 3, refund_id: 2408080001 }));
    await expect(zalo.refund(refund)).resolves.toEqual({
      status: 'PROCESSING',
      transactionNo: '2408080001',
    });
    const f = form();
    expect(f.get('mac')).toBe(
      sha256(key1, ['2553', '240808000012345', '100000', `Hoan tien ${refund.requestId}`, String(createdAt.getTime())].join('|')),
    );
    http.mockReset();
    http.mockReturnValueOnce(reply({ return_code: 1, refund_id: 2408080001 }));
    await expect(zalo.queryRefund(refund)).resolves.toEqual({
      status: 'SUCCEEDED',
      transactionNo: '2408080001',
    });
    const q = form();
    expect(q.get('mac')).toBe(sha256(key1, ['2553', refund.requestId, q.get('timestamp')].join('|')));
  });

  it('accepts only https ZaloPay pages', () => {
    expect(zalopayPaymentUrl('https://qcgateway.zalopay.vn/openinapp?order=1')).toBe(true);
    expect(zalopayPaymentUrl('https://zalopay.vn.evil.example/x')).toBe(false);
    expect(zalopayPaymentUrl('http://qcgateway.zalopay.vn/x')).toBe(false);
  });
});
