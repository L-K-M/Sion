/**
 * Connection handles (PLAN.md §11.2): React Flow Handles on all four sides
 * (id n/s/e/w) are the drag affordance and the persisted attachment.
 * Pinned anchors keep routes stable as either endpoint moves. One shared component for all node kinds.
 */
import { Handle, Position } from '@xyflow/react';

const HANDLE_SIDES = [
  { id: 'n', position: Position.Top },
  { id: 's', position: Position.Bottom },
  { id: 'e', position: Position.Right },
  { id: 'w', position: Position.Left },
] as const;

export function ConnectionHandles({ isConnectable }: { isConnectable: boolean }) {
  return (
    <>
      {HANDLE_SIDES.map(({ id, position }) => (
        <Handle
          key={id}
          id={id}
          type="source"
          position={position}
          className="thalyx-handle"
          isConnectable={isConnectable}
          isConnectableStart={isConnectable}
          isConnectableEnd={isConnectable}
        />
      ))}
    </>
  );
}
