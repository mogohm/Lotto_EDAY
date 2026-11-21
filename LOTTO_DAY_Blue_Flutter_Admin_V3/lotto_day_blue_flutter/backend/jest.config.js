/** Two projects: fast pure unit tests, and API e2e tests against a real (embedded) PostgreSQL. */
const tsJest = ['ts-jest', { tsconfig: 'tsconfig.json', diagnostics: { warnOnly: false } }];
module.exports = {
  projects: [
    { displayName: 'unit', testEnvironment: 'node', testMatch: ['<rootDir>/test/unit/**/*.spec.ts'], transform: { '^.+\.ts$': tsJest } },
    {
      displayName: 'e2e', testEnvironment: 'node', testMatch: ['<rootDir>/test/e2e/**/*.e2e-spec.ts'], transform: { '^.+\.ts$': tsJest },
      globalSetup: '<rootDir>/test/e2e/global-setup.mjs', globalTeardown: '<rootDir>/test/e2e/global-teardown.mjs', testTimeout: 60000,
    },
  ],
};
