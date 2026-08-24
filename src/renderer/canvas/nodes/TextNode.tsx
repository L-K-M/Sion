/**
 * TextNode: borderless text element. Memoized; own data only (§11.1).
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

export const TextNode = memo(function TextNode({ data, selected, id }: NodeProps) {
  const node = (data as ThalyxNodeData).node as ThalyxNode;
  const lines = node.label.length > 0 ? node.label.split('\n') : [];
  const editing = useStore((st) => st.session.editingLabel);
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
      <ConnectionHandles />
      {editing?.kind === 'node' && editing.id === id ? (
        <LabelTextarea
          value={node.label}
          fontSize={node.style.fontSize}
          onCommit={(next) => A.updateNodeLabel(id, next)}
          onCancel={() => A.clearSelection()}
        />
      ) : (
        <div className="thalyx-node-label">
          {lines.map((line, i) => (
            <div key={i}>{line}</div>
          ))}
        </div>
      )}
    </div>
  );
});
