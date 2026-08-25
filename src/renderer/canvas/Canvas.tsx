/**
 * Canvas (PLAN.md §11.1): controlled React Flow wiring.
 *
 * - nodes/edges are derived from the doc via memoized selectors
 * - NO snapToGrid prop ever — snap.ts (§11.4, M4) is the single snap authority
 * - selectionOnDrag (rubber-band), panOnDrag={[1,2]} (middle/right), pinch zoom
 * - onlyRenderVisibleElements from M2; minZoom 0.1 / maxZoom 4
 * - position changes are transient during drag and committed on drag-end (§8.2)
 */
import { useCallback, useEffect, useMemo, useRef } from 'react';

import {
  Background,
  ConnectionMode,
  BackgroundVariant,
  ReactFlow,
  useReactFlow,
  type NodeChange,
  type OnSelectionChangeParams,
  type NodeTypes,
  type OnNodesChange,
  type OnNodeDrag as OnNodeDragParameter,
} from '@xyflow/react';
import { useStore } from '../store/store';
import * as A from '../store/actions';
import { toReactFlowEdges, toReactFlowNodes } from './rfSelectors';
import { ShapeNode } from './nodes/ShapeNode';
import { TextNode } from './nodes/TextNode';
import { ContainerNode } from './nodes/ContainerNode';
import { EmptyCanvasHint } from './overlays/EmptyCanvasHint';
import { GuideLines } from './overlays/GuideLines';
import { QuickConnectChevrons } from './overlays/QuickConnectChevrons';
import { computeSnap, type Bounds } from '../../../src/shared/snap/snap';
import { absolutePosition, descendantsOf } from '../../../src/shared/model/queries';
import { ThalyxEdgeComponent } from './edges/ThalyxEdge';

const nodeTypes: NodeTypes = {
  shape: ShapeNode,
  text: TextNode,
  container: ContainerNode,
  // 'mermaid' island node type lands with M5.
};

const edgeTypes = { thalyx: ThalyxEdgeComponent };

