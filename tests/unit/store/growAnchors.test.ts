import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { resetStore, getStore } from '../../../src/renderer/store/store';
import * as A from '../../../src/renderer/store/actions';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('quick-grow connection anchors', () => {
  it.each([
    ['n', 'n', 's'],
    ['s', 's', 'n'],
    ['e', 'e', 'w'],
    ['w', 'w', 'e'],
  ] as const)(
    'pins a %s connection to opposing magnets',
    (direction, sourceAnchor, targetAnchor) => {
      const source = A.addNode({ x: 300, y: 300 });

      A.growConnectedNode(source, direction);

      expect(getStore().doc.edges[0]).toMatchObject({ sourceAnchor, targetAnchor });
    },
  );

  it('pins a corridor connection to opposing magnets', () => {
    const source = A.addNode({ x: 300, y: 300 });
    const target = A.addNode({ x: 508, y: 300 });

    expect(A.growConnectedNode(source, 'e')).toBe(target);
    expect(getStore().doc.edges[0]).toMatchObject({
      sourceAnchor: 'e',
      targetAnchor: 'w',
    });
  });
});
