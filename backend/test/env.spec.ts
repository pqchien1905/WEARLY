import { validateEnv } from '../src/config/env.validation';
const good = {
  DATABASE_URL: 'postgresql://wearly:x@localhost:5432/wearly',
  JWT_ACCESS_SECRET: 'a'.repeat(40),
  JWT_REFRESH_SECRET: 'b'.repeat(40),
  CORS_ORIGINS: 'http://localhost:5173',
};
describe('configuration', () => {
  it('accepts Gemini authorization keys and rejects unsafe header characters', () => {
    const key = 'AQ.' + 'fixture-key_'.repeat(4);
    expect(validateEnv({ ...good, GEMINI_API_KEY: key }).GEMINI_API_KEY).toBe(key);
    for (const invalid of ['short', key + '\r\nInjected: value', key + ' space']) {
      expect(() => validateEnv({ ...good, GEMINI_API_KEY: invalid })).toThrow();
    }
  });
  it('accepts only explicit loopback origins for local metadata links', () => {
    expect(validateEnv(good)).toHaveProperty(
      'LOCAL_API_ORIGIN',
      'http://127.0.0.1:3000',
    );
    for (const value of [
      'https://evil.example',
      'http://localhost:3000/path',
      'http://localhost:3000/',
      'http://user:password@localhost:3000',
      'http://localhost:3000?q=1',
      'http://localhost:3000/#hash',
    ]) {
      expect(() => validateEnv({ ...good, LOCAL_API_ORIGIN: value })).toThrow();
      expect(() =>
        validateEnv({ ...good, LOCAL_STORE_ORIGIN: value }),
      ).toThrow();
    }
  });
  it('defaults to loopback binding and accepts only supported explicit addresses', () => {
    expect(validateEnv(good)).toHaveProperty('HOST', '127.0.0.1');
    expect(validateEnv({ ...good, HOST: '0.0.0.0' })).toHaveProperty(
      'HOST',
      '0.0.0.0',
    );
    for (const host of [
      'example.test',
      'http://127.0.0.1',
      '127.0.0.1:3000',
      '',
    ]) {
      expect(() => validateEnv({ ...good, HOST: host })).toThrow();
    }
  });
  it('requires loopback non-production SMTP for local transaction mail', () => {
    expect(validateEnv(good)).toHaveProperty('LOCAL_MAIL_ENABLED', 'false');
    const local = {
      ...good,
      LOCAL_MAIL_ENABLED: 'true',
      SMTP_HOST: '127.0.0.1',
      SMTP_PORT: 1025,
      SMTP_FROM: 'store@example.test',
      SMTP_ALLOW_INSECURE_LOCAL: 'true',
    };
    expect(validateEnv(local)).toHaveProperty('LOCAL_MAIL_ENABLED', 'true');
    for (const patch of [
      { NODE_ENV: 'production' },
      { SMTP_HOST: 'smtp.example.test' },
      { SMTP_FROM: '' },
      { SMTP_ALLOW_INSECURE_LOCAL: 'false' },
      { SMTP_USER: 'partial-auth' },
    ]) {
      expect(() => validateEnv({ ...local, ...patch })).toThrow();
    }
  });
  it('allows order/support mail through a complete external SMTP configuration', () => {
    expect(validateEnv(good)).toHaveProperty('MAIL_DELIVERY_ENABLED', 'false');
    const external = {
      ...good,
      MAIL_DELIVERY_ENABLED: 'true',
      SMTP_HOST: 'smtp.example.test',
      SMTP_PORT: 465,
      SMTP_SECURE: 'true',
      SMTP_FROM: 'store@example.test',
      SMTP_USER: 'store@example.test',
      SMTP_PASSWORD: 'app-password',
    };
    expect(validateEnv(external)).toHaveProperty(
      'MAIL_DELIVERY_ENABLED',
      'true',
    );
    for (const patch of [
      { SMTP_HOST: '' },
      { SMTP_FROM: 'not-an-email' },
      { SMTP_PASSWORD: '' },
      { SMTP_ALLOW_INSECURE_LOCAL: 'true' },
    ]) {
      expect(() => validateEnv({ ...external, ...patch })).toThrow();
    }
  });
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
