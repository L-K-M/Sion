#!/usr/bin/env node
/**
 * CI license gate (PLAN.md §4.1).
 *
 * Runs license-checker-rseidelsohn twice over the installed tree:
 *  - production dependencies: any violation FAILS the build (exit 1);
 *  - dev dependencies: violations print a WARNING report only (dev toolchains
 *    drag in odd transitive licenses that never ship).
 */
import { evaluate, scan } from './lib/licenses.mjs';

const root = process.cwd();
let failed = false;

const prod = evaluate(await scan({ start: root, production: true }));
console.log(
  `[license-gate] production dependencies: ${prod.ok.length} ok, ${prod.violations.length} violations`,
);
if (prod.violations.length > 0) {
  console.log('  ✖ PRODUCTION VIOLATIONS (build fails):');
  for (const v of prod.violations) {
    const electedNote = v.elected ? ` (elected ${v.effective})` : '';
    console.log(`    ${v.key} → ${v.raw}${electedNote}`);
  }
  failed = true;
} else {
  console.log('  ✔ all production dependencies are on the allowlist');
}

const dev = evaluate(await scan({ start: root, development: true }));
console.log(
  `[license-gate] dev dependencies: ${dev.ok.length} ok, ${dev.violations.length} non-allowlist`,
);
if (dev.violations.length > 0) {
  console.log('  ⚠ dev-only non-allowlist licenses (warning — never shipped):');
  for (const v of dev.violations) {
    const electedNote = v.elected ? ` (elected ${v.effective})` : '';
    console.log(`    ${v.key} → ${v.raw}${electedNote}`);
  }
}

if (failed) {
  console.error('\n[license-gate] FAILED: production dependency license violations (PLAN.md §4).');
  process.exit(1);
}
console.log('\n[license-gate] OK');
