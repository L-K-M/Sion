import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('container resizing', () => {
  it('keeps frames large enough to use their title and children', () => {
    const frame = A.addNode({ kind: 'container', width: 320, height: 200 });

    A.beginGesture();
    A.resizeNodeTransient(frame, { width: 8, height: 8 });
    A.endGesture();

    expect(getStore().doc.nodes[0]).toMatchObject({ width: 120, height: 80 });
  });
});
