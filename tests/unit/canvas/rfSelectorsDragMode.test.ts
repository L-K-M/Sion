import { describe, expect, it } from 'vitest';
import { toReactFlowNodes } from '../../../src/renderer/canvas/rfSelectors';
import { newNode } from '../../../src/shared/model/create';

const EMPTY_SELECTION = { nodeIds: [], edgeIds: [] };

describe('React Flow drag mode', () => {
  it('lets the canvas tool control unlocked nodes while locked nodes stay fixed', () => {
    const unlocked = newNode();
    const locked = newNode({ locked: true });
    const [unlockedView, lockedView] = toReactFlowNodes([unlocked, locked], EMPTY_SELECTION);

    expect(unlockedView).not.toHaveProperty('draggable');
    expect(lockedView?.draggable).toBe(false);
  });
});
