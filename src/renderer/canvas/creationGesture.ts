import type { Point } from '../../shared/geometry/anchors';
import { absolutePosition } from '../../shared/model/queries';
import type { ThalyxDoc } from '../../shared/model/types';
import { MIN_CONTAINER_HEIGHT, MIN_CONTAINER_WIDTH } from '../../shared/model/nodeSizes';

export type PlacementKind = 'shape' | 'text' | 'container';

export const DEFAULT_CONTAINER_HEIGHT = 200;

const MIN_DRAG_DISTANCE = 4;

export enum PlacementGesture {
  Click = 'click',
  Drag = 'drag',
}

const MIN_DRAWN_SIZE: Record<PlacementKind, { width: number; height: number }> = {
  shape: { width: 16, height: 16 },
  text: { width: 32, height: 24 },
  container: { width: MIN_CONTAINER_WIDTH, height: MIN_CONTAINER_HEIGHT },
};

const DEFAULT_SIZE: Record<PlacementKind, { width: number; height: number }> = {
  shape: { width: 160, height: 64 },
  text: { width: 160, height: 32 },
  container: { width: 320, height: DEFAULT_CONTAINER_HEIGHT },
};

export interface Placement {
  x: number;
  y: number;
  width: number;
  height: number;
}

export function placementGesture(start: Point, end: Point): PlacementGesture {
  return Math.hypot(end.x - start.x, end.y - start.y) < MIN_DRAG_DISTANCE
    ? PlacementGesture.Click
    : PlacementGesture.Drag;
}

export function createPlacement(
  kind: PlacementKind,
  start: Point,
  end: Point,
  gesture: PlacementGesture,
): Placement {
  const dx = end.x - start.x;
  const dy = end.y - start.y;

  if (gesture === PlacementGesture.Click) {
    const size = DEFAULT_SIZE[kind];
    return {
      x: Math.round(start.x - size.width / 2),
      y: Math.round(start.y - size.height / 2),
      ...size,
    };
  }

  return {
    x: Math.round(Math.min(start.x, end.x)),
    y: Math.round(Math.min(start.y, end.y)),
    width: Math.round(Math.max(MIN_DRAWN_SIZE[kind].width, Math.abs(dx))),
    height: Math.round(Math.max(MIN_DRAWN_SIZE[kind].height, Math.abs(dy))),
  };
}

export function snapPlacementToGrid(
  placement: Placement,
  gesture: PlacementGesture,
  gridSize: number,
): Placement {
  if (gesture === PlacementGesture.Click) {
    const centerX = placement.x + placement.width / 2;
    const centerY = placement.y + placement.height / 2;
    return {
      ...placement,
      x: Math.round(centerX / gridSize) * gridSize - placement.width / 2,
      y: Math.round(centerY / gridSize) * gridSize - placement.height / 2,
    };
  }

  const left = Math.round(placement.x / gridSize) * gridSize;
  const top = Math.round(placement.y / gridSize) * gridSize;
  const right = Math.round((placement.x + placement.width) / gridSize) * gridSize;
  const bottom = Math.round((placement.y + placement.height) / gridSize) * gridSize;
  return {
    x: left,
    y: top,
    width: Math.max(gridSize, right - left),
    height: Math.max(gridSize, bottom - top),
  };
}

export interface NestedPlacement extends Placement {
  parentId?: string;
}

export function nestPlacement(
  doc: ThalyxDoc,
  containerId: string | null,
  placement: Placement,
): NestedPlacement {
  if (!containerId) return placement;

  const container = doc.nodes.find((node) => node.id === containerId);
  if (!container || container.kind !== 'container') return placement;

  const absolute = absolutePosition(doc, container);
  const width = Math.min(placement.width, container.width);
  const height = Math.min(placement.height, container.height);
  const x = Math.min(Math.max(placement.x - absolute.x, 0), container.width - width);
  const y = Math.min(Math.max(placement.y - absolute.y, 0), container.height - height);

  return { x, y, width, height, parentId: container.id };
}
