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
  type Connection,
  type Edge,
} from '@xyflow/react';
import { useStore } from '../store/store';
import * as A from '../store/actions';
import { toReactFlowEdges, toReactFlowNodes } from './rfSelectors';
import { ShapeNode } from './nodes/ShapeNode';
import { TextNode } from './nodes/TextNode';
import { ContainerNode } from './nodes/ContainerNode';
import { MermaidIslandNode } from './nodes/MermaidIslandNode';
import { EmptyCanvasHint } from './overlays/EmptyCanvasHint';
import { GuideLines } from './overlays/GuideLines';
import { QuickConnectChevrons } from './overlays/QuickConnectChevrons';
import { usePasteImport } from './hooks/usePasteImport';
import { computeSnap, type Bounds } from '../../../src/shared/snap/snap';
import { absolutePosition, descendantIdsOf } from '../../../src/shared/model/queries';
import { ThalyxEdgeComponent } from './edges/ThalyxEdge';
import { startsNodeGesture } from './nodeChangeGesture';
import { useObjectCreation } from './hooks/useObjectCreation';
import { connectionAnchor } from './connectionAnchors';

const nodeTypes: NodeTypes = {
  shape: ShapeNode,
  text: TextNode,
  container: ContainerNode,
  mermaid: MermaidIslandNode,
};

const edgeTypes = { thalyx: ThalyxEdgeComponent };

export function Canvas() {
  const modelNodes = useStore((s) => s.doc.nodes);
  const modelEdges = useStore((s) => s.doc.edges);
  const grid = useStore((s) => s.doc.canvas.grid);
  const tool = useStore((s) => s.session.tool);
  // Selection-slice subscription: tool/viewport session changes must not
  // rebuild the node/edge arrays (§11.1 perf doctrine).
  const selection = useStore((s) => s.session.selection);
  const rfInstance = useReactFlow();
  const { toast } = usePasteImport();
  const rootRef = useRef<HTMLDivElement>(null);
  const creationPreview = useObjectCreation(rootRef);
  const gestureActive = useRef(false);
  const movedIds = useRef<Set<string>>(new Set());
  const snapDisabled = useRef(false); // Mod held during a drag (§11.4)
  const altDragIds = useRef<string[] | null>(null);

  const nodes = useMemo(() => toReactFlowNodes(modelNodes, selection), [modelNodes, selection]);
  const edges = useMemo(() => toReactFlowEdges(modelEdges, selection), [modelEdges, selection]);
  const connectableNodeIds = useMemo(
    () => new Set(modelNodes.filter((node) => node.kind !== 'mermaid').map((node) => node.id)),
    [modelNodes],
  );

  const onSelectionChange = useCallback(({ nodes: n, edges: e }: OnSelectionChangeParams) => {
    A.setSelection(
      n.map((x) => x.id),
      e.map((x) => x.id),
    );
  }, []);

  const onNodesChange: OnNodesChange = useCallback(
    (changes) => {
      if (startsNodeGesture(changes) && !gestureActive.current) {
        gestureActive.current = true;
        movedIds.current = new Set();
        A.beginGesture();
      }

      // Position changes: transient frames while dragging; gesture committed on
      // drag stop. Selection changes flow back through onSelectionChange.
      const positionChanges = changes.filter(
        (c): c is Extract<NodeChange, { type: 'position' }> =>
          c.type === 'position' && typeof c.position !== 'undefined',
      );
      const dragging = changes.some((c) => c.type === 'position' && c.dragging === true);

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
            const moved = new Set(draggedIds);
            for (const id of descendantIdsOf(state.doc, draggedIds)) moved.add(id);
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
        if (altDragIds.current) {
          A.finishAltDragDuplicate(altDragIds.current);
          altDragIds.current = null;
        } else {
          A.reparentNodesTransient([...movedIds.current]);
          A.endGesture();
        }
      }

      // Dimension changes come from NodeResizer — transient during the resize
      // drag; commit once via the gesture the resizer starts/stops.
      const dimChanges = changes.filter(
        (c): c is Extract<NodeChange, { type: 'dimensions' }> =>
          c.type === 'dimensions' && c.resizing === true && typeof c.dimensions !== 'undefined',
      );
      for (const c of dimChanges) {
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
      }
    },
    [rfInstance],
  );

  const onNodeDragStart = useCallback(
    (event: Parameters<OnNodeDragParameter>[0], node: { id: string }) => {
      snapDisabled.current = event.altKey ? false : event.metaKey || event.ctrlKey;
      const state = useStore.getState();
      const sel = state.session.selection.nodeIds;
      const ids = sel.length > 0 ? sel : [node.id];
      if (event.altKey) {
        altDragIds.current = ids.filter((id) => state.doc.nodes.some((n) => n.id === id));
      } else {
        altDragIds.current = null;
      }
    },
    [],
  );

  const onConnect = useCallback((connection: Connection) => {
    if (!connection.source || !connection.target || connection.source === connection.target) return;

    const tool = useStore.getState().session.tool;
    A.connectEdge(connection.source, connection.target, tool, {
      sourceAnchor: connectionAnchor(connection.sourceHandle),
      targetAnchor: connectionAnchor(connection.targetHandle),
    });
  }, []);

  const isValidConnection = useCallback(
    (connection: Connection | Edge) => {
      if (!connection.source || !connection.target || connection.source === connection.target) {
        return false;
      }

      return connectableNodeIds.has(connection.source) && connectableNodeIds.has(connection.target);
    },
    [connectableNodeIds],
  );

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
      className={`thalyx-canvas-root${tool === 'hand' ? ' is-hand-tool' : ''}`}
      onContextMenu={(e) => e.preventDefault()} // right-drag pan must not open the browser menu
    >
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        onNodesChange={onNodesChange}
        onSelectionChange={onSelectionChange}
        onNodeDragStart={onNodeDragStart}
        selectionOnDrag={tool === 'select'}
        panOnDrag={tool === 'hand' ? true : [1, 2]}
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
        nodesDraggable={tool === 'select'}
        nodesConnectable={tool === 'select' || tool === 'arrow' || tool === 'line'}
        connectionMode={ConnectionMode.Loose}
        connectOnClick={false}
        edgesFocusable
        edgeTypes={edgeTypes}
        onConnect={onConnect}
        isValidConnection={isValidConnection}
        connectionRadius={32}
      >
        {grid ? (
          <Background variant={BackgroundVariant.Dots} gap={16} size={1} color="var(--grid)" />
        ) : null}
        <QuickConnectChevrons />
      </ReactFlow>
      {creationPreview ? (
        <div
          className="thalyx-creation-preview"
          style={{
            left: creationPreview.left,
            top: creationPreview.top,
            width: creationPreview.width,
            height: creationPreview.height,
          }}
        />
      ) : null}
      <GuideLines />
      {toast ? (
        <div className="thalyx-toast" role="status" aria-live="polite">
          <span>{toast.message}</span>
          <button onClick={toast.onTextInstead}>Paste as text instead</button>
        </div>
      ) : null}
      <EmptyCanvasHint visible={modelNodes.length === 0} />
    </div>
  );
}
