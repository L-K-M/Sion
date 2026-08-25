import { describe, expect, it } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { shimParse } from '../../corpus/shim';
import { importMermaid } from '../../../src/shared/mermaid/import';
import { exportMermaid } from '../../../src/shared/mermaid/export';
import { semanticallyEqual } from '../../../src/shared/mermaid/roundTrip';
import { newDoc, newEdge, newNode } from '../../../src/shared/model/create';
import type { ThalyxDoc, ThalyxNode } from '../../../src/shared/model/types';

const corpusDir = join(__dirname, '../../corpus');
const FIXTURES = readdirSync(corpusDir).filter(
  (f) => f.endsWith('.mmd') && !f.startsWith('12-') && !f.startsWith('06-'),
);

async function importText(text: string) {
  return importMermaid(text, shimParse);
}

function toDoc(
  result: Extract<Awaited<ReturnType<typeof importText>>, { kind: 'flowchart' }>,
): ThalyxDoc {
  const doc = newDoc();
  doc.nodes = result.nodes as ThalyxNode[];
  doc.edges = result.edges;
  doc.meta.mermaid = {
    direction: result.meta.direction,
    ...(result.meta.frontmatter ? { frontmatter: result.meta.frontmatter } : {}),
    ...(result.meta.classDefs ? { classDefs: result.meta.classDefs } : {}),
    sourceText: result.meta.sourceText,
  };
  return doc;
}

