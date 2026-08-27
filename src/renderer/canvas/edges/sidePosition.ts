import { Position } from '@xyflow/react';
import type { Side } from '../../../shared/geometry/anchors';

const SIDE_POSITION: Record<Side, Position> = {
  n: Position.Top,
  s: Position.Bottom,
  e: Position.Right,
  w: Position.Left,
};

export function sidePosition(side: Side): Position {
  return SIDE_POSITION[side];
}
