/**
 * ShapeNode (PLAN.md §7.3): <svg><path d={shapePath(...)}/></svg> + centered
 * label. Memoized; reads only its own data (perf doctrine §11.1).
 */
import { memo } from 'react';
import { NodeResizer, type NodeProps } from '@xyflow/react';
import { shapePath } from '../../../shared/geometry/shapes';
import type { ThalyxNode } from '../../../shared/model/types';
import type { ThalyxNodeData } from '../rfSelectors';
import { colorStyle } from '../../theme/colorStyle';
import { useStore } from '../../store/store';
import * as A from '../../store/actions';
import { LabelTextarea } from '../hooks/useLabelEditing';
import { ConnectionHandles } from './ConnectionHandles';

export const ShapeNode = memo(function ShapeNode({ data, selected, id }: NodeProps) {
  const node = (data as ThalyxNodeData).node as ThalyxNode;
  const lines = node.label.length > 0 ? node.label.split('\n') : [];
  return (
    <div
      className="thalyx-shape"
      style={{
        width: '100%',
        height: '100%',
        position: 'relative',
        color: colorStyle(node.style.fill, 'text'),
        fontSize: node.style.fontSize,
      }}
      data-shape={node.shape}
    >
      <NodeResizer
        isVisible={selected === true}
        minWidth={8}
        minHeight={8}
        lineClassName="thalyx-resize-line"
        handleClassName="thalyx-resize-handle"
      />
      <svg
        width="100%"
        height="100%"
        viewBox={`0 0 ${Math.max(1, node.width)} ${Math.max(1, node.height)}`}
        preserveAspectRatio="none"
        style={{ display: 'block', position: 'absolute', inset: 0 }}
      >
        <path
          d={shapePath(node.shape ?? 'rect', node.width, node.height)}
          fill={colorStyle(node.style.fill, 'fill')}
          stroke={colorStyle(node.style.stroke, 'stroke')}
          strokeWidth={node.style.strokeWidth}
          strokeLinejoin="round"
        />
      </svg>
      <ConnectionHandles />
      <NodeLabel id={id!} label={node.label} fontSize={node.style.fontSize} lines={lines} />
    </div>
  );
});

function NodeLabel({
  id,
  label,
  fontSize,
  lines,
}: {
  id: string;
  label: string;
  fontSize: number;
  lines: string[];
}) {
  const editing = useStore((st) => st.session.editingLabel);
  if (editing?.kind === 'node' && editing.id === id) {
    return (
      <LabelTextarea
        value={label}
        fontSize={fontSize}
        onCommit={(next) => {
          A.updateNodeLabel(id, next);
          A.setEditingLabel(null);
        }}
        onCancel={() => A.clearSelection()}
      />
    );
  }
  return (
    <div className="thalyx-node-label">
      {lines.map((line, i) => (
        <div key={i}>{line}</div>
      ))}
    </div>
  );
}