describe('mermaid export + round-trip (§15.1 export half)', () => {
  it('every corpus fixture: import → export → import → semantic equality + fixpoint', async () => {
    for (const name of FIXTURES) {
      const text = readFileSync(join(corpusDir, name), 'utf8');
      const m1 = await importText(text);
      expect(m1.kind, `${name} imports`).toBe('flowchart');
      if (m1.kind !== 'flowchart') continue;

      const out1 = exportMermaid(toDoc(m1));
      // exported text re-parses
      const m2 = await importText(out1.text);
      expect(m2.kind, `${name}: re-exported text parses`).toBe('flowchart');
      if (m2.kind !== 'flowchart') continue;

      const eq = semanticallyEqual(toDoc(m1), toDoc(m2));
      expect(eq.equal, `${name}: ${eq.diff}`).toBe(true);

      // fixpoint: export(M2) === export(M1) byte-equal
      const out2 = exportMermaid(toDoc(m2));
      expect(out2.text, `${name}: fixpoint`).toBe(out1.text);
    }
  });

  it('byte-stable export across consecutive exports (id stability)', async () => {
    const text = readFileSync(join(corpusDir, '01-basic.mmd'), 'utf8');
    const m = (await importText(text)) as Extract<
      Awaited<ReturnType<typeof importText>>,
      { kind: 'flowchart' }
    >;
    const doc = toDoc(m);
    const a = exportMermaid(doc);
    // apply idAssignments (as ensureMermaidIds does, untracked)
    for (const n of doc.nodes) {
      if (a.idAssignments[n.id]) {
        n.meta ??= {};
        n.meta.mermaid ??= {};
        n.meta.mermaid.id = a.idAssignments[n.id];
      }
    }
    const b = exportMermaid(doc);
    expect(b.text).toBe(a.text);
    expect(b.idAssignments).toEqual({});
  });

  it('emit table coverage: every body appears in an exported corpus doc', async () => {
    const text = readFileSync(join(corpusDir, '02-arrows.mmd'), 'utf8');
    const m = (await importText(text)) as Extract<
      Awaited<ReturnType<typeof importText>>,
      { kind: 'flowchart' }
    >;
    const out = exportMermaid(toDoc(m));
    for (const body of [
      '---',
      '-->',
      '--o',
      '--x',
      '<-->',
      'o--o',
      'x--x',
      '-.-',
      '-.->',
      '-.-o',
      '-.-x',
      '<-.->',
      'o-.-o',
      'x-.-x',
      '===',
      '==>',
      '==o',
      '==x',
      '<==>',
      'o==o',
      'x==x',
    ]) {
      // bidirectional bodies print with the source id first; just check presence
      expect(out.text.includes(body), `body ${body} missing`).toBe(true);
    }
  });

  it('degrade rule: asymmetric heads export as (none, end)', async () => {
    const doc = newDoc();
    doc.nodes.push(newNode({ id: 'a', label: 'A' }), newNode({ id: 'b', label: 'B' }));
    doc.edges.push({
      ...newEdge({ source: 'a', target: 'b' }),
      arrowStart: 'circle', // asymmetric → degrades
      arrowEnd: 'arrow',
    });
    const out = exportMermaid(doc);
    expect(out.text).toContain('A --> B'); // asymmetric start degrades away
  });

  it('hidden edges emit ~~~', () => {
    const doc = newDoc();
    doc.nodes.push(newNode({ id: 'a', label: 'A' }), newNode({ id: 'b', label: 'B' }));
    doc.edges.push({ ...newEdge({ source: 'a', target: 'b' }), hidden: true });
    const out = exportMermaid(doc);
    expect(out.text).toContain('A ~~~ B'); // ids derive from labels
  });

  it('edge-less plain nodes still get standalone lines', () => {
    const doc = newDoc();
    doc.nodes.push(newNode({ id: 'a', label: 'A', shape: 'rect' }));
    const out = exportMermaid(doc);
    expect(out.text).toContain('A["A"]');
  });

  it('containers emit subgraph blocks with direction; nested containers nest', async () => {
    const text = readFileSync(join(corpusDir, '05-subgraphs.mmd'), 'utf8');
    const m = (await importText(text)) as Extract<
      Awaited<ReturnType<typeof importText>>,
      { kind: 'flowchart' }
    >;
    const out = exportMermaid(toDoc(m));
    expect(out.text).toContain('subgraph SG1["Auth"]');
    expect(out.text).toContain('direction LR');
    // Inner nested inside Outer
    const outerIdx = out.text.indexOf('subgraph Outer[');
    const innerIdx = out.text.indexOf('subgraph Inner[');
    const outerEnd = out.text.indexOf('end', outerIdx);
    expect(outerIdx).toBeGreaterThan(-1);
    expect(innerIdx).toBeGreaterThan(outerIdx);
    expect(innerIdx).toBeLessThan(outerEnd);
  });

  it('blocklisted derivations are avoided', () => {
    const doc = newDoc();
    doc.nodes.push(newNode({ id: 'x', label: 'End' })); // would derive 'End' — Capitalized ok, but test 'end' via label 'end'
    doc.nodes.push(newNode({ id: 'y', label: 'end' })); // lowercase → blocklist hit
    doc.nodes.push(newNode({ id: 'z', label: 'Style' }));
    const out = exportMermaid(doc);
    // 'end' must NOT appear as a bare node id at line start
    const lines = out.text.split('\n').map((l) => l.trim());
    expect(
      lines.some((l) =>
        new RegExp(
          '^(end|style|class|classDef|click|subgraph|graph|flowchart|linkStyle)\\s*[\\[(\\@{>-]',
        ).test(l),
      ),
    ).toBe(false);
    // the lowercase-'end' node got a safe derived id instead
    const endNode = out.text
      .split('\n')
      .find((l) => l.includes('end') && !l.startsWith('flowchart'));
    expect(endNode).toBeTruthy();
  });

  it('property: random docs export → import → semantic equality (fixpoint after one pass)', async () => {
    // deterministic pseudo-random generator
    let seed = 42;
    const rand = () => {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      return seed / 2147483648;
    };
    const shapes = ['rect', 'rounded', 'diamond', 'circle', 'cylinder', 'hexagon'] as const;
    const lines3 = ['solid', 'dashed', 'thick'] as const;
    const heads = ['none', 'arrow', 'circle', 'cross'] as const;

    for (let iter = 0; iter < 25; iter++) {
      const doc = newDoc();
      const count = 3 + Math.floor(rand() * 6);
      for (let i = 0; i < count; i++) {
        doc.nodes.push(
          newNode({
            id: `id${i}`,
            label: rand() < 0.3 ? '' : `Node ${i}`,
            shape: shapes[Math.floor(rand() * shapes.length)],
          }),
        );
      }
      for (let i = 0; i < count; i++) {
        for (let j = 0; j < count; j++) {
          if (i === j) continue;
          if (rand() < 0.25) {
            doc.edges.push(
              newEdge({
                source: `id${i}`,
                target: `id${j}`,
                arrowStart: heads[Math.floor(rand() * heads.length)]!,
                arrowEnd: heads[Math.floor(rand() * heads.length)]!,
                style: { line: lines3[Math.floor(rand() * lines3.length)]! },
              }),
            );
          }
        }
      }
      const out1 = exportMermaid(doc);
      const m2 = await importText(out1.text);
      expect(m2.kind, `iter ${iter} parses`).toBe('flowchart');
      if (m2.kind !== 'flowchart') continue;
      // apply idAssignments from pass 1 for the semantic comparison ids
      for (const n of doc.nodes) {
        const mid = out1.idAssignments[n.id];
        if (mid) {
          n.meta ??= {};
          n.meta.mermaid ??= {};
          n.meta.mermaid.id = mid;
        }
      }
      const eq = semanticallyEqual(doc, toDoc(m2));
      expect(eq.equal, `iter ${iter}: ${eq.diff}`).toBe(true);
      // fixpoint
      const out2 = exportMermaid(toDoc(m2));
      expect(out2.text).toBe(out1.text);
    }
  });
});

describe('export edge cases (§9.4)', () => {
  it('empty container titles emit a quoted space (not a parse error)', async () => {
    const doc = newDoc();
    doc.nodes.push(
      newNode({ id: 'g', kind: 'container', label: '', x: 0, y: 0, width: 300, height: 200 }),
    );
    doc.nodes.push(newNode({ id: 'a', label: 'A', parentId: 'g', x: 10, y: 10 }));
    const out = exportMermaid(doc);
    const sgLine = out.text.split('\n').find((l) => l.startsWith('subgraph '))!;
    expect(sgLine).toMatch(/^subgraph \w+[" "]$/);
    const reparsed = await importMermaid(out.text, shimParse);
    expect(reparsed.kind).toBe('flowchart');
  });
});
