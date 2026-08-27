#!/usr/bin/env node
/**
 * Generates THIRD_PARTY_LICENSES.md (PLAN.md §4.2).
 *
 * - "Bundled" section: production dependencies (these ship inside the app).
 * - "Dev toolchain" section: dev dependencies grouped by license (none ship).
 * - "Bundled assets" section: fonts/colors/etc. that are not npm packages.
 *
 * Re-run via `npm run gen:licenses` whenever dependencies change.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { flatten, scan } from './lib/licenses.mjs';

const MODE = Object.freeze({ check: 'check', write: 'write' });
const EXIT_FAILURE = 1;
const root = process.cwd();
const rootName = JSON.parse(readFileSync(`${root}/package.json`, 'utf8')).name;

function parseMode(args) {
  if (args.length === 0) return MODE.write;
  if (args.length === 1 && args[0] === '--check') return MODE.check;

  console.error('Usage: node scripts/gen-third-party-licenses.mjs [--check]');
  process.exit(EXIT_FAILURE);
}

// Platform/arch-specific optional deps (esbuild/rollup binaries, napi modules)
// differ per OS — exclude them so the ledger (and the CI staleness diff) is
// deterministic across macOS/Linux contributors.
const PLATFORM_BINARY =
  /^(@esbuild\/|@rollup\/rollup-|@napi-rs\/|@parcel\/watcher-|@swc\/core-|lightningcss-)/;

const prod = flatten(await scan({ start: root, production: true })).filter(
  (p) => p.name !== rootName && !PLATFORM_BINARY.test(p.name),
);
const dev = flatten(await scan({ start: root, development: true })).filter(
  (p) => p.name !== rootName && !PLATFORM_BINARY.test(p.name),
);

const devByLicense = new Map();
for (const d of dev) {
  const license = d.effective;
  if (!devByLicense.has(license)) devByLicense.set(license, []);
  devByLicense.get(license).push(d.name);
}

const lines = [];
lines.push('# Third-party licenses');
lines.push('');
lines.push('Thalyx is dedicated to the public domain ([Unlicense](LICENSE)).');
lines.push('');
lines.push('This file is **generated** by `npm run gen:licenses` — do not edit by hand.');
lines.push('');
lines.push('## Bundled runtime dependencies');
lines.push('');
lines.push('These packages are compiled into the shipped application. License texts are');
lines.push("available in each package's directory inside `node_modules/`.");
lines.push('');
lines.push('| Package | License(s) |');
lines.push('|---|---|');
for (const p of prod) {
  lines.push(`| ${p.key} | ${p.effective}${p.elected ? ' (elected)' : ''} |`);
}
lines.push('');
lines.push('## Bundled assets');
lines.push('');
lines.push('| Asset | License | Notes |');
lines.push('|---|---|---|');
lines.push(
  '| [Open Color](https://github.com/yeun/open-color) color values | MIT | Palette token values derive from Open Color (PLAN.md §10.4); values, not code. |',
);
lines.push(
  '| Inter font (files land with the M2 theme) | SIL OFL-1.1 | Bundled as an app asset (D19). |',
);
lines.push('');
lines.push('## Dev toolchain (not shipped)');
lines.push('');
lines.push('Build/test dependencies, grouped by license. They never ship in any installer.');
lines.push('');
for (const [license, names] of [...devByLicense.entries()].sort((a, b) =>
  a[0].localeCompare(b[0]),
)) {
  const unique = [...new Set(names)].sort((a, b) => a.localeCompare(b));
  lines.push(`- **${license}** (${unique.length}): ${unique.join(', ')}`);
}
lines.push('');

const outputPath = join(root, 'THIRD_PARTY_LICENSES.md');
const generated = lines.join('\n');
const mode = parseMode(process.argv.slice(2));

if (mode === MODE.check) {
  let current = '';
  try {
    current = readFileSync(outputPath, 'utf8');
  } catch {
    // A missing ledger is stale by definition.
  }

  if (current !== generated) {
    console.error('THIRD_PARTY_LICENSES.md is stale; run npm run gen:licenses.');
    process.exit(EXIT_FAILURE);
  }

  console.log(
    `THIRD_PARTY_LICENSES.md is current: ${prod.length} bundled, ${dev.length} dev entries.`,
  );
} else {
  writeFileSync(outputPath, generated);
  console.log(
    `THIRD_PARTY_LICENSES.md written: ${prod.length} bundled, ${dev.length} dev entries.`,
  );
}
