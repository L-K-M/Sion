import { describe, expect, it } from 'vitest';
import { renderDocToSvg } from '../../../src/shared/export/svg';
import { newDoc, newEdge, newNode } from '../../../src/shared/model/create';
import type { EdgeKind, ThalyxDoc } from '../../../src/shared/model/types';

function documentWithEdge(kind: EdgeKind): ThalyxDoc {
  const doc = newDoc();
  doc.nodes.push(
    newNode({ id: 'source', x: 0, y: 0, width: 100, height: 60 }),
    newNode({ id: 'target', x: 300, y: 200, width: 100, height: 60 }),
  );
  doc.edges.push(
    newEdge({
      id: 'edge',
      source: 'source',
      target: 'target',
      sourceAnchor: 'e',
      targetAnchor: 'w',
      kind,
    }),
  );

  return doc;
}

function connectorPath(svg: string): string {
  const match = svg.match(/<path d="([^"]+)" fill="none"/);
  if (!match) throw new Error('connector path missing');

  return match[1]!;
}

describe('SVG connector parity', () => {
  it('exports a cubic curved path and places its label on that curve', () => {
    const doc = documentWithEdge('curved');
    Object.assign(doc.edges[0]!, { label: 'curve', labelT: 0.25 });

    const svg = renderDocToSvg(doc, { background: 'light', padding: 0 });
    const label = svg.match(/<text x="([^"]+)" y="([^"]+)"[^>]*>curve<\/text>/);

    expect(connectorPath(svg)).toBe('M 100 30 C 200 30 200 230 300 230');
    expect(Number(label?.[1])).toBeCloseTo(159.375);
    expect(Number(label?.[2])).toBeCloseTo(65.25);
  });

  it.each(['straight', 'curved'] as const)('ignores stale elbow waypoints for %s edges', (kind) => {
    const doc = documentWithEdge(kind);
    doc.edges[0]!.waypoints = [{ x: 999, y: 999 }];

    const svg = renderDocToSvg(doc, { background: 'light', padding: 0 });

    expect(connectorPath(svg)).not.toContain('999');
  });

  it('includes manual edge rails in the SVG view box', () => {
    const doc = newDoc();
    doc.nodes.push(
      newNode({ id: 'source', x: 0, y: 0, width: 100, height: 60 }),
      newNode({ id: 'target', x: 300, y: 0, width: 100, height: 60 }),
    );
    doc.edges.push(
      newEdge({
        source: 'source',
        target: 'target',
        sourceAnchor: 'e',
        targetAnchor: 'w',
        kind: 'elbow',
        waypoints: [
          { x: 116, y: 30 },
          { x: 116, y: -120 },
          { x: 284, y: -120 },
          { x: 284, y: 30 },
        ],
      }),
    );

    const svg = renderDocToSvg(doc, { background: 'light', padding: 0 });

    expect(svg).toContain('viewBox="0 -120 400 180"');
  });

  it('includes curved path extrema in the SVG view box', () => {
    const doc = documentWithEdge('curved');
    Object.assign(doc.edges[0]!, {
      sourceAnchor: 'w',
      targetAnchor: 'e',
    });

    const svg = renderDocToSvg(doc, { background: 'light', padding: 0 });
    const viewBox = svg.match(/viewBox="([^ ]+) [^ ]+ ([^ ]+) [^"]+"/);

    expect(Number(viewBox?.[1])).toBeLessThan(0);
    expect(Number(viewBox?.[1]) + Number(viewBox?.[2])).toBeGreaterThan(400);
  });
});
