// @ts-check
import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import reactHooks from 'eslint-plugin-react-hooks';
import reactRefresh from 'eslint-plugin-react-refresh';

export default tseslint.config(
  {
    ignores: [
      'out/**',
      'release/**',
      'dist/**',
      'node_modules/**',
      'docs/**',
      'playwright-report/**',
      'test-results/**',
      'THIRD_PARTY_LICENSES.md',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'module',
    },
  },
  {
    // Plain-JS node scripts (license gate / ledger generator).
    files: ['scripts/**/*.mjs'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'module',
      globals: {
        console: 'readonly',
        process: 'readonly',
      },
    },
  },
  {
    files: ['src/renderer/**/*.{ts,tsx}'],
    plugins: {
      'react-hooks': reactHooks,
      'react-refresh': reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      'react-refresh/only-export-components': 'warn',
    },
  },
  {
    // PLAN.md §19.5: src/shared is pure TS — no React, no Electron, no
    // renderer-only libraries. Enforced from M0.
    files: ['src/shared/**/*.ts'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          paths: [
            { name: 'react', message: 'src/shared must stay renderer-agnostic (PLAN.md §6).' },
            { name: 'react-dom', message: 'src/shared must stay renderer-agnostic (PLAN.md §6).' },
            { name: 'electron', message: 'src/shared must stay Electron-free (PLAN.md §6).' },
            { name: 'mermaid', message: 'mermaid runs only in the renderer/tests (PLAN.md §9).' },
            {
              name: '@xyflow/react',
              message: 'Nothing may import React Flow types into src/shared (PLAN.md §11.7).',
            },
          ],
          patterns: [
            {
              group: ['react/*', 'react-dom/*'],
              message: 'src/shared must stay renderer-agnostic (PLAN.md §6).',
            },
            {
              group: ['electron/*', 'electron/**'],
              message: 'src/shared must stay Electron-free (PLAN.md §6).',
            },
            {
              group: ['@xyflow/*'],
              message: 'Nothing may import React Flow types into src/shared (PLAN.md §11.7).',
            },
          ],
        },
      ],
    },
  },
);
