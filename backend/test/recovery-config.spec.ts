import { validateEnv } from '../src/config/env.validation';

const base = {
  NODE_ENV: 'test',
  DATABASE_URL: 'postgresql://localhost/wearly_test',
  JWT_ACCESS_SECRET: 'access-test-'.repeat(5),
  JWT_REFRESH_SECRET: 'refresh-test-'.repeat(5),
  CORS_ORIGINS: 'http://localhost:4183',
};
const enabled = {
  ...base,
  PASSWORD_RECOVERY_ENABLED: 'true',
  SMTP_HOST: '127.0.0.1',
  SMTP_PORT: '2525',
  SMTP_FROM: 'store@example.test',
  SMTP_ALLOW_INSECURE_LOCAL: 'true',
  PASSWORD_RESET_WEB_URL: 'http://localhost:4183/#/reset-password',
};
describe('Password recovery configuration', () => {
  it('is disabled by default and requires explicit SMTP and trusted URL configuration', () => {
    expect(validateEnv(base).PASSWORD_RECOVERY_ENABLED).toBe('false');
    expect(() =>
      validateEnv({ ...base, PASSWORD_RECOVERY_ENABLED: 'true' }),
    ).toThrow();
    expect(validateEnv(enabled).SMTP_PORT).toBe(2525);
    for (const bad of [
      { SMTP_FROM: 'bad\r\nBcc: other@example.test' },
      { SMTP_HOST: 'smtp.example.test' },
      { SMTP_USER: 'user', SMTP_PASSWORD: '' },
      { PASSWORD_RESET_WEB_URL: 'https://attacker.example/#/reset-password' },
      {
        PASSWORD_RESET_WEB_URL:
          'http://localhost:4183/?token=bad#/reset-password',
      },
    ])
      expect(() => validateEnv({ ...enabled, ...bad })).toThrow();
  });
  it('refuses insecure recovery in production', () => {
    expect(() => validateEnv({ ...enabled, NODE_ENV: 'production' })).toThrow();
    expect(
      validateEnv({
        ...enabled,
        NODE_ENV: 'production',
        SMTP_ALLOW_INSECURE_LOCAL: 'false',
        SMTP_HOST: 'smtp.example.test',
        SMTP_USER: 'store',
        SMTP_PASSWORD: 'configured-in-environment',
        CORS_ORIGINS: 'https://store.example',
        PASSWORD_RESET_WEB_URL: 'https://store.example/#/reset-password',
      }).PASSWORD_RECOVERY_ENABLED,
    ).toBe('true');
  });
});
