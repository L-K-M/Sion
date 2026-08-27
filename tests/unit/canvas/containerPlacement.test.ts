import { describe, expect, it } from 'vitest';
import { newDoc, newNode } from '../../../src/shared/model/create';
import { nestPlacement } from '../../../src/renderer/canvas/creationGesture';

describe('nestPlacement', () => {
  it('converts an object drawn inside a container to parent-relative coordinates', () => {
    const doc = newDoc();
    doc.nodes.push(
      newNode({ id: 'frame', kind: 'container', x: 100, y: 80, width: 400, height: 300 }),
    );

    expect(nestPlacement(doc, 'frame', { x: 140, y: 130, width: 160, height: 64 })).toEqual({
      parentId: 'frame',
      x: 40,
      y: 50,
      width: 160,
      height: 64,
    });
  });

  it('clamps an overflowing object inside the chosen container', () => {
    const doc = newDoc();
    doc.nodes.push(
      newNode({ id: 'frame', kind: 'container', x: 100, y: 80, width: 200, height: 120 }),
    );

    expect(nestPlacement(doc, 'frame', { x: 250, y: 150, width: 160, height: 64 })).toEqual({
      parentId: 'frame',
      x: 40,
      y: 56,
      width: 160,
      height: 64,
    });
  });
});
