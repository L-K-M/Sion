import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { resetStore, getStore } from '../../../src/renderer/store/store';
import * as A from '../../../src/renderer/store/actions';
import { absolutePosition, descendantsOf } from '../../../src/shared/model/queries';
import { newEdge, newNode } from '../../../src/shared/model/create';
import type { ThalyxDoc } from '../../../src/shared/model/types';

function doc(): ThalyxDoc {
  return getStore().doc;
}

beforeEach(() => {
  resetStore();
});

afterEach(() => {
  resetStore();
});

describe('store basics', () => {
  it('starts with an empty doc, clean session', () => {
    const s = getStore();
    expect(s.doc.nodes).toEqual([]);
    expect(s.session.dirtySinceSave).toBe(false);
    expect(s.session.tool).toBe('select');
    expect(s.session.pendingShape).toBe('rounded');
  });

  it('addNode adds + selects + marks dirty + creates one history entry', () => {
    const id = A.addNode({ x: 10, y: 20, label: 'A' });
    const s = getStore();
    expect(s.doc.nodes.length).toBe(1);
    expect(s.doc.nodes[0]!.id).toBe(id);
    expect(s.session.selection.nodeIds).toEqual([id]);
    expect(s.session.dirtySinceSave).toBe(true);
    expect(s.history.past.length).toBe(1);

    A.undo();
    expect(getStore().doc.nodes.length).toBe(0);
    expect(getStore().session.selection.nodeIds).toEqual([]); // pruned
    A.redo();
    expect(getStore().doc.nodes.length).toBe(1);
  });

  it('updateNodeLabel clamps at 4 kB', () => {
    const id = A.addNode({ label: 'A' });
    A.updateNodeLabel(id, 'x'.repeat(6000));
    expect(doc().nodes[0]!.label.length).toBe(4096);
  });
});

describe('edges & invariants', () => {
  it('addEdge rejects unknown endpoints and islands', () => {
    const a = A.addNode({ label: 'A' });
    const island = A.addNode({ kind: 'mermaid', mermaidSource: 'pie' });
    expect(() => A.addEdge({ source: a, target: 'nope' })).toThrow();
    expect(() => A.addEdge({ source: a, target: island })).toThrow();
    expect(doc().edges.length).toBe(0);
  });

  it('deleting a node deletes its edges in the SAME history entry', () => {
    const a = A.addNode({ label: 'A' });
    const b = A.addNode({ label: 'B' });
    const e = A.addEdge({ source: a, target: b });
    expect(doc().edges.length).toBe(1);
    const entriesBefore = getStore().history.past.length;

    A.setSelection([b]);
    A.deleteSelection();
    expect(doc().nodes.length).toBe(1);
    expect(doc().edges.length).toBe(0); // dependent edge gone too
    expect(getStore().history.past.length).toBe(entriesBefore + 1); // ONE entry

    A.undo();
    expect(doc().nodes.length).toBe(2);
    expect(doc().edges.length).toBe(1);
    expect(doc().edges[0]!.id).toBe(e);
  });

  it('deleting a container takes its descendants (one entry)', () => {
    const g = A.addNode({ kind: 'container', label: 'G', x: 0, y: 0, width: 300, height: 200 });
    const c = A.addNode({ label: 'in', parentId: g, x: 10, y: 10 });
    const d = A.addNode({ label: 'out' });
    const before = getStore().history.past.length;
    A.setSelection([g]);
    A.deleteSelection();
    expect(doc().nodes.map((n) => n.id)).toEqual([d]);
    expect(getStore().history.past.length).toBe(before + 1);
    A.undo();
    expect(doc().nodes.length).toBe(3);
    expect(doc().nodes.find((n) => n.id === c)?.parentId).toBe(g);
  });

  it('waypoints: set (gesture) then clear-on-endpoint-move (D12)', () => {
    const a = A.addNode({ label: 'A' });
    const b = A.addNode({ label: 'B' });
    const e = A.addEdge({ source: a, target: b });
    A.beginGesture();
    A.setEdgeWaypoints(e, [{ x: 5, y: 5 }], { transient: true });
    A.endGesture();
    expect(doc().edges[0]!.waypoints).toEqual([{ x: 5, y: 5 }]);
    A.clearWaypointsOfNodeEndpoints([a]);
    expect(doc().edges[0]!.waypoints).toBeUndefined();
  });
});

