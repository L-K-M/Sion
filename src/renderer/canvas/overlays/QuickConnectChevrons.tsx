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

// 16px out: clears the 10px connection Handle that sits ON the edge (a
// flush chevron would be un-clickable — the handle consumes pointerdown).
// Hover tracking tolerates the pane gap (see the listeners below).
const CHEVRON_OFFSET = 16;

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
    // Hover model: entering a node sets hover; entering a chevron or empty
    // pane KEEPS it (no flicker while reaching for a chevron); hover clears
    // only when the pointer enters a DIFFERENT node or leaves the canvas.
    const onOver = (e: Event) => {
      const target = e.target as HTMLElement | null;
      const nodeEl = target?.closest?.('.react-flow__node');
      if (nodeEl) {
        const id = nodeEl.getAttribute('data-id');
        if (id) setHoveredId(id);
      }
      // pane/chevron targets: keep the current hover
    };
    const onLeave = () => setHoveredId(null);
    el.addEventListener('mouseover', onOver);
    el.addEventListener('mouseleave', onLeave);
    return () => {
      el.removeEventListener('mouseover', onOver);
      el.removeEventListener('mouseleave', onLeave);
    };
  }, [chevronsEnabled, tool, editing]);

  // RF's store doesn't expose a drag flag; track it via pointer events on the
  // canvas root (a mousedown on a node starts a potential drag).
  const [pointerDown, setPointerDown] = useState(false);
  useEffect(() => {
    const el = document.querySelector('.thalyx-canvas-root');
    if (!el) return;
    const cancel = () => setPointerDown(false);
    const down = (e: Event) => {
      const target = e.target as HTMLElement | null;
      // A potential node DRAG starts on a node — not on overlay buttons
      // (clicking a chevron must not hide the chevrons mid-click).
      if (target?.closest?.('.react-flow__node')) setPointerDown(true);
    };
    const up = () => setPointerDown(false);
    el.addEventListener('pointerdown', down);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', cancel);
    window.addEventListener('pointerout', (e: Event) => {
      // pointer leaving the window entirely clears hover
      if (!(e as PointerEvent).relatedTarget) setHoveredId(null);
    });
    return () => {
      el.removeEventListener('pointerdown', down);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', cancel);
    };
  }, []);
  if (!hoveredId || !chevronsEnabled || tool !== 'select' || editing || pointerDown) return null;
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
            if (e.button !== 0) return; // primary only
            e.stopPropagation();
            A.growConnectedNode(node.id, c.dir, { grid: doc.canvas.grid });
          }}
          onKeyDown={(e) => {
            if (e.key === 'Enter' || e.key === ' ') {
              e.preventDefault();
              A.growConnectedNode(node.id, c.dir, { grid: doc.canvas.grid });
            }
          }}
        >
          {c.glyph}
        </button>
      ))}
    </ViewportPortal>
  );
});
