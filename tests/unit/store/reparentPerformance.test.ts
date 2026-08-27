import { afterEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { newDoc, newNode } from '../../../src/shared/model/create';
import { resetStore } from '../../../src/renderer/store/store';

const MOVED_NODE_COUNT = 3_000;
const CONTAINER_COUNT = 8;
const REPARENT_BUDGET_MS = 500;

afterEach(() => resetStore());

describe('reparent performance', () => {
  it('handles a large multi-selection without repeated document scans', () => {
    const doc = newDoc();
    const movedIds: string[] = [];
    for (let index = 0; index < MOVED_NODE_COUNT; index += 1) {
      const node = newNode({ x: index * 200, y: 0 });
      doc.nodes.push(node);
      movedIds.push(node.id);
    }
    for (let index = 0; index < CONTAINER_COUNT; index += 1) {
      doc.nodes.push(
        newNode({ kind: 'container', x: -10_000, y: index * 500, width: 200, height: 200 }),
      );
    }
    resetStore(doc);

    const startedAt = performance.now();
    A.reparentNodesTransient(movedIds);
    const elapsed = performance.now() - startedAt;

    expect(elapsed).toBeLessThan(REPARENT_BUDGET_MS);
  });
});
