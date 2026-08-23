import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * Convention test (M1 acceptance): mutation-through-actions is the only way to
 * change the doc — `setStore(`/`useStore.setState(` may appear ONLY in
 * store.ts (definition) and actions.ts (all mutations). history.ts is pure.
 */

const rendererRoot = join(__dirname, '../../../src/renderer');
const sharedRoot = join(__dirname, '../../../src/shared');

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (/\.(ts|tsx)$/.test(entry)) out.push(p);
  }
  return out;
}

const ALLOWED = new Set(
  ['store.ts', 'actions.ts'].map((f) => join(__dirname, '../../../src/renderer/store', f)),
);

describe('store mutation convention (§8.3)', () => {
  it('setStore/useStore.setState appear only in store.ts and actions.ts', () => {
    const offenders: string[] = [];
    for (const file of walk(rendererRoot)) {
      if (ALLOWED.has(file)) continue;
      const src = readFileSync(file, 'utf8');
      if (/setStore\s*\(|useStore\.setState\s*\(|\.setState\s*\(/.test(src)) {
        offenders.push(file);
      }
    }
    expect(offenders).toEqual([]);
  });

  it('shared code never imports the renderer (renderer-free, §6)', () => {
    const offenders: string[] = [];
    const importsRenderer =
      /(?:from\s*|import\s*\(\s*|require\s*\(\s*)['"](?:\.\.\/)*\.?\/?renderer\//;
    const importsRendererAbsolute =
      /(?:from\s*|import\s*\(\s*|require\s*\(\s*)['"](?:src\/)?renderer\//;
    for (const file of walk(sharedRoot)) {
      const src = readFileSync(file, 'utf8');
      if (importsRenderer.test(src) || importsRendererAbsolute.test(src)) offenders.push(file);
    }
    expect(offenders).toEqual([]);
  });
});
