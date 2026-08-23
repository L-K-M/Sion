/**
 * Toolbar (PLAN.md §6 left tool strip; M2 subset): select/hand tools, the
 * five toolbar shapes (§3: rect, rounded, ellipse, diamond, cylinder), text,
 * grid toggle, theme toggle. Full keymap + more tools land in M4; arrows in M3.
 */
import { useCallback } from 'react';
import { useStore } from '../store/store';
import * as A from '../store/actions';
import { shapePath } from '../../shared/geometry/shapes';
import type { ShapeKind, Tool } from '../../shared/model/types';
import { useEffectiveTheme } from '../theme/useEffectiveTheme';

const TOOLBUTTONS: Array<{ tool: Tool; label: string; title: string; key?: string }> = [
  { tool: 'select', label: '⌖', title: 'Select (V)', key: 'V' },
  { tool: 'hand', label: '✋', title: 'Hand (H) — or hold Space', key: 'H' },
  { tool: 'arrow', label: '→', title: 'Arrow connector (A)', key: 'A' },
  { tool: 'line', label: '—', title: 'Line, no arrowheads (L)', key: 'L' },
];

const SHAPES: Array<{ shape: ShapeKind; label: string; title: string }> = [
  { shape: 'rect', label: '▭', title: 'Rectangle (R)' },
  { shape: 'rounded', label: '▢', title: 'Rounded rectangle' },
  { shape: 'ellipse', label: '◯', title: 'Ellipse (O)' },
  { shape: 'diamond', label: '◇', title: 'Diamond (D)' },
  { shape: 'cylinder', label: '⬮', title: 'Cylinder' },
];

export function Toolbar() {
  const tool = useStore((s) => s.session.tool);
  const pendingShape = useStore((s) => s.session.pendingShape);
  const grid = useStore((s) => s.doc.canvas.grid);
  const themeSetting = useStore((s) => s.session.theme);
  const theme = useEffectiveTheme();

  const pickTool = useCallback((t: Tool) => {
    A.setTool(t);
  }, []);

  const pickShape = useCallback((shape: ShapeKind) => {
    A.setPendingShape(shape);
    A.setTool('shape');
  }, []);

  const cycleTheme = useCallback(() => {
    // system → light → dark → system (§10.1 delta 5)
    const next = themeSetting === 'system' ? 'light' : themeSetting === 'light' ? 'dark' : 'system';
    A.setTheme(next);
  }, [themeSetting]);

  return (
    <div className="thalyx-toolbar" role="toolbar" aria-label="Canvas tools">
      {TOOLBUTTONS.map((b) => (
        <button
          key={b.tool}
          className={`thalyx-toolbtn${tool === b.tool ? ' is-active' : ''}`}
          title={b.title}
          aria-pressed={tool === b.tool}
          onClick={() => pickTool(b.tool)}
        >
          {b.label}
        </button>
      ))}
      <div className="thalyx-toolbar-sep" role="separator" />
      {SHAPES.map((s) => (
        <button
          key={s.shape}
          className={`thalyx-toolbtn${tool === 'shape' && pendingShape === s.shape ? ' is-active' : ''}`}
          title={s.title}
          aria-pressed={tool === 'shape' && pendingShape === s.shape}
          onClick={() => pickShape(s.shape)}
        >
          <svg width="20" height="20" viewBox="0 0 20 20" aria-hidden>
            <path
              d={shapePath(s.shape, 20, 20)}
              fill="none"
              stroke="currentColor"
              strokeWidth="1.5"
            />
          </svg>
        </button>
      ))}
      <div className="thalyx-toolbar-sep" role="separator" />
      <button
        className="thalyx-toolbtn"
        title="Text (T)"
        onClick={() => pickTool('text')}
        aria-pressed={tool === 'text'}
      >
        <span style={{ fontWeight: 700 }}>T</span>
      </button>
      <button
        className={`thalyx-toolbtn${grid ? ' is-active' : ''}`}
        title="Toggle grid"
        aria-pressed={grid}
        onClick={() => A.toggleGrid()}
      >
        #
      </button>
      <button className="thalyx-toolbtn" title={`Theme: ${themeSetting}`} onClick={cycleTheme}>
        {theme === 'dark' ? '☾' : '☀'}
      </button>
    </div>
  );
}