describe('duplicate & paste', () => {
  it('duplicateSelection re-ids, offsets +16/+16, keeps intra edges only', () => {
    const a = A.addNode({ label: 'A', x: 100, y: 100 });
    const b = A.addNode({ label: 'B', x: 400, y: 100 });
    const outside = A.addNode({ label: 'C', x: 700, y: 100 });
    A.addEdge({ source: a, target: b });
    const abEdge = A.addEdge({ source: b, target: outside });
    A.setSelection([a, b]);
    const before = getStore().history.past.length;

    A.duplicateSelection();
    const s = getStore();
    expect(s.doc.nodes.length).toBe(5);
    expect(s.doc.edges.length).toBe(3); // intra duplicated, cross not
    const dupA = s.session.selection.nodeIds[0]!;
    expect(dupA).not.toBe(a);
    const nodeA = s.doc.nodes.find((n) => n.id === dupA)!;
    expect(nodeA.x).toBe(116);
    expect(nodeA.y).toBe(116);
    expect(s.history.past.length).toBe(before + 1);
    // cross edge untouched
    expect(s.doc.edges.some((e) => e.id === abEdge)).toBe(true);
    A.undo();
    expect(getStore().doc.nodes.length).toBe(3);
  });

  it('duplicating a container brings its children even if unselected', () => {
    const g = A.addNode({ kind: 'container', label: 'G', x: 0, y: 0, width: 300, height: 200 });
    A.addNode({ label: 'kid', parentId: g, x: 10, y: 10 });
    A.setSelection([g]);
    A.duplicateSelection();
    expect(getStore().doc.nodes.length).toBe(4);
    const dupG = getStore().session.selection.nodeIds[0]!;
    const dupKid = getStore().doc.nodes.find((n) => n.id !== g && n.parentId === dupG);
    expect(dupKid).toBeDefined();
  });
});

describe('containers', () => {
  it('groupIntoContainer preserves absolute positions (§7.2.7)', () => {
    const a = A.addNode({ label: 'A', x: 100, y: 100 });
    const b = A.addNode({ label: 'B', x: 400, y: 300 });
    A.setSelection([a, b]);
    const before = getStore().history.past.length;

    A.groupIntoContainer('G');
    const s = getStore();
    const g = s.session.selection.nodeIds[0]!;
    const gNode = s.doc.nodes.find((n) => n.id === g)!;
    expect(gNode.kind).toBe('container');
    expect(gNode.label).toBe('G');
    // container bounds = member bounds + 24 padding each side
    // members abs: (100,100)-(260,164), (400,300)-(560,364) → bounds (100,100)-(560,364)
    expect(gNode.x).toBe(100 - 24);
    expect(gNode.y).toBe(100 - 24);
    expect(gNode.width).toBeCloseTo(460 + 48);
    expect(gNode.height).toBeCloseTo(264 + 48);
    // children keep absolute positions
    expect(
      absolutePosition(
        s.doc,
        s.doc.nodes.find((n) => n.id === a)!,
      ),
    ).toEqual({ x: 100, y: 100 });
    expect(
      absolutePosition(
        s.doc,
        s.doc.nodes.find((n) => n.id === b)!,
      ),
    ).toEqual({ x: 400, y: 300 });
    // stored coords are now parent-relative
    expect(s.doc.nodes.find((n) => n.id === a)!.parentId).toBe(g);
    expect(s.doc.nodes.find((n) => n.id === a)!.x).toBe(24);
    // container appears before its children in the array (invariant 3)
    expect(s.doc.nodes.findIndex((n) => n.id === g)).toBeLessThan(
      s.doc.nodes.findIndex((n) => n.id === a),
    );
    expect(s.history.past.length).toBe(before + 1);

    A.undo();
    const after = getStore().doc;
    expect(after.nodes.find((n) => n.id === a)!.parentId).toBeUndefined();
    expect(after.nodes.find((n) => n.id === a)!.x).toBe(100);
  });

  it('dissolveContainer restores absolute positions and drops container edges', () => {
    const a = A.addNode({ label: 'A', x: 100, y: 100 });
    const b = A.addNode({ label: 'B', x: 400, y: 300 });
    A.setSelection([a, b]);
    A.groupIntoContainer('G');
    const g = getStore().session.selection.nodeIds[0]!;
    const d = A.addNode({ label: 'D' });
    A.addEdge({ source: d, target: g }); // edge to the container
    const before = getStore().history.past.length;

    A.setSelection([g]);
    A.dissolveContainer();
    const s = getStore();
    expect(s.doc.nodes.length).toBe(3); // a, b, d (container gone)
    expect(
      absolutePosition(
        s.doc,
        s.doc.nodes.find((n) => n.id === a)!,
      ),
    ).toEqual({ x: 100, y: 100 });
    expect(
      absolutePosition(
        s.doc,
        s.doc.nodes.find((n) => n.id === b)!,
      ),
    ).toEqual({ x: 400, y: 300 });
    expect(s.doc.edges.length).toBe(0); // container edge dropped
    expect(s.history.past.length).toBe(before + 1);
    // freed children selected
    expect([...s.session.selection.nodeIds].sort()).toEqual([a, b].sort());
    A.undo();
    expect(getStore().doc.nodes.length).toBe(4);
    expect(getStore().doc.edges.length).toBe(1);
  });
});

