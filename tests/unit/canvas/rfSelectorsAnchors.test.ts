import { describe, expect, it } from 'vitest';
import { newDoc, newEdge, newNode } from '../../../src/shared/model/create';
import { toReactFlowEdges } from '../../../src/renderer/canvas/rfSelectors';

describe('React Flow edge anchors', () => {
  it('maps pinned model anchors back to matching handles', () => {
    const doc = newDoc();
    const source = newNode({ id: 'source' });
    const target = newNode({ id: 'target' });
    doc.nodes.push(source, target);
    doc.edges.push(
      newEdge({
        id: 'edge',
        source: source.id,
        target: target.id,
        sourceAnchor: 'e',
        targetAnchor: 'w',
      }),
    );

    expect(toReactFlowEdges(doc.edges, { nodeIds: [], edgeIds: [] })[0]).toMatchObject({
      sourceHandle: 'e',
      targetHandle: 'w',
    });
  });

  it('leaves automatic anchors unpinned', () => {
    const doc = newDoc();
    const source = newNode({ id: 'source' });
    const target = newNode({ id: 'target' });
    doc.nodes.push(source, target);
    doc.edges.push(newEdge({ id: 'edge', source: source.id, target: target.id }));

    expect(toReactFlowEdges(doc.edges, { nodeIds: [], edgeIds: [] })[0]).toMatchObject({
      sourceHandle: null,
      targetHandle: null,
    });
  });
});
