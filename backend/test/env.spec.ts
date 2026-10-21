import { validateEnv } from '../src/config/env.validation';
const good = {
  DATABASE_URL: 'postgresql://wearly:x@localhost:5432/wearly',
  JWT_ACCESS_SECRET: 'a'.repeat(40),
  JWT_REFRESH_SECRET: 'b'.repeat(40),
  CORS_ORIGINS: 'http://localhost:5173',
};
describe('configuration', () => {
  it('requires explicit complete sandbox configuration and an allowed storefront return', () => {
    expect(validateEnv(good)).toHaveProperty('VNPAY_ENABLED', 'false');
    expect(() => validateEnv({ ...good, VNPAY_ENABLED: 'true' })).toThrow();
    const gateway = {
      ...good,
      VNPAY_ENABLED: 'true',
      VNPAY_TMN_CODE: 'TEST0001',
      VNPAY_HASH_SECRET: 'sandbox-test-secret',
      VNPAY_RETURN_URL: 'http://localhost:3000/api/v1/payments/vnpay/return',
      VNPAY_WEB_RETURN_URL: 'http://localhost:5173/#/payments/return',
    };
    expect(validateEnv(gateway)).toHaveProperty('VNPAY_ENABLED', 'true');
    for (const patch of [
      { VNPAY_TMN_CODE: 'x' },
      { VNPAY_HASH_SECRET: '' },
      { VNPAY_RETURN_URL: 'http://external.test/callback' },
      { VNPAY_WEB_RETURN_URL: 'https://external.test/#/payments/return' },
      { VNPAY_WEB_RETURN_URL: 'http://localhost:5173/#/shop' },
    ]) {
      expect(() => validateEnv({ ...gateway, ...patch })).toThrow();
    }
  });
  it('requires secrets and rejects copied placeholders', () => {
    expect(() => validateEnv({})).toThrow();
    expect(() =>
      validateEnv({
        ...good,
        JWT_ACCESS_SECRET: 'replace-with-at-least-32-random-characters',
      }),
    ).toThrow();
    expect(() =>
      validateEnv({ ...good, JWT_REFRESH_SECRET: good.JWT_ACCESS_SECRET }),
    ).toThrow();
  });
  it('parses bounded ports and token durations', () => {
    expect(validateEnv(good).PORT).toBe(3000);
    expect(() => validateEnv({ ...good, PORT: '99999' })).toThrow();
    expect(() =>
      validateEnv({ ...good, JWT_ACCESS_EXPIRES_IN: '-1' }),
    ).toThrow();
  });
  it('validates an explicit queue namespace for isolated integration tests', () => {
    expect(validateEnv(good)).toHaveProperty('AI_QUEUE_PREFIX', 'wearly');
    expect(
      validateEnv({ ...good, AI_QUEUE_PREFIX: 'wearly-test-123' }),
    ).toHaveProperty('AI_QUEUE_PREFIX', 'wearly-test-123');
    expect(() => validateEnv({ ...good, AI_QUEUE_PREFIX: '' })).toThrow();
    expect(() =>
      validateEnv({ ...good, AI_QUEUE_PREFIX: 'contains:separator' }),
    ).toThrow();
  });
});
