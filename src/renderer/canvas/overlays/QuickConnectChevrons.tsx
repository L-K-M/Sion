/**
 * QuickConnectChevrons (PLAN.md §11.6): ViewportPortal overlay on the hovered
 * node — select tool only, zoom ≥ 40%, Q-toggleable, hidden while dragging or
 * editing. Clicking a chevron grows a connected node in that direction
 * (connects to an existing node in the corridor when one is there).
 */
import { memo, useEffect, useState } from 'react';
import { ViewportPortal, useStore as useRFStore } from '@xyflow/react';
import { useStore } from '../../store/store';
import * as A from '../../store/actions';
import { absolutePosition } from '../../../shared/model/queries';

// Flush with the node edge: the pointer travels node → chevron with NO
// pane pixels between, so hover tracking never drops the node. The chevron
// (portal renders above nodes, z-index 20) also overlays the connection
// handle cleanly — its pointerdown wins.
const CHEVRON_OFFSET = 0;

export const QuickConnectChevrons = memo(function QuickConnectChevrons() {
  const chevronsEnabled = useStore((s) => s.session.chevronsEnabled);
  const tool = useStore((s) => s.session.tool);
  const editing = useStore((s) => s.session.editingLabel);
  const doc = useStore((s) => s.doc);
  const selection = useStore((s) => s.session.selection);
  // Reactive zoom (re-renders on viewport change) instead of an imperative read.
  const zoom = useRFStore((s) => s.transform[2]);
  const [hoveredId, setHoveredId] = useState<string | null>(null);

  useEffect(() => {
    if (!chevronsEnabled || tool !== 'select' || editing) {
      setHoveredId(null);
      return;
    }
    const el = document.querySelector('.thalyx-canvas-root') as HTMLElement | null;
    if (!el) return;
    const onOver = (e: Event) => {
      const target = e.target as HTMLElement | null;
      // Moving onto one of the chevrons must NOT clear the hover they belong to.
      if (target?.closest?.('.thalyx-chevron')) return;
      const nodeEl = target?.closest?.('.react-flow__node');
      const id = nodeEl?.getAttribute('data-id') ?? null;
      setHoveredId(id);
    };
    const onOut = (e: Event) => {
      const target = e.target as HTMLElement | null;
      // Keep hover while the pointer moves onto a chevron (it belongs to the
      // hovered node) — only clear when leaving toward other canvas content.
      if (target?.closest?.('.thalyx-chevron')) return;
      if (!target?.closest?.('.react-flow__node')) setHoveredId(null);
    };
    el.addEventListener('mouseover', onOver);
    el.addEventListener('mouseout', onOut);
    return () => {
      el.removeEventListener('mouseover', onOver);
      el.removeEventListener('mouseout', onOut);
    };
  }, [chevronsEnabled, tool, editing]);

  if (!hoveredId || !chevronsEnabled || tool !== 'select' || editing) return null;
  if (zoom < 0.4) return null;

  const node = doc.nodes.find((n) => n.id === hoveredId);
  if (!node) return null;
  // Locked nodes can still be grown FROM (creating a new node doesn't move them)
  const abs = absolutePosition(doc, node);
  const isMermaid = node.kind === 'mermaid';
  if (isMermaid) return null;

  const chevrons: Array<{
    dir: 'n' | 's' | 'e' | 'w';
    x: number;
    y: number;
    glyph: string;
  }> = [
    { dir: 'n', x: abs.x + node.width / 2, y: abs.y - CHEVRON_OFFSET, glyph: '▲' },
    { dir: 's', x: abs.x + node.width / 2, y: abs.y + node.height + CHEVRON_OFFSET, glyph: '▼' },
    { dir: 'e', x: abs.x + node.width + CHEVRON_OFFSET, y: abs.y + node.height / 2, glyph: '▶' },
    { dir: 'w', x: abs.x - CHEVRON_OFFSET, y: abs.y + node.height / 2, glyph: '◀' },
  ];

  void selection;
  return (
    <ViewportPortal>
      {chevrons.map((c) => (
        <button
          key={c.dir}
          className="thalyx-chevron nodrag nopan"
          style={{
            left: c.x,
            top: c.y,
            fontSize: 9,
          }}
          title={`Grow ${c.dir === 'n' ? 'up' : c.dir === 's' ? 'down' : c.dir === 'e' ? 'right' : 'left'}`}
          onPointerDown={(e) => {
            e.stopPropagation();
            A.growConnectedNode(node.id, c.dir, { grid: doc.canvas.grid });
          }}
        >
          {c.glyph}
        </button>
      ))}
    </ViewportPortal>
  );
});
