/**
 * Perf fixture generator (PLAN.md §11.7): 500/1000/2000-node docs — mixed
 * shapes, 1.5× edges, 10% containers.
 *
 * Pure TS: used by the Playwright perf spec (which drives the real renderer)
 * and available for manual testing via ?fixture=perf-N.
 */
import { newDoc, newEdge, newNode, newId } from '../../src/shared/model/create';
import { serializeDoc } from '../../src/shared/files/thalyxFile';
import type { ShapeKind, ThalyxDoc } from '../../src/shared/model/types';

const SHAPE_MIX: ShapeKind[] = [
  'rect',
  'rounded',
  'ellipse',
  'diamond',
  'cylinder',
  'stadium',
  'hexagon',
  'parallelogram',
];

export function generateDoc(nodeCount: number): ThalyxDoc {
  const doc = newDoc();
  const containerCount = Math.max(1, Math.round(nodeCount * 0.1));
  const containers: string[] = [];

  const COLS = Math.ceil(Math.sqrt(nodeCount));
  for (let i = 0; i < nodeCount; i++) {
    const inContainer = i >= containerCount && (i - containerCount) % 10 === 0;
    void inContainer;
    const cx = (i % COLS) * 200;
    const cy = Math.floor(i / COLS) * 140;
    if (i < containerCount) {
      // spread container frames over the grid, sized to hold 8 nodes each
      const id = newId();
      containers.push(id);
      doc.nodes.push(
        newNode({
          id,
          kind: 'container',
          x: cx,
          y: cy,
          width: 8 * 200 + 40,
          height: 2 * 140 + 60,
          label: `Group ${i}`,
        }),
      );
      continue;
    }
    const parentIdx = containers.length > 0 ? (i - containerCount) % containers.length : -1;
    const parent = parentIdx >= 0 && Math.random() < 0.5 ? containers[parentIdx] : undefined;
    // position relative to parent when contained (rough containment)
    const px = parent ? cx - parentIdx * 200 : cx;
    const py = parent ? cy - Math.floor(parentIdx) * 70 : cy;
    doc.nodes.push(
      newNode({
        kind: 'shape',
        shape: SHAPE_MIX[i % SHAPE_MIX.length]!,
        x: px,
        y: py,
        width: 140,
        height: 64,
        label: `Node ${i}`,
        parentId: parent,
      }),
    );
  }

  // 1.5× edges: chain + random extra links (skip container endpoints mostly)
  const shapeIds = doc.nodes.filter((n) => n.kind === 'shape').map((n) => n.id);
  const edgeTarget = Math.round(nodeCount * 1.5);
  for (let i = 0; i < edgeTarget; i++) {
    if (i < shapeIds.length - 1) {
      doc.edges.push(newEdge({ source: shapeIds[i]!, target: shapeIds[i + 1]! }));
    } else {
      const a = shapeIds[Math.floor(Math.random() * shapeIds.length)]!;
      const b = shapeIds[Math.floor(Math.random() * shapeIds.length)]!;
      if (a !== b) doc.edges.push(newEdge({ source: a, target: b }));
    }
  }
  return doc;
}

export function serializeGeneratedDoc(nodeCount: number): string {
  return serializeDoc(generateDoc(nodeCount));
}
