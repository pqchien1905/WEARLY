import { validateEnv } from '../src/config/env.validation';

const base = {
  NODE_ENV: 'test',
  DATABASE_URL: 'postgresql://localhost/wearly_test',
  JWT_ACCESS_SECRET: 'access-test-'.repeat(5),
  JWT_REFRESH_SECRET: 'refresh-test-'.repeat(5),
  CORS_ORIGINS: 'http://localhost:8080',
};
const momo = {
  ...base,
  PAYMENT_WEB_RETURN_URL: 'http://localhost:8080/#/payments/return',
  MOMO_ENABLED: 'true',
  MOMO_PARTNER_CODE: 'MOMO',
  MOMO_ACCESS_KEY: 'F8BBA842ECF85',
  MOMO_SECRET_KEY: 'momo-fixture-secret-not-a-key',
  MOMO_RETURN_URL: 'http://localhost:3000/api/v1/payments/momo/return',
  MOMO_IPN_URL: 'http://localhost:3000/api/v1/payments/momo/ipn',
};
const zalopay = {
  ...base,
  PAYMENT_WEB_RETURN_URL: 'http://localhost:8080/#/payments/return',
  ZALOPAY_ENABLED: 'true',
  ZALOPAY_APP_ID: '2553',
  ZALOPAY_KEY1: 'zalopay-fixture-key1-not-a-key',
  ZALOPAY_KEY2: 'zalopay-fixture-key2-not-a-key',
  ZALOPAY_RETURN_URL: 'http://localhost:3000/api/v1/payments/zalopay/return',
  ZALOPAY_CALLBACK_URL: 'http://localhost:3000/api/v1/payments/zalopay/callback',
};
describe('E-wallet sandbox configuration', () => {
  it('is disabled by default and accepts complete local configurations', () => {
    expect(validateEnv(base)).toMatchObject({ MOMO_ENABLED: 'false', ZALOPAY_ENABLED: 'false' });
    expect(validateEnv(momo).MOMO_ENABLED).toBe('true');
    expect(validateEnv(zalopay).ZALOPAY_ENABLED).toBe('true');
  });
  it('refuses incomplete or untrusted MoMo settings', () => {
    for (const bad of [
      { MOMO_SECRET_KEY: 'short' },
      { MOMO_PARTNER_CODE: 'bad code' },
      { MOMO_RETURN_URL: 'http://localhost:3000/api/v1/payments/vnpay/return' },
      { MOMO_IPN_URL: 'http://wallet.example/api/v1/payments/momo/ipn' },
      { PAYMENT_WEB_RETURN_URL: 'https://attacker.example/#/payments/return' },
      { PAYMENT_WEB_RETURN_URL: 'http://localhost:8080/#/account' },
      { PAYMENT_WEB_RETURN_URL: '' },
    ])
      expect(() => validateEnv({ ...momo, ...bad })).toThrow();
  });
  it('refuses incomplete ZaloPay settings and plain HTTP outside localhost', () => {
    for (const bad of [
      { ZALOPAY_APP_ID: 'abc' },
      { ZALOPAY_KEY2: '' },
      { ZALOPAY_CALLBACK_URL: 'http://shop.example/api/v1/payments/zalopay/callback' },
      { ZALOPAY_RETURN_URL: 'https://u:p@shop.example/api/v1/payments/zalopay/return' },
    ])
      expect(() => validateEnv({ ...zalopay, ...bad })).toThrow();
    expect(
      validateEnv({
        ...zalopay,
        ZALOPAY_CALLBACK_URL: 'https://shop.example/api/v1/payments/zalopay/callback',
      }).ZALOPAY_ENABLED,
    ).toBe('true');
  });
});