describe('z-order', () => {
  it('front/back/forward/backward keep containers before children', () => {
    const a = A.addNode({ label: 'A' });
    const g = A.addNode({ kind: 'container', label: 'G', x: 500, y: 0, width: 300, height: 200 });
    const kid = A.addNode({ label: 'kid', parentId: g, x: 10, y: 10 });
    const z = A.addNode({ label: 'Z' });
    // order now: a, g, kid, z

    A.setSelection([a]);
    A.reorderZ('front');
    expect(doc().nodes.map((n) => n.id)).toEqual([g, kid, z, a]);

    A.reorderZ('back');
    expect(doc().nodes.map((n) => n.id)).toEqual([a, g, kid, z]);

    A.reorderZ('forward');
    expect(doc().nodes.map((n) => n.id)).toEqual([g, a, kid, z]);

    A.reorderZ('backward');
    expect(doc().nodes.map((n) => n.id)).toEqual([a, g, kid, z]);

    // moving a container moves it with its descendant as a block
    A.setSelection([g]);
    A.reorderZ('front');
    expect(doc().nodes.map((n) => n.id)).toEqual([a, z, g, kid]);
    const idx = (id: string) => doc().nodes.findIndex((n) => n.id === id);
    expect(idx(g)).toBeLessThan(idx(kid)); // invariant 3 preserved
  });

  it('reorderZ commits one entry per invocation (including a front-while-already-front no-op reorder)', () => {
    const a = A.addNode({ label: 'A' });
    const b = A.addNode({ label: 'B' });
    const before = getStore().history.past.length;
    A.setSelection([a]);
    A.reorderZ('front'); // [b, a] — changed
    A.reorderZ('front'); // already front — rebuilt array, still one commit
    const entries = getStore().history.past.length - before;
    expect(entries).toBe(2);
    expect(getStore().doc.nodes.map((n) => n.id)).toEqual([b, a]);
  });
});

describe('align', () => {
  it('aligns left on absolute coordinates (also inside containers)', () => {
    const a = A.addNode({ label: 'A', x: 100, y: 100 });
    const g = A.addNode({ kind: 'container', label: 'G', x: 500, y: 40, width: 400, height: 300 });
    const kid = A.addNode({ label: 'kid', parentId: g, x: 30, y: 50 }); // abs (530, 90)
    A.setSelection([a, kid]);
    A.alignSelection('left');
    // bounds.x = 100 → both at abs x 100
    expect(
      absolutePosition(
        doc(),
        doc().nodes.find((n) => n.id === a)!,
      ).x,
    ).toBe(100);
    expect(
      absolutePosition(
        doc(),
        doc().nodes.find((n) => n.id === kid)!,
      ).x,
    ).toBe(100);
    // kid stays parent-relative under g
    expect(doc().nodes.find((n) => n.id === kid)!.parentId).toBe(g);
    expect(doc().nodes.find((n) => n.id === kid)!.x).toBe(100 - 500);
  });

  it('align does nothing with fewer than 2 nodes', () => {
    const a = A.addNode({ label: 'A' });
    A.setSelection([a]);
    const before = JSON.stringify(doc());
    A.alignSelection('top');
    expect(JSON.stringify(doc())).toBe(before);
  });
});

