import { validateEnv } from '../src/config/env.validation';
const good = {
  DATABASE_URL: 'postgresql://wearly:x@localhost:5432/wearly',
  JWT_ACCESS_SECRET: 'a'.repeat(40),
  JWT_REFRESH_SECRET: 'b'.repeat(40),
  CORS_ORIGINS: 'http://localhost:5173',
};
describe('configuration', () => {
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
});
