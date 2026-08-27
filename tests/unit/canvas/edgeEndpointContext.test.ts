import { describe, expect, it } from 'vitest';
import { shallow } from 'zustand/shallow';
import {
  absoluteFromContext,
  edgeEndpointContext,
} from '../../../src/renderer/canvas/edges/edgeEndpointContext';
import { newDoc, newNode } from '../../../src/shared/model/create';

describe('edge endpoint subscriptions', () => {
  it('remain shallow-equal when an unrelated node changes', () => {
    const source = newNode({ id: 'source', x: 10, y: 20 });
    const target = newNode({ id: 'target', x: 300, y: 200 });
    const unrelated = newNode({ id: 'other' });
    const first = { ...newDoc(), nodes: [source, target, unrelated] };
    const second = {
      ...first,
      nodes: [source, target, { ...unrelated, x: 500 }],
    };

    expect(
      shallow(
        edgeEndpointContext(first, source.id, target.id),
        edgeEndpointContext(second, source.id, target.id),
      ),
    ).toBe(true);
  });

  it('includes ancestors that affect absolute endpoint geometry', () => {
    const frame = newNode({ id: 'frame', kind: 'container', x: 100, y: 80 });
    const source = newNode({ id: 'source', parentId: frame.id, x: 20, y: 30 });
    const target = newNode({ id: 'target', x: 500, y: 300 });
    const doc = { ...newDoc(), nodes: [frame, source, target] };
    const context = edgeEndpointContext(doc, source.id, target.id);

    expect(absoluteFromContext(context, source)).toEqual({ x: 120, y: 110 });
    expect(context).toContain(frame);
  });
});