describe('gestures & transient updates', () => {
  it('moveNodes transient frames + one gesture entry', () => {
    const a = A.addNode({ label: 'A' });
    const b = A.addNode({ label: 'B' });
    A.addEdge({ source: a, target: b });
    const before = getStore().history.past.length;

    A.beginGesture();
    A.moveNodesTransient([{ id: a, x: 50, y: 60 }]);
    A.moveNodesTransient([{ id: a, x: 120, y: 130 }]);
    A.endGesture();
    expect(doc().nodes.find((n) => n.id === a)!.x).toBe(120);
    expect(getStore().history.past.length).toBe(before + 1); // ONE entry
    A.undo();
    expect(doc().nodes.find((n) => n.id === a)!.x).toBe(0);
  });

  it('locked nodes refuse transient moves/resizes', () => {
    const a = A.addNode({ label: 'A' });
    A.setNodesLocked([a], true);
    A.beginGesture();
    A.moveNodesTransient([{ id: a, x: 999, y: 999 }]);
    A.endGesture();
    expect(doc().nodes.find((n) => n.id === a)!.x).toBe(0);
  });

  it('resize clamps to ≥ 8', () => {
    const a = A.addNode({ label: 'A' });
    A.beginGesture();
    A.resizeNodeTransient(a, { width: 2, height: -3 });
    A.endGesture();
    const n = doc().nodes.find((x) => x.id === a)!;
    expect(n.width).toBe(8);
    expect(n.height).toBe(8);
  });

  it('locked nodes refuse transient resize', () => {
    const a = A.addNode({ label: 'A' });
    A.setNodesLocked([a], true);
    A.beginGesture();
    A.resizeNodeTransient(a, { width: 500, height: 500 });
    A.endGesture();
    const n = doc().nodes.find((x) => x.id === a)!;
    expect(n.width).toBe(160);
    expect(n.height).toBe(64);
  });
});

describe('doc-level actions', () => {
  it('toggleGrid / setCanvas / setDirection are tracked and undoable', () => {
    A.toggleGrid();
    expect(doc().canvas.grid).toBe(true);
    A.undo();
    expect(doc().canvas.grid).toBe(false);

    A.setDirection('LR');
    expect(doc().meta.mermaid?.direction).toBe('LR');
    A.undo();
    expect(doc().meta.mermaid?.direction).toBe('TB');

    A.setCanvas({ background: '#fff' });
    expect(doc().canvas.background).toBe('#fff');
    A.undo();
    expect(doc().canvas.background).toBe('default');
  });

  it('paste drops dangling parentIds and unresolvable edge endpoints', () => {
    const a = newNode({ id: 'clip-a', x: 0, y: 0, label: 'A' });
    const orphan = newNode({ id: 'clip-orphan', x: 50, y: 0, label: 'O', parentId: 'not-in-clip' });
    const edgeIn = { ...newEdge({ id: 'clip-e1', source: 'clip-a', target: 'clip-orphan' }) };
    const edgeOut = { ...newEdge({ id: 'clip-e2', source: 'clip-a', target: 'elsewhere' }) };
    A.pasteInternal([a, orphan], [edgeIn, edgeOut]);
    const s = getStore();
    expect(s.doc.nodes.length).toBe(2);
    expect(s.doc.nodes.every((n) => n.parentId === undefined)).toBe(true); // dangling dropped
    expect(s.doc.edges.length).toBe(1); // unresolvable endpoint dropped
    expect(s.doc.edges[0]!.source).toBe(s.doc.nodes.find((n) => n.label === 'A')!.id);
  });

  it('session setters do not create history entries', () => {
    const before = getStore().history.past.length;
    A.setTool('hand');
    A.setPendingShape('diamond');
    A.setSelection(['x']);
    A.setTheme('dark');
    A.setViewport({ x: 1, y: 2, zoom: 0.5 });
    expect(getStore().history.past.length).toBe(before);
    expect(getStore().session.tool).toBe('hand');
    expect(getStore().session.pendingShape).toBe('diamond');
    expect(getStore().session.viewport).toEqual({ x: 1, y: 2, zoom: 0.5 });
  });

  it('pasteInternal re-ids and selects', () => {
    const a = newNode({ id: 'clip-a', x: 0, y: 0, label: 'clip' });
    const pasted = A.pasteInternal([a], []);
    void pasted;
    const sel = getStore().session.selection.nodeIds;
    expect(sel.length).toBe(1);
    expect(sel[0]).not.toBe('clip-a');
    expect(doc().nodes[0]!.label).toBe('clip');
    expect(doc().nodes[0]!.x).toBe(16); // +16 offset
  });
});

describe('undo/redo selection hygiene', () => {
  it('undo prunes selection ids that no longer exist', () => {
    A.addNode({ label: 'A' }); // entry 1
    A.addNode({ label: 'B' }); // entry 2 (B selected)
    A.undo(); // B gone; selection must not reference it
    expect(getStore().session.selection.nodeIds).toEqual([]);
  });
});

