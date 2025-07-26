import type { Config } from 'jest';

const config: Config = {
  watch: false,
  preset: 'ts-jest/presets/js-with-ts',
  testEnvironment: 'node',
  globalSetup: '<rootDir>/global-setup.ts',
  globalTeardown: '<rootDir>/global-teardown.ts',
  workerThreads: true,
  testTimeout: 60_000, // Increased timeout for RQQ retry logic testing
  transformIgnorePatterns: [
    '/node_modules/(?!@dfinity/agent|@dfinity/certificate-verification)'
  ]
};

export default config; 