/**
 * ContainerNode (PLAN.md §7.2/D5): a labeled frame. Children are React Flow
 * subflows (parentId + extent:'parent' set in rfSelectors).
 */
import { memo } from 'react';
import { NodeResizer, type NodeProps } from '@xyflow/react';
import type { ThalyxNode } from '../../../shared/model/types';
import type { ThalyxNodeData } from '../rfSelectors';
import { colorStyle } from '../../theme/colorStyle';
import { ConnectionHandles } from './ConnectionHandles';

export const ContainerNode = memo(function ContainerNode({ data, selected }: NodeProps) {
  const node = (data as ThalyxNodeData).node as ThalyxNode;
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
        minWidth={8}
        minHeight={8}
        lineClassName="thalyx-resize-line"
        handleClassName="thalyx-resize-handle"
      />
      <ConnectionHandles />
      <div
        className="thalyx-container-title"
        style={{ color: colorStyle(node.style.stroke, 'text') }}
      >
        {node.label}
      </div>
    </div>
  );
});
