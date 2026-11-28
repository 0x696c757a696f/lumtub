// ESLint for the repository's own JavaScript, after Google's JavaScript
// style guide (docs/CODE-STYLE.md). Run from the repository root:
// .github/lint/node_modules/.bin/eslint -c .github/lint/eslint.config.mjs
import js from '@eslint/js';

const workerGlobals = Object.fromEntries(
  [
    'atob', 'btoa', 'console', 'crypto', 'fetch', 'caches', 'Request', 'Response', 'Headers',
    'URL', 'URLSearchParams', 'TextEncoder', 'TextDecoder', 'AbortController', 'AbortSignal',
    'setTimeout', 'clearTimeout', 'structuredClone', 'FormData', 'Blob', 'ReadableStream',
  ].map((name) => [name, 'readonly']),
);

const nodeGlobals = Object.fromEntries(
  ['require', 'module', 'process', 'console', '__dirname'].map((name) => [name, 'readonly']),
);

const rules = {
  ...js.configs.recommended.rules,
  // Google: const by default, let when reassigned, never var.
  'no-var': 'error',
  'prefer-const': 'error',
  'eqeqeq': ['error', 'always', {null: 'ignore'}],
  'curly': ['error', 'multi-line'],
  'no-throw-literal': 'error',
  'prefer-rest-params': 'error',
  'prefer-spread': 'error',
  'no-new-wrappers': 'error',
  'new-cap': 'error',
  'camelcase': ['error', {properties: 'never'}],
};

export default [
  {
    files: ['license-server/**/*.js'],
    languageOptions: {sourceType: 'module', globals: workerGlobals},
    rules,
  },
  {
    files: ['docs/cards/**/*.js'],
    languageOptions: {
      sourceType: 'commonjs',
      globals: {...nodeGlobals, document: 'readonly'},
    },
    rules,
  },
];
