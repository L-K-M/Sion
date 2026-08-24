/**
 * Smart-guide overlay (PLAN.md §11.4): renders session.guides as thin
 * full-viewport lines + gap chips inside React Flow's coordinate space.
 */
import { ViewportPortal } from '@xyflow/react';
import { useStore } from '../../store/store';

export function GuideLines() {
  const guides = useStore((s) => s.session.guides);
  if (guides.length === 0) return null;
  return (
    <ViewportPortal>
      {guides.map((g, i) =>
        g.axis === 'x' ? (
          <div
            key={i}
            className="thalyx-guide thalyx-guide-x"
            style={{ left: g.position, top: g.start, height: Math.max(1, g.end - g.start) }}
          >
            {g.kind === 'gap' && g.label ? (
              <span className="thalyx-guide-chip">{g.label}</span>
            ) : null}
          </div>
        ) : (
          <div
            key={i}
            className="thalyx-guide thalyx-guide-y"
            style={{ top: g.position, left: g.start, width: Math.max(1, g.end - g.start) }}
          >
            {g.kind === 'gap' && g.label ? (
              <span className="thalyx-guide-chip">{g.label}</span>
            ) : null}
          </div>
        ),
      )}
    </ViewportPortal>
  );
}