describe('descendant expansion helper sanity', () => {
  it('descendantsOf on nested containers', () => {
    const outer = A.addNode({ kind: 'container', label: 'O', width: 600, height: 400 });
    const inner = A.addNode({
      kind: 'container',
      label: 'I',
      parentId: outer,
      x: 20,
      y: 20,
      width: 300,
      height: 200,
    });
    A.addNode({ label: 'leaf', parentId: inner, x: 5, y: 5 });
    expect(
      descendantsOf(doc(), outer)
        .map((n) => n.label)
        .sort(),
    ).toEqual(['I', 'leaf']);
  });
});

describe('review round 3 regressions', () => {
  it('reIdSubgraph handles child-before-parent input order (pasteInternal)', () => {
    const parent = newNode({
      id: 'p-old',
      kind: 'container',
      x: 0,
      y: 0,
      width: 300,
      height: 200,
      label: 'P',
    });
    const child = newNode({ id: 'c-old', x: 10, y: 10, label: 'C', parentId: 'p-old' });
    // child listed BEFORE parent
    A.pasteInternal([child, parent], []);
    const s = getStore();
    const newParent = s.doc.nodes.find((n) => n.id !== 'p-old' && n.kind === 'container')!;
    const newChild = s.doc.nodes.find((n) => n.id !== 'c-old' && n.label === 'C')!;
    expect(newChild.parentId).toBe(newParent.id);
  });

  it('undo mid-gesture reverts to the pre-gesture snapshot', () => {
    const a = A.addNode({ label: 'A', x: 0, y: 0 }); // one entry
    A.markSaved();
    A.beginGesture();
    A.moveNodesTransient([{ id: a, x: 55, y: 66 }]);
    expect(doc().nodes.find((n) => n.id === a)!.x).toBe(55);
    A.undo(); // mid-gesture undo → pending snapshot
    expect(doc().nodes.find((n) => n.id === a)!.x).toBe(0);
    expect(getStore().history.pending).toBeNull();
    A.redo(); // gesture state back
    expect(doc().nodes.find((n) => n.id === a)!.x).toBe(55);
  });

  it('a no-op transient produce does not mark the doc dirty', () => {
    const a = A.addNode({ label: 'A' });
    A.markSaved();
    expect(getStore().session.dirtySinceSave).toBe(false);
    A.beginGesture();
    A.moveNodesTransient([{ id: a, x: 0, y: 0 }]); // same position → no-op produce
    A.endGesture();
    expect(getStore().session.dirtySinceSave).toBe(false);
  });

  it('send-to-back inside a container stays below its ancestors', () => {
    const g = A.addNode({ kind: 'container', label: 'G', x: 0, y: 0, width: 400, height: 300 });
    const kid = A.addNode({ label: 'kid', parentId: g, x: 10, y: 10 });
    const z = A.addNode({ label: 'Z' }); // top level, after
    A.setSelection([kid]);
    A.reorderZ('back');
    const idx = (id: string) => doc().nodes.findIndex((n) => n.id === id);
    expect(idx(g)).toBeLessThan(idx(kid)); // invariant 3 preserved
    expect(idx(kid)).toBeLessThan(idx(z)); // kid sank but not past unrelated nodes' order with G
    // moving backward past the parent is refused
    A.reorderZ('backward');
    expect(idx(g)).toBeLessThan(idx(kid));
  });
});

