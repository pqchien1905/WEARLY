module.exports = {
  ...require('../jest.config.cjs'),
  rootDir: '..',
  testMatch: ['**/test/**/*.e2e-spec.ts'],
  setupFiles: ['<rootDir>/test/setup-e2e-env.cjs'],
  testTimeout: 30000,
};
