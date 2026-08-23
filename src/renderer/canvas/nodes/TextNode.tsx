/**
 * TextNode: borderless text element. Memoized; own data only (§11.1).
 */
import { memo } from 'react';
import { NodeResizer, type NodeProps } from '@xyflow/react';
import type { ThalyxNode } from '../../../shared/model/types';
import type { ThalyxNodeData } from '../rfSelectors';
import { colorStyle } from '../../theme/colorStyle';

export const TextNode = memo(function TextNode({ data, selected }: NodeProps) {
  const node = (data as ThalyxNodeData).node as ThalyxNode;
  const lines = node.label.length > 0 ? node.label.split('\n') : [];
  return (
    <div
      className="thalyx-text-node"
      style={{
        width: '100%',
        height: '100%',
        position: 'relative',
        color: colorStyle(node.style.stroke, 'text'), // text nodes use ink color
        fontSize: node.style.fontSize,
      }}
    >
      <NodeResizer
        isVisible={selected === true}
        minWidth={8}
        minHeight={8}
        lineClassName="thalyx-resize-line"
        handleClassName="thalyx-resize-handle"
      />
      <div className="thalyx-node-label" style={{ whiteSpace: 'pre' }}>
        {lines.map((line, i) => (
          <div key={i}>{line}</div>
        ))}
      </div>
    </div>
  );
});
