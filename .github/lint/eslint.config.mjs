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
  // Google 4.1.1: braces for every control statement, except a simple
  // statement that fits on the same line as an if with no else.
  'curly': ['error', 'multi-line'],
  // Google 5.1.1 and 5.4.1: one variable per declaration, no Array().
  'one-var': ['error', 'never'],
  'no-array-constructor': 'error',
  // No code built from strings, no changes to built-in prototypes.
  'no-eval': 'error',
  'no-implied-eval': 'error',
  'no-new-func': 'error',
  'no-extend-native': 'error',
  'no-promise-executor-return': 'error',
  'radix': 'error',
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
