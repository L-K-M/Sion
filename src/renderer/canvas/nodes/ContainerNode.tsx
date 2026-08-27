/**
 * ContainerNode (PLAN.md §7.2/D5): a labeled frame. Children are React Flow
 * subflows (parentId + extent:'parent' set in rfSelectors).
 */
import { memo } from 'react';
import { NodeResizer, type NodeProps } from '@xyflow/react';
import type { ThalyxNode } from '../../../shared/model/types';
import type { ThalyxNodeData } from '../rfSelectors';
import { colorStyle } from '../../theme/colorStyle';
import { useStore } from '../../store/store';
import * as A from '../../store/actions';
import { LabelTextarea } from '../hooks/useLabelEditing';
import { ConnectionHandles } from './ConnectionHandles';
import { MIN_CONTAINER_HEIGHT, MIN_CONTAINER_WIDTH } from '../../../shared/model/nodeSizes';

export const ContainerNode = memo(function ContainerNode({
  data,
  selected,
  id,
  isConnectable,
}: NodeProps) {
  const node = (data as ThalyxNodeData).node as ThalyxNode;
  const editing = useStore((state) => state.session.editingLabel);
  return (
    <div
      className="thalyx-container"
      style={{
        width: '100%',
        height: '100%',
        position: 'relative',
        background: colorStyle(node.style.fill, 'fill'),
        // Containers stay see-through for children drawn above them.
        opacity: node.style.fill === 'transparent' ? 1 : undefined,
      }}
    >
      <NodeResizer
        isVisible={selected === true}
        minWidth={MIN_CONTAINER_WIDTH}
        minHeight={MIN_CONTAINER_HEIGHT}
        lineClassName="thalyx-resize-line"
        handleClassName="thalyx-resize-handle"
      />
      <ConnectionHandles isConnectable={isConnectable} />
      {editing?.kind === 'node' && editing.id === id ? (
        <LabelTextarea
          value={node.label}
          fontSize={node.style.fontSize}
          onCommit={(next) => {
            A.updateNodeLabel(id, next);
            A.setEditingLabel(null);
          }}
          onCancel={() => A.clearSelection()}
        />
      ) : (
        <div
          className="thalyx-container-title"
          style={{ color: colorStyle(node.style.stroke, 'text') }}
        >
          {node.label}
        </div>
      )}
    </div>
  );
});