describe('connectEdge (M3)', () => {
  it('arrow tool connects with the last-used style; line tool omits arrowheads', () => {
    const a = A.addNode({ label: 'A' });
    const b = A.addNode({ label: 'B' });
    const e1 = A.connectEdge(a, b, 'arrow');
    expect(doc().edges).toHaveLength(1);
    expect(doc().edges[0]!.arrowEnd).toBe('arrow');
    expect(doc().edges[0]!.kind).toBe('elbow');
    expect(getStore().session.lastEdgeStyle).toEqual({ arrowEnd: 'arrow', line: 'solid' });

    const e2 = A.connectEdge(b, a, 'line');
    expect(doc().edges[1]!.arrowEnd).toBe('none');
    expect(doc().edges[1]!.arrowStart).toBe('none');
    expect(getStore().session.lastEdgeStyle).toEqual({ arrowEnd: 'none', line: 'solid' });
    // distinct ids, both present in the doc
    expect(e1).not.toBe(e2);
    expect(
      doc()
        .edges.map((e) => e.id)
        .sort(),
    ).toEqual([e1, e2].sort());
  });

  it('connect is ONE history entry; undo removes the edge', () => {
    const a = A.addNode({ label: 'A' });
    const b = A.addNode({ label: 'B' });
    const before = getStore().history.past.length;
    A.connectEdge(a, b, 'arrow');
    expect(getStore().history.past.length).toBe(before + 1);
    A.undo();
    expect(doc().edges).toHaveLength(0);
    // undoing the connect must not touch the nodes
    expect(
      doc()
        .nodes.map((n) => n.label)
        .sort(),
    ).toEqual(['A', 'B']);
  });

  it('style inheritance: dashed last-used style carries into the next edge', () => {
    const a = A.addNode({ label: 'A' });
    const b = A.addNode({ label: 'B' });
    A.setLastEdgeStyle({ arrowEnd: 'arrow', line: 'dashed' });
    A.connectEdge(a, b, 'arrow');
    expect(doc().edges[0]!.style.line).toBe('dashed');
  });

  it('label update via updateEdge is one undo entry; labelT clamped', () => {
    const a = A.addNode({ label: 'A' });
    const b = A.addNode({ label: 'B' });
    const e = A.connectEdge(a, b, 'arrow');
    const before = getStore().history.past.length;
    A.updateEdge(e, { label: 'yes', labelT: 2 });
    expect(getStore().history.past.length).toBe(before + 1);
    expect(doc().edges[0]!.label).toBe('yes');
    expect(doc().edges[0]!.labelT).toBe(1); // upper clamp
    A.updateEdge(e, { labelT: -3 });
    expect(doc().edges[0]!.labelT).toBe(0); // lower clamp
    A.undo();
    A.undo();
    expect(doc().edges[0]!.label).toBeUndefined();
  });

  it('waypoint gesture coalesces and D12 clears on endpoint move', () => {
    const a = A.addNode({ label: 'A' });
    const b = A.addNode({ label: 'B' });
    const e = A.connectEdge(a, b, 'arrow');
    const before = getStore().history.past.length;
    A.beginGesture();
    A.setEdgeWaypoints(e, [{ x: 10, y: 10 }], { transient: true });
    A.setEdgeWaypoints(e, [{ x: 20, y: 20 }], { transient: true });
    A.endGesture();
    expect(getStore().history.past.length).toBe(before + 1); // ONE entry
    expect(doc().edges[0]!.waypoints).toEqual([{ x: 20, y: 20 }]);
    // endpoint move clears (D12)
    A.clearWaypointsOfNodeEndpoints([a]);
    expect(doc().edges[0]!.waypoints).toBeUndefined();
    // undo restores the pre-gesture state (no waypoints)
    A.undo();
    expect(doc().edges[0]!.waypoints).toBeUndefined();
  });
});

describe('M4a: nudge + alt-drag duplicate', () => {
  it('nudge moves the selection by the delta', () => {
    const a = A.addNode({ label: 'A', x: 0, y: 0 });
    A.addNode({ label: 'B', x: 500, y: 500 });
    A.setSelection([a]);
    A.nudgeSelection(8, -1);
    const nodes = doc().nodes;
    expect(nodes.find((n) => n.label === 'A')).toMatchObject({ x: 8, y: -1 });
    expect(nodes.find((n) => n.label === 'B')).toMatchObject({ x: 500, y: 500 });
  });

  it('alt-drag duplicate: originals restored, copies at final positions, one entry', () => {
    const a = A.addNode({ label: 'A', x: 100, y: 100 });
    const b = A.addNode({ label: 'B', x: 400, y: 100 });
    A.addEdge({ source: a, target: b });
    A.setSelection([a]);
    const before = getStore().history.past.length;

    const final = new Map([[a, { x: 260, y: 240 }]]);
    A.altDragDuplicate([a], final);
    // restore originals (as the canvas does after alt-drop)
    A.setNodesPosition([a], () => ({ x: 100, y: 100 }));

    const nodes = doc().nodes;
    expect(nodes).toHaveLength(3);
    // original back at start
    expect(nodes.find((n) => n.id === a)).toMatchObject({ x: 100, y: 100 });
    // copy at final position with a fresh id
    const copy = nodes.find((n) => n.id !== a && n.label === 'A')!;
    expect(copy).toMatchObject({ x: 260, y: 240 });
    // edge NOT duplicated (intra-selection only — b was not selected)
    expect(doc().edges).toHaveLength(1);
    expect(getStore().history.past.length).toBeGreaterThanOrEqual(before + 1);
    // copy is selected
    expect(getStore().session.selection.nodeIds).toEqual([copy.id]);
  });
});
