/**
 * Shared license-gate logic (PLAN.md §4). Used by check-licenses.mjs (CI gate)
 * and gen-third-party-licenses.mjs (ledger generator).
 */
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const checker = require('license-checker-rseidelsohn');

/** Package name → license arm Thalyx elects (dompurify: Apache-2.0 per D17). */
export const ELECTIONS = {
  dompurify: 'Apache-2.0',
};

export const ALLOWED = new Set([
  'MIT',
  'Apache-2.0',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'ISC',
  '0BSD',
  'Unlicense',
  'CC0-1.0',
  'BlueOak-1.0.0',
  // Python-2.0 (PSF) allowed for argparse (electron-updater → js-yaml
  // transitive): BSD-class permissive — noted in CHANGELOG per §19.3.
  'Python-2.0',
  // Zlib allowed for pako (jspdf transitive): BSD-class permissive,
  // same category as the listed licenses — noted in CHANGELOG per §19.3.
  'Zlib',
]);

/**
 * Evaluate a license expression against the allowlist.
 * Handles `A`, `A OR B`, `A AND B`, parenthesized variants, and `*` globs
 * (e.g. `BSD-3-Clause*`). Returns true if permitted.
 */
export function isAllowedExpression(expr) {
  const stripped = String(expr).replace(/[()]/g, ' ').trim();
  if (!stripped || /^(UNKNOWN|UNLICENSED|SEE LICENSE IN .*)$/i.test(stripped)) return false;

  // Mixed AND/OR after paren flattening (e.g. "MIT OR CC0 AND X") — precedence
  // is ambiguous, so fail closed and require a human/election instead of
  // guessing permissively.
  if (stripped.includes(' OR ') && stripped.includes(' AND ')) return false;

  for (const orPart of stripped.split(' OR ')) {
    const andParts = orPart.split(' AND ').map((s) => s.trim());
    if (andParts.every((p) => ALLOWED.has(p.replace(/\*$/, '').trim()))) return true;
  }
  return false;
}

/**
 * Flatten checker output into sorted `{key, name, raw, effective, elected}` entries.
 */
export function flatten(packages) {
  return Object.entries(packages)
    .map(([key, info]) => {
      const name = key.replace(/@[^@]+$/, '');
      let licenses = info.licenses;
      if (Array.isArray(licenses)) licenses = licenses.join(' OR ');
      const raw = String(licenses ?? 'UNKNOWN');
      return { key, name, raw, effective: ELECTIONS[name] ?? raw, elected: name in ELECTIONS };
    })
    .sort((a, b) => a.key.localeCompare(b.key));
}

export function evaluate(packages) {
  const all = flatten(packages);
  return {
    ok: all.filter((e) => isAllowedExpression(e.effective)),
    violations: all.filter((e) => !isAllowedExpression(e.effective)),
  };
}

export function scan(opts) {
  return new Promise((resolve, reject) => {
    checker.init(opts, (err, packages) => (err ? reject(err) : resolve(packages ?? {})));
  });
}
