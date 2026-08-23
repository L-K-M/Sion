/**
 * Canvas (PLAN.md §11.1): controlled React Flow wiring.
 *
 * - nodes/edges are derived from the doc via memoized selectors
 * - NO snapToGrid prop ever — snap.ts (§11.4, M4) is the single snap authority
 * - selectionOnDrag (rubber-band), panOnDrag={[1,2]} (middle/right), pinch zoom
 * - onlyRenderVisibleElements from M2; minZoom 0.1 / maxZoom 4
 * - position changes are transient during drag and committed on drag-end (§8.2)
 */
import { useCallback, useMemo, useRef } from 'react';
import {
  Background,
  BackgroundVariant,
  ReactFlow,
  useReactFlow,
  type NodeChange,
  type OnSelectionChangeParams,
  type NodeTypes,
  type OnNodesChange,
} from '@xyflow/react';
import { useStore } from '../store/store';
import * as A from '../store/actions';
import { toReactFlowEdges, toReactFlowNodes } from './rfSelectors';
import { ShapeNode } from './nodes/ShapeNode';
import { TextNode } from './nodes/TextNode';
import { ContainerNode } from './nodes/ContainerNode';
import { EmptyCanvasHint } from './overlays/EmptyCanvasHint';
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
  const gestureActive = useRef(false);
  const movedIds = useRef<Set<string>>(new Set());

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
      const positions = positionChanges.map((c) => ({
        id: c.id,
        x: c.position!.x,
        y: c.position!.y,
      }));
      for (const p of positions) movedIds.current.add(p.id);
      A.moveNodesTransient(positions);
    }
    const dragStopped = changes.some((c) => c.type === 'position' && c.dragging === false);
    if (dragStopped && gestureActive.current) {
      gestureActive.current = false;
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

  return (
    <div
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
        selectionOnDrag={session.tool !== 'hand'}
        panOnDrag={session.tool === 'hand' ? true : [1, 2]}
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
        edgesFocusable
        edgeTypes={edgeTypes}
        onConnect={onConnect}
        connectionRadius={32}
        fitView
        fitViewOptions={{ padding: 0.2, maxZoom: 1 }}
      >
        {doc.canvas.grid ? (
          <Background variant={BackgroundVariant.Dots} gap={16} size={1} color="var(--grid)" />
        ) : null}
      </ReactFlow>
      <EmptyCanvasHint visible={doc.nodes.length === 0} />
    </div>
  );
}
