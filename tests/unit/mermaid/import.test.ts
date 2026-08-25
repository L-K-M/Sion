import { describe, expect, it } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { shimParse } from '../../corpus/shim';
import { importMermaid } from '../../../src/shared/mermaid/import';
import type { FlowchartImport } from '../../../src/shared/mermaid/import';

const corpusDir = join(__dirname, '../../corpus');

const FLOWCHART_FIXTURES = readdirSync(corpusDir).filter(
  (f) => f.endsWith('.mmd') && !f.startsWith('12-'),
);

async function importFixture(name: string): Promise<Awaited<ReturnType<typeof importMermaid>>> {
  const text = readFileSync(join(corpusDir, name), 'utf8');
  return importMermaid(text, shimParse);
}

describe('mermaid import corpus (§15.1 import half)', () => {
  it('every flowchart fixture imports as a flowchart with sane models', async () => {
    for (const name of FLOWCHART_FIXTURES) {
      const result = await importFixture(name);
      expect(result.kind, `${name} must be a flowchart import`).toBe('flowchart');
      const fc = result as FlowchartImport;
      expect(fc.nodes.length, `${name} nodes`).toBeGreaterThan(0);
      // invariants: containers before children; edges resolve; ids unique
      const idx = new Map(fc.nodes.map((n, i) => [n.id, i]));
      for (const n of fc.nodes) {
        if (n.parentId !== undefined) {
          expect(idx.get(n.parentId)!, `${name}: parent before child`).toBeLessThan(idx.get(n.id)!);
        }
      }
      for (const e of fc.edges) {
        expect(idx.has(e.source), `${name} edge source`).toBe(true);
        expect(idx.has(e.target), `${name} edge target`).toBe(true);
      }
      expect(new Set(fc.nodes.map((n) => n.id)).size).toBe(fc.nodes.length);
    }
  });

  it('01-basic: shapes, labels, directions, edge heads', async () => {
    const r = (await importFixture('01-basic.mmd')) as FlowchartImport;
    expect(r.meta.direction).toBe('TB');
    const byLabel = new Map(r.nodes.map((n) => [n.label, n]));
    expect(byLabel.get('Start')?.shape).toBe('rect');
    expect(byLabel.get('Valid?')?.shape).toBe('diamond');
    expect(byLabel.get('Dashboard')?.shape).toBe('rect');
    const yes = r.edges.find((e) => e.label === 'yes')!;
    expect(yes.arrowEnd).toBe('arrow');
    expect(yes.arrowStart).toBe('none');
    expect(r.edges).toHaveLength(3);
  });

  it('02-arrows: every emit-table arrow variant imports', async () => {
    const r = (await importFixture('02-arrows.mmd')) as FlowchartImport;
    expect(r.edges.length).toBeGreaterThanOrEqual(23);
    const heads = new Set(r.edges.map((e) => `${e.arrowStart}>${e.arrowEnd}|${e.style.line}`));
    // spot-check the composed dotted-circle
    expect(heads.has('none>circle|dashed')).toBe(true);
    expect(heads.has('arrow>arrow|thick')).toBe(true);
    expect(heads.has('none>none|solid')).toBe(true);
    expect(heads.has('cross>cross|dashed')).toBe(true);
    // minlen edge (J ---> K) carried meta
    const jk = r.edges.find((e) => e.source === 'J' && e.target === 'K')!;
    expect(jk.meta?.mermaid?.minlen).toBe(2);
  });

  it('03-shapes: every bracket maps to its ShapeKind', async () => {
    const r = (await importFixture('03-shapes.mmd')) as FlowchartImport;
    const byLabel = new Map(r.nodes.map((n) => [n.label, n]));
    expect(byLabel.get('square')?.shape).toBe('rect');
    expect(byLabel.get('round')?.shape).toBe('rounded');
    expect(byLabel.get('stadium')?.shape).toBe('stadium');
    expect(byLabel.get('circle')?.shape).toBe('circle');
    expect(byLabel.get('doublecircle')?.shape).toBe('doublecircle');
    expect(byLabel.get('ellipse')?.shape).toBe('ellipse');
    expect(byLabel.get('diamond')?.shape).toBe('diamond');
    expect(byLabel.get('hexagon')?.shape).toBe('hexagon');
    expect(byLabel.get('cylinder')?.shape).toBe('cylinder');
    expect(byLabel.get('subroutine')?.shape).toBe('subroutine');
    expect(byLabel.get('parallelogram')?.shape).toBe('parallelogram');
    expect(byLabel.get('lean-left')?.shape).toBe('parallelogram-alt');
    expect(byLabel.get('trapezoid')?.shape).toBe('trapezoid');
    expect(byLabel.get('inv-trapezoid')?.shape).toBe('trapezoid-alt');
    expect(byLabel.get('odd')?.shape).toBe('asymmetric');
    // bare node A
    const bare = r.nodes.find((n) => n.meta?.mermaid?.id === 'A')!;
    expect(bare.shape).toBe('rect');
  });

  it('04-labels: entities, <br>, unicode round through decode', async () => {
    const r = (await importFixture('04-labels.mmd')) as FlowchartImport;
    const labels = r.nodes.map((n) => n.label);
    expect(labels).toContain('say "hi"');
    expect(labels).toContain('AT&T');
    expect(labels).toContain('5 < 6'); // db decodes '&lt;' itself; the plan's #38;lt; flow is the export side
    expect(labels).toContain('multi\nline');
    expect(labels.some((l) => l.includes('🎉'))).toBe(true);
    expect(labels.some((l) => l.includes('back`tick`'))).toBe(true);
  });

  it('05-subgraphs: nested containers with dir, parent-first order', async () => {
    const r = (await importFixture('05-subgraphs.mmd')) as FlowchartImport;
    const containers = r.nodes.filter((n) => n.kind === 'container');
    expect(containers.map((c) => c.meta?.mermaid?.id).sort()).toEqual(['Inner', 'Outer', 'SG1']);
    const sg1 = containers.find((c) => c.meta?.mermaid?.id === 'SG1')!;
    expect(sg1.meta?.mermaid?.dir).toBe('LR');
    const login = r.nodes.find((n) => n.label === 'Login')!;
    expect(login.parentId).toBe(sg1.id);
    const deep = r.nodes.find((n) => n.label === 'Deep')!;
    const inner = containers.find((c) => c.meta?.mermaid?.id === 'Inner')!;
    expect(deep.parentId).toBe(inner.id);
    expect(inner.parentId).toBe(containers.find((c) => c.meta?.mermaid?.id === 'Outer')!.id);
  });

  it('06-styles: classDef + style strings map into NodeStyle + meta', async () => {
    const r = (await importFixture('06-styles.mmd')) as FlowchartImport;
    const styled = r.nodes.find((n) => n.label === 'Styled')!;
    expect(styled.style.fill).toBe('#d0ebff');
    expect(styled.style.stroke).toBe('#1971c2');
    expect(styled.style.strokeWidth).toBe(4);
    expect(styled.meta?.mermaid?.classes).toContain('blue');
    const plain = r.nodes.find((n) => n.label === 'Plain')!;
    expect(plain.style.fill).toBe('#ffe3e3');
    expect(r.meta.classDefs?.['blue']).toBeDefined();
    const withLink = r.nodes.find((n) => n.meta?.mermaid?.link !== undefined);
    // mermaid normalizes the URL (adds the trailing slash)
    expect(withLink?.meta?.mermaid?.tooltip).toBe('tooltip text');
  });

  it('07-hidden: ~~~ edges import as hidden', async () => {
    const r = (await importFixture('07-hidden.mmd')) as FlowchartImport;
    expect(r.edges.filter((e) => e.hidden)).toHaveLength(1);
    expect(r.edges.filter((e) => !e.hidden)).toHaveLength(1);
  });

  it('08-edgeids: user edge ids persist in meta; synthetic ones do not', async () => {
    const r = (await importFixture('08-edgeids.mmd')) as FlowchartImport;
    const ids = r.edges.map((e) => e.meta?.mermaid?.id).filter(Boolean);
    expect(ids).toEqual(['e1', 'e2']);
  });

  it('09-altshapes: @{shape: cyl} keeps the raw name in meta', async () => {
    const r = (await importFixture('09-altshapes.mmd')) as FlowchartImport;
    const db = r.nodes.find((n) => n.label === 'db')!;
    expect(db.shape).toBe('cylinder');
    const choice = r.nodes.find((n) => n.label === 'choice')!;
    expect(choice.shape).toBe('diamond');
  });

  it('10-frontmatter: block preserved verbatim in meta', async () => {
    const r = (await importFixture('10-frontmatter.mmd')) as FlowchartImport;
    expect(r.meta.frontmatter).toBe('---\ntitle: My diagram\n---\n');
    expect(r.meta.direction).toBe('LR');
  });

  it('11-minlen: length>1 carried as meta.mermaid.minlen', async () => {
    const r = (await importFixture('11-minlen.mmd')) as FlowchartImport;
    const minlens = r.edges.map((e) => e.meta?.mermaid?.minlen).filter((m) => m !== undefined);
    expect(minlens.length).toBe(6);
    expect(minlens.every((m) => m! > 1)).toBe(true);
  });

  it('12-sequence: non-flowchart imports as an island', async () => {
    const r = await importFixture('12-sequence.mmd');
    expect(r.kind).toBe('island');
    if (r.kind === 'island') {
      expect(r.diagramType).toBe('sequence');
      expect(r.source).toContain('Alice');
    }
  });

  it('garbage: parse errors surface message + position', async () => {
    const r = await importMermaid('flowchart TB\n  A --x', shimParse);
    expect(r.kind).toBe('error');
    if (r.kind === 'error') {
      expect(r.error.message.length).toBeGreaterThan(0);
      expect(r.error.line).toBeGreaterThan(0);
    }
  });

  it('mermaid upgrade gate: pin is exactly 11.17.0 (D16)', async () => {
    const pkg = JSON.parse(readFileSync(join(process.cwd(), 'package.json'), 'utf8'));
    expect(pkg.dependencies.mermaid).toBe('11.17.0');
    const mermaidPkg = JSON.parse(
      readFileSync(join(process.cwd(), 'node_modules/mermaid/package.json'), 'utf8'),
    );
    expect(mermaidPkg.version).toMatch(/^11\.17\./);
  });
});
