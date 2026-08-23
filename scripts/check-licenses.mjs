#!/usr/bin/env node
/**
 * CI license gate (PLAN.md §4.1).
 *
 * Runs license-checker-rseidelsohn twice over the installed tree:
 *  - production dependencies: any violation FAILS the build (exit 1);
 *  - dev dependencies: violations print a WARNING report only (dev toolchains
 *    drag in odd transitive licenses that never ship).
 *
 * The root package (Thalyx's own Unlicense code) is excluded: it is not a
 * dependency, and the checker reports private roots as UNLICENSED.
 */
import { readFileSync } from 'node:fs';
import { evaluate, scan } from './lib/licenses.mjs';

const root = process.cwd();
const rootName = JSON.parse(readFileSync(`${root}/package.json`, 'utf8')).name;
let failed = false;

function report(label, result, failHard) {
  console.log(
    `[license-gate] ${label}: ${result.ok.length} ok, ${result.violations.length} violations`,
  );
  if (result.violations.length > 0) {
    console.log(
      failHard
        ? '  ✖ PRODUCTION VIOLATIONS (build fails):'
        : '  ⚠ dev-only non-allowlist licenses (warning — never shipped):',
    );
    for (const v of result.violations) {
      const electedNote = v.elected ? ` (elected ${v.effective})` : '';
      console.log(`    ${v.key} → ${v.raw}${electedNote}`);
    }
    if (failHard) failed = true;
  } else if (failHard) {
    console.log('  ✔ all production dependencies are on the allowlist');
  }
}

const notRoot = (e) => e.name !== rootName;

const prod = evaluate(await scan({ start: root, production: true }));
prod.ok = prod.ok.filter(notRoot);
prod.violations = prod.violations.filter(notRoot);
report('production dependencies', prod, true);

const dev = evaluate(await scan({ start: root, development: true }));
dev.ok = dev.ok.filter(notRoot);
dev.violations = dev.violations.filter(notRoot);
report('dev dependencies', dev, false);

if (failed) {
  console.error('\n[license-gate] FAILED: production dependency license violations (PLAN.md §4).');
  process.exit(1);
}
console.log('\n[license-gate] OK');
