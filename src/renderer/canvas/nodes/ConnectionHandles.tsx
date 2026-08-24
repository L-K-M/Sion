/**
 * Connection handles (PLAN.md §11.2): React Flow Handles on all four sides
 * (id n/s/e/w) are the drag AFFORDANCE; the model always stores 'auto'
 * (floating attachment). One shared component for all node kinds.
 */
import { Handle, Position } from '@xyflow/react';

export const HANDLE_SIDES = [
  { id: 'n', position: Position.Top },
  { id: 's', position: Position.Bottom },
  { id: 'e', position: Position.Right },
  { id: 'w', position: Position.Left },
] as const;

export function ConnectionHandles() {
  return (
    <>
      {HANDLE_SIDES.map(({ id, position }) => (
        <Handle
          key={id}
          id={id}
          type="source"
          position={position}
          className="thalyx-handle"
          isConnectableStart
          isConnectableEnd
        />
      ))}
    </>
  );
}