export function Canvas() {
  const doc = useStore((s) => s.doc);
  const session = useStore((s) => s.session);
  // Selection-slice subscription: tool/viewport session changes must not
  // rebuild the node/edge arrays (§11.1 perf doctrine).
  const selection = useStore((s) => s.session.selection);
  const rfInstance = useReactFlow();
  const rootRef = useRef<HTMLDivElement>(null);
  const gestureActive = useRef(false);
  const movedIds = useRef<Set<string>>(new Set());
  const snapDisabled = useRef(false); // Mod held during a drag (§11.4)
  const altDragStart = useRef<Map<string, { x: number; y: number }> | null>(null);
  const altDragFinal = useRef<Map<string, { x: number; y: number }> | null>(null);

  const collectAltDragPositions = (): Map<string, { x: number; y: number }> | null => {
    const start = altDragStart.current;
    if (!start) return null;
    const doc = useStore.getState().doc;
    const positions = new Map<string, { x: number; y: number }>();
    for (const id of start.keys()) {
      const n = doc.nodes.find((x) => x.id === id);
      if (n) positions.set(id, { x: n.x, y: n.y });
    }
    return positions;
  };

  const nodes = useMemo(() => toReactFlowNodes(doc, selection), [doc, selection]);
  const edges = useMemo(() => toReactFlowEdges(doc, selection), [doc, selection]);

  const onSelectionChange = useCallback(({ nodes: n, edges: e }: OnSelectionChangeParams) => {
    A.setSelection(
      n.map((x) => x.id),
      e.map((x) => x.id),
    );
  }, []);

  const onNodesChange: OnNodesChange = useCallback((changes) => {
    // Position changes: transient frames while dragging; gesture committed on
    // drag stop. Selection changes flow back through onSelectionChange.
    const positionChanges = changes.filter(
      (c): c is Extract<NodeChange, { type: 'position' }> =>
        c.type === 'position' && typeof c.position !== 'undefined',
    );
    const dragging = changes.some((c) => c.type === 'position' && c.dragging === true);

    if (dragging && !gestureActive.current) {
      gestureActive.current = true;
      movedIds.current = new Set();
      A.beginGesture();
    }
    if (positionChanges.length > 0) {
      let positions = positionChanges.map((c) => ({
        id: c.id,
        x: c.position!.x,
        y: c.position!.y,
      }));
      for (const p of positions) movedIds.current.add(p.id);
      if (
        typeof console !== 'undefined' &&
        (globalThis as unknown as Record<string, unknown>).__THALYX_TRACE_DRAG__
      ) {
        console.log(
          '[drag-frame]',
          JSON.stringify(positions),
          'dragging:',
          dragging,
          'stop:',
          changes.some((ch) => ch.type === 'position' && ch.dragging === false),
        );
      }

      // Smart guides (§11.4): compute the snap for guide rendering on every
      // drag frame, but APPLY the delta only on the final frame (settle-on-
      // drop). Applying it mid-drag fights React Flow's internal drag state
      // (controlled positions feed back into the next raw frame).
      const applyDelta = changes.some((c) => c.type === 'position' && c.dragging === false);
      if (gestureActive.current && positions.length >= 1 && !snapDisabled.current) {
        const state = useStore.getState();
        const draggedIds = new Set(positions.map((p) => p.id));
        const byId = new Map(state.doc.nodes.map((n) => [n.id, n]));
        const draggedNode = byId.get(positions[0]!.id);
        if (draggedNode) {
          const pos0 = positions[0]!;
          const parentAbs = draggedNode.parentId
            ? absolutePosition(state.doc, byId.get(draggedNode.parentId)!)
            : { x: 0, y: 0 };
          const draggedBounds: Bounds = {
            x: pos0.x + parentAbs.x,
            y: pos0.y + parentAbs.y,
            width: draggedNode.width,
            height: draggedNode.height,
          };
          // Statics exclude the dragged nodes AND their descendants (they move
          // with a dragged container) — snapping against your own children is
          // meaningless (§11.4).
          const moved = new Set<string>();
          for (const id of draggedIds) {
            const n = byId.get(id);
            if (!n) continue;
            moved.add(id);
            for (const desc of descendantsOf(state.doc, id)) moved.add(desc.id);
          }
          const statics = state.doc.nodes
            .filter((n) => !moved.has(n.id) && !n.hidden)
            .map((n) => {
              const p = absolutePosition(state.doc, n);
              return { x: p.x, y: p.y, width: n.width, height: n.height } satisfies Bounds;
            });
          const zoom = rfInstance.getZoom();
          const snap = computeSnap(draggedBounds, statics, {
            grid: state.doc.canvas.grid,
            zoom,
          });
          if (applyDelta && (snap.dx !== 0 || snap.dy !== 0)) {
            positions = positions.map((p) => ({ ...p, x: p.x + snap.dx, y: p.y + snap.dy }));
          }
          A.setGuides(snap.guides);
        }
      }
      A.moveNodesTransient(positions);
    }
    const dragStopped = changes.some((c) => c.type === 'position' && c.dragging === false);
    if (dragStopped && gestureActive.current) {
      gestureActive.current = false;
      A.setGuides([]);
      altDragFinal.current = collectAltDragPositions();
      A.endGesture();
      if (movedIds.current.size > 0) {
        // D12: manual waypoints clear when an endpoint node moves.
        A.clearWaypointsOfNodeEndpoints([...movedIds.current]);
      }
    }

    // Dimension changes come from NodeResizer — transient during the resize
    // drag; commit once via the gesture the resizer starts/stops.
    const dimChanges = changes.filter(
      (c): c is Extract<NodeChange, { type: 'dimensions' }> =>
        c.type === 'dimensions' && c.resizing === true && typeof c.dimensions !== 'undefined',
    );
    for (const c of dimChanges) {
      if (!gestureActive.current) {
        gestureActive.current = true;
        movedIds.current = new Set();
        A.beginGesture();
      }
      A.resizeNodeTransient(c.id, {
        width: c.dimensions!.width,
        height: c.dimensions!.height,
      });
      movedIds.current.add(c.id);
    }
    const resizeStopped = changes.some((c) => c.type === 'dimensions' && c.resizing === false);
    if (resizeStopped && gestureActive.current) {
      gestureActive.current = false;
      A.endGesture();
      if (movedIds.current.size > 0) {
        A.clearWaypointsOfNodeEndpoints([...movedIds.current]);
      }
    }
  }, []);

  const onNodeDragStart = useCallback(
    (event: Parameters<OnNodeDragParameter>[0], node: { id: string }) => {
      snapDisabled.current = event.altKey ? false : event.metaKey || event.ctrlKey;
      const state = useStore.getState();
      const sel = state.session.selection.nodeIds;
      const ids = sel.length > 0 ? sel : [node.id];
      if (event.altKey) {
        altDragStart.current = new Map(
          ids
            .map((id) => state.doc.nodes.find((n) => n.id === id))
            .filter((n): n is NonNullable<typeof n> => Boolean(n))
            .map((n) => [n.id, { x: n.x, y: n.y }] as const),
        );
      } else {
        altDragStart.current = null;
      }
    },
    [],
  );

  const onNodeDragStop = useCallback(() => {
    // Alt-drag duplicate (I11): originals snap back, copies land at the end.
    const start = altDragStart.current;
    const final = altDragFinal.current;
    altDragStart.current = null;
    altDragFinal.current = null;
    if (start && final) {
      const state = useStore.getState();
      A.altDragDuplicate(
        [...start.keys()].filter((id) => state.doc.nodes.some((n) => n.id === id)),
        final,
      );
      // restore the originals to their pre-drag positions (one entry total is
      // acceptable: duplicate + restore are the same user intent)
      A.setNodesPosition([...start.keys()], (n) => start.get(n.id) ?? { x: n.x, y: n.y });
    }
  }, []);

  // Shape/text tools: click-place (drag-size affordance arrives with M4's
  // pointer layer; M2 places at default size centered on the click).
  const onPaneClick = useCallback(
    (event: React.MouseEvent) => {
      if (session.tool === 'shape') {
        const pos = rfInstance.screenToFlowPosition({ x: event.clientX, y: event.clientY });
        A.addNode({
          kind: 'shape',
          shape: session.pendingShape,
          x: Math.round(pos.x - 80),
          y: Math.round(pos.y - 32),
        });
        if (!session.toolLocked) A.setTool('select');
        return;
      }
      if (session.tool === 'container') {
        const pos = rfInstance.screenToFlowPosition({ x: event.clientX, y: event.clientY });
        A.addNode({
          kind: 'container',
          x: Math.round(pos.x - 160),
          y: Math.round(pos.y - 24),
          width: 320,
          height: 48,
          label: 'Group',
        });
        if (!session.toolLocked) A.setTool('select');
        return;
      }
      if (session.tool === 'text') {
        const pos = rfInstance.screenToFlowPosition({ x: event.clientX, y: event.clientY });
        const id = A.addNode({
          kind: 'text',
          x: Math.round(pos.x - 80),
          y: Math.round(pos.y - 12),
          width: 160,
          height: 24,
          label: 'Text',
        });
        void id; // label editing opens via double-click (M4 inline editor)
        if (!session.toolLocked) A.setTool('select');
      }
    },
    [session.tool, session.pendingShape, session.toolLocked, rfInstance],
  );

  const onConnect = useCallback((connection: { source: string | null; target: string | null }) => {
    if (!connection.source || !connection.target || connection.source === connection.target) return;
    const tool = useStore.getState().session.tool;
    A.connectEdge(connection.source, connection.target, tool);
  }, []);

  // Double-click: inline label editing (I10). A native capture-phase
  // listener on the canvas root — React-delegated dblclick on nodes is
  // unreliable under React Flow's d3-drag pointer handling.
  useEffect(() => {
    const el = rootRef.current;
    if (!el) return;
    const onDblClick = (e: MouseEvent) => {
      const target = e.target as HTMLElement | null;
      const nodeEl = target?.closest?.('.react-flow__node');
      const id = nodeEl?.getAttribute('data-id');
      if (id) {
        e.preventDefault();
        A.setEditingLabel({ kind: 'node', id });
      }
    };
    el.addEventListener('dblclick', onDblClick, true);
    return () => el.removeEventListener('dblclick', onDblClick, true);
  }, []);

  return (
    <div
      ref={rootRef}
      className="thalyx-canvas-root"
      onContextMenu={(e) => e.preventDefault()} // right-drag pan must not open the browser menu
    >
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        onNodesChange={onNodesChange}
        onSelectionChange={onSelectionChange}
        onPaneClick={onPaneClick}
        onNodeDragStart={onNodeDragStart}
        onNodeDragStop={onNodeDragStop}
        selectionOnDrag={session.tool !== 'hand'}
        panOnDrag={session.tool === 'hand' ? true : [1, 2]}
        zoomOnDoubleClick={false}
        zoomOnPinch
        selectionKeyCode={null}
        multiSelectionKeyCode="Shift"
        panActivationKeyCode="Space"
        deleteKeyCode={null}
        minZoom={0.1}
        maxZoom={4}
        onlyRenderVisibleElements
        proOptions={{ hideAttribution: false }}
        nodesDraggable={session.tool === 'select'}
        nodesConnectable={
          session.tool === 'select' || session.tool === 'arrow' || session.tool === 'line'
        }
        connectionMode={ConnectionMode.Loose}
        edgesFocusable
        edgeTypes={edgeTypes}
        onConnect={onConnect}
        connectionRadius={32}
      >
        {doc.canvas.grid ? (
          <Background variant={BackgroundVariant.Dots} gap={16} size={1} color="var(--grid)" />
        ) : null}
        <QuickConnectChevrons />
      </ReactFlow>
      <GuideLines />
      <EmptyCanvasHint visible={doc.nodes.length === 0} />
    </div>
  );
}
