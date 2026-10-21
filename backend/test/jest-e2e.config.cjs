module.exports = {
  ...require('../jest.config.cjs'),
  rootDir: '..',
  testMatch: ['**/test/**/*.e2e-spec.ts'],
  testTimeout: 30000,
};
