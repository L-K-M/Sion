import { useEffect, useRef, useState, type RefObject } from 'react';
import { useReactFlow } from '@xyflow/react';
import { GRID_SIZE } from '../../../shared/snap/snap';
import type { ShapeKind, Tool } from '../../../shared/model/types';
import { absolutePosition } from '../../../shared/model/queries';
import { useStore } from '../../store/store';
import * as A from '../../store/actions';
import {
  createPlacement,
  nestPlacement,
  placementGesture,
  snapPlacementToGrid,
  type PlacementKind,
} from '../creationGesture';
import { creationTarget } from '../creationTarget';

interface GestureStart {
  pointerId: number;
  clientX: number;
  clientY: number;
  flowX: number;
  flowY: number;
  kind: PlacementKind;
  shape: ShapeKind;
  containerId: string | null;
  toolLocked: boolean;
  gridSize: number | null;
}

export interface CreationPreview {
  left: number;
  top: number;
  width: number;
  height: number;
}

function placementKind(tool: Tool): PlacementKind | null {
  if (tool === 'shape' || tool === 'text' || tool === 'container') return tool;

  return null;
}

export function useObjectCreation(
  rootRef: RefObject<HTMLDivElement | null>,
): CreationPreview | null {
  const reactFlow = useReactFlow();
  const [preview, setPreview] = useState<CreationPreview | null>(null);
  const cleanupRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    const canvasRoot = root;

    function onPointerDown(event: PointerEvent): void {
      if (event.button !== 0 || !event.isPrimary) return;

      const state = useStore.getState();
      const kind = placementKind(state.session.tool);
      if (!kind) return;

      const target = event.target instanceof Element ? event.target : null;
      if (!target) return;

      const resolvedTarget = creationTarget(target, state.doc);
      if (!resolvedTarget) return;

      // Placement owns the sequence so frame/node drag cannot start underneath it.
      event.preventDefault();
      event.stopPropagation();

      const flowStart = reactFlow.screenToFlowPosition({ x: event.clientX, y: event.clientY });
      const start: GestureStart = {
        pointerId: event.pointerId,
        clientX: event.clientX,
        clientY: event.clientY,
        flowX: flowStart.x,
        flowY: flowStart.y,
        kind,
        shape: state.session.pendingShape,
        containerId: resolvedTarget.containerId,
        toolLocked: state.session.toolLocked,
        gridSize: state.doc.canvas.grid ? GRID_SIZE : null,
      };
      const rootBounds = canvasRoot.getBoundingClientRect();
      let animationFrame: number | null = null;
      let nextPreview: CreationPreview | null = null;

      function flushPreview(): void {
        animationFrame = null;
        if (!nextPreview) return;

        setPreview(nextPreview);
        nextPreview = null;
      }

      function onPointerMove(moveEvent: PointerEvent): void {
        if (moveEvent.pointerId !== start.pointerId) return;

        const flowEnd = reactFlow.screenToFlowPosition({
          x: moveEvent.clientX,
          y: moveEvent.clientY,
        });
        const gesture = placementGesture(
          { x: start.clientX, y: start.clientY },
          { x: moveEvent.clientX, y: moveEvent.clientY },
        );
        let placement = createPlacement(
          start.kind,
          { x: start.flowX, y: start.flowY },
          flowEnd,
          gesture,
        );
        if (start.gridSize) placement = snapPlacementToGrid(placement, gesture, start.gridSize);

        const state = useStore.getState();
        const nested = nestPlacement(state.doc, start.containerId, placement);
        const parent = nested.parentId
          ? state.doc.nodes.find((node) => node.id === nested.parentId)
          : undefined;
        const parentAbsolute = parent ? absolutePosition(state.doc, parent) : { x: 0, y: 0 };
        const topLeft = reactFlow.flowToScreenPosition({
          x: nested.x + parentAbsolute.x,
          y: nested.y + parentAbsolute.y,
        });
        const bottomRight = reactFlow.flowToScreenPosition({
          x: nested.x + parentAbsolute.x + nested.width,
          y: nested.y + parentAbsolute.y + nested.height,
        });
        nextPreview = {
          left: topLeft.x - rootBounds.left,
          top: topLeft.y - rootBounds.top,
          width: bottomRight.x - topLeft.x,
          height: bottomRight.y - topLeft.y,
        };
        if (animationFrame === null) animationFrame = requestAnimationFrame(flushPreview);
      }

      function cleanup(): void {
        window.removeEventListener('pointermove', onPointerMove);
        window.removeEventListener('pointerup', onPointerUp);
        window.removeEventListener('pointercancel', onPointerCancel);
        window.removeEventListener('keydown', onKeyDown);
        window.removeEventListener('blur', cleanup);
        if (animationFrame !== null) cancelAnimationFrame(animationFrame);
        animationFrame = null;
        nextPreview = null;
        cleanupRef.current = null;
        setPreview(null);
      }

      function onPointerUp(upEvent: PointerEvent): void {
        if (upEvent.pointerId !== start.pointerId) return;

        cleanup();
        const end = reactFlow.screenToFlowPosition({ x: upEvent.clientX, y: upEvent.clientY });
        const gesture = placementGesture(
          { x: start.clientX, y: start.clientY },
          { x: upEvent.clientX, y: upEvent.clientY },
        );
        let placement = createPlacement(
          start.kind,
          { x: start.flowX, y: start.flowY },
          end,
          gesture,
        );
        if (start.gridSize) {
          placement = snapPlacementToGrid(placement, gesture, start.gridSize);
        }
        const nested = nestPlacement(useStore.getState().doc, start.containerId, placement);
        const id = A.addNode({
          ...nested,
          kind: start.kind,
          ...(start.kind === 'shape' ? { shape: start.shape } : {}),
          ...(start.kind === 'container' ? { label: 'Group' } : {}),
          ...(start.kind === 'text' ? { label: '' } : {}),
        });

        if (start.kind === 'text' || start.kind === 'container') {
          A.setEditingLabel({ kind: 'node', id });
        }
        if (!start.toolLocked) A.setTool('select');
      }

      function onPointerCancel(cancelEvent: PointerEvent): void {
        if (cancelEvent.pointerId === start.pointerId) cleanup();
      }

      function onKeyDown(keyEvent: KeyboardEvent): void {
        if (keyEvent.code === 'Escape') cleanup();
      }

      cleanupRef.current?.();
      cleanupRef.current = cleanup;
      window.addEventListener('pointermove', onPointerMove);
      window.addEventListener('pointerup', onPointerUp);
      window.addEventListener('pointercancel', onPointerCancel);
      window.addEventListener('keydown', onKeyDown);
      window.addEventListener('blur', cleanup);
    }

    canvasRoot.addEventListener('pointerdown', onPointerDown, { capture: true });
    return () => {
      canvasRoot.removeEventListener('pointerdown', onPointerDown, { capture: true });
      cleanupRef.current?.();
    };
  }, [reactFlow, rootRef]);

  useEffect(() => {
    return useStore.subscribe((state, previous) => {
      if (state.doc !== previous.doc) cleanupRef.current?.();
    });
  }, []);

  return preview;
}
