import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const querySpies = vi.hoisted(() => ({
  descendantIdsOf: vi.fn(),
  descendantsOf: vi.fn(),
}));

vi.mock('../../../src/shared/model/queries', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../../src/shared/model/queries')>();
  querySpies.descendantIdsOf.mockImplementation(actual.descendantIdsOf);
  querySpies.descendantsOf.mockImplementation(actual.descendantsOf);

  return {
    ...actual,
    descendantIdsOf: querySpies.descendantIdsOf,
    descendantsOf: querySpies.descendantsOf,
  };
});

import * as A from '../../../src/renderer/store/actions';
import { resetStore } from '../../../src/renderer/store/store';

beforeEach(() => {
  resetStore();
  vi.clearAllMocks();
});
afterEach(() => resetStore());

function addNestedSelection(): [outer: string, inner: string] {
  const outer = A.addNode({ kind: 'container', x: 0, y: 0, width: 300, height: 200 });
  const inner = A.addNode({
    kind: 'container',
    parentId: outer,
    x: 20,
    y: 20,
    width: 150,
    height: 100,
  });
  A.addNode({ parentId: inner, x: 10, y: 10 });

  return [outer, inner];
}

describe('duplication descendant traversal', () => {
  it('expands nested selections once for keyboard duplication', () => {
    const [outer, inner] = addNestedSelection();
    A.setSelection([outer, inner]);
    vi.clearAllMocks();

    A.duplicateSelection();

    expect(querySpies.descendantIdsOf).toHaveBeenCalledTimes(1);
    expect(querySpies.descendantsOf).not.toHaveBeenCalled();
  });

  it('expands nested selections once when Alt-drag finishes', () => {
    const [outer, inner] = addNestedSelection();
    A.beginGesture();
    A.moveNodesTransient([{ id: outer, x: 32, y: 16 }]);
    vi.clearAllMocks();

    A.finishAltDragDuplicate([outer, inner]);

    expect(querySpies.descendantIdsOf).toHaveBeenCalledTimes(1);
    expect(querySpies.descendantsOf).not.toHaveBeenCalled();
  });
});
