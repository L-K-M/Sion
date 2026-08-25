/**
 * ContextPanel (PLAN.md §10.3): ONE floating panel, left-docked, showing only
 * what applies to the current selection. Segmented controls for ≤5 options —
 * no dropdowns (except the shape popup with the full §7.3 set). Max ~8 visible
 * controls; nothing nests.
 */
import { memo, useCallback } from 'react';
import { useStore } from '../store/store';
import * as A from '../store/actions';
import {
  ARROW_HEADS,
  SHAPE_KINDS,
  type ArrowHead,
  type EdgeKind,
  type ShapeKind,
} from '../../shared/model/types';
import { PALETTE_TOKENS } from '../theme/palette';
import { useEffectiveTheme } from '../theme/useEffectiveTheme';

const SEG = 'thalyx-seg';
const SEGGROUP = 'thalyx-seg-group';

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="thalyx-panel-row">
      <span className="thalyx-panel-label">{label}</span>
      <div className="thalyx-panel-control">{children}</div>
    </div>
  );
}

function Segmented<T extends string | number>({
  value,
  options,
  onChange,
  title,
}: {
  value: T;
  options: Array<{ value: T; label: string; title?: string }>;
  onChange: (v: T) => void;
  title?: string;
}) {
  return (
    <div className={SEGGROUP} role="group" aria-label={title}>
      {options.map((o) => (
        <button
          key={String(o.value)}
          className={SEG}
          aria-pressed={o.value === value}
          title={o.title ?? o.label}
          onClick={() => onChange(o.value)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

const ToolbarShapes: ShapeKind[] = ['rect', 'rounded', 'ellipse', 'diamond', 'cylinder'];

export const ContextPanel = memo(function ContextPanel() {
  const selection = useStore((s) => s.session.selection);
  const doc = useStore((s) => s.doc);
  const themeSetting = useStore((s) => s.session.theme);
  const theme = useEffectiveTheme();

  const nodes = doc.nodes.filter((n) => selection.nodeIds.includes(n.id));
  const edges = doc.edges.filter((e) => selection.edgeIds.includes(e.id));
  const shapeNodes = nodes.filter((n) => n.kind === 'shape');
  const containers = nodes.filter((n) => n.kind === 'container');

  const onFill = useCallback(
    (fill: string) => A.updateNodesStyle(selection.nodeIds, { fill }),
    [selection.nodeIds],
  );
  const onStrokeWidth = useCallback(
    (strokeWidth: 1 | 2 | 4) => A.updateNodesStyle(selection.nodeIds, { strokeWidth }),
    [selection.nodeIds],
  );
  const onFontSize = useCallback(
    (fontSize: 12 | 14 | 18 | 24) => A.updateNodesStyle(selection.nodeIds, { fontSize }),
    [selection.nodeIds],
  );

  const singleShape = shapeNodes.length === 1 ? shapeNodes[0] : undefined;
  const singleEdge = edges.length === 1 ? edges[0] : undefined;

  // ---- nothing selected: canvas controls --------------------------------
  if (nodes.length === 0 && edges.length === 0) {
    return (
      <aside className="thalyx-panel" aria-label="Canvas properties">
        <div className="thalyx-panel-title">Canvas</div>
        <Row label="Grid">
          <Segmented
            value={doc.canvas.grid ? 'on' : 'off'}
            options={[
              { value: 'off', label: 'Off' },
              { value: 'on', label: 'On' },
            ]}
            onChange={(v) => A.setCanvas({ grid: v === 'on' })}
            title="Grid"
          />
        </Row>
        <Row label="Theme">
          <Segmented
            value={themeSetting}
            options={[
              { value: 'system', label: 'Auto' },
              { value: 'light', label: 'Light' },
              { value: 'dark', label: 'Dark' },
            ]}
            onChange={(v) => A.setTheme(v)}
            title={`Theme (currently ${theme})`}
          />
        </Row>
        <Row label="Direction">
          <Segmented
            value={doc.meta.mermaid?.direction ?? 'TB'}
            options={[
              { value: 'TB', label: '↓' },
              { value: 'BT', label: '↑' },
              { value: 'LR', label: '→' },
              { value: 'RL', label: '←' },
            ]}
            onChange={(v) => A.setDirection(v)}
            title="Flow direction (Mermaid)"
          />
        </Row>
      </aside>
    );
  }

  // ---- edge(s) selected --------------------------------------------------
  if (edges.length > 0 && nodes.length === 0) {
    const line = edges[0]?.style.line ?? 'solid';
    const kind = edges[0]?.kind ?? 'elbow';
    return (
      <aside className="thalyx-panel" aria-label="Connector properties">
        <div className="thalyx-panel-title">
          {edges.length === 1 ? 'Connector' : `${edges.length} connectors`}
        </div>
        <Row label="Line">
          <Segmented
            value={line}
            options={[
              { value: 'solid', label: '——' },
              { value: 'dashed', label: '– –' },
              { value: 'thick', label: '━' },
            ]}
            onChange={(v) => {
              for (const e of edges) A.updateEdge(e.id, { style: { ...e.style, line: v } });
            }}
            title="Line"
          />
        </Row>
        <Row label="Route">
          <Segmented
            value={kind}
            options={[
              { value: 'elbow', label: '⌐' },
              { value: 'straight', label: '╱' },
              { value: 'curved', label: '︵' },
            ]}
            onChange={(v: EdgeKind) => {
              for (const e of edges) A.updateEdge(e.id, { kind: v });
            }}
            title="Route"
          />
        </Row>
        <Row label="Start">
          <Segmented
            value={edges[0]?.arrowStart ?? 'none'}
            options={ARROW_HEADS.map((h: ArrowHead) => ({ value: h, label: arrowLabel(h) }))}
            onChange={(v: ArrowHead) => {
              for (const e of edges) A.updateEdge(e.id, { arrowStart: v });
            }}
            title="Start arrowhead"
          />
        </Row>
        <Row label="End">
          <Segmented
            value={edges[0]?.arrowEnd ?? 'arrow'}
            options={ARROW_HEADS.map((h: ArrowHead) => ({ value: h, label: arrowLabel(h) }))}
            onChange={(v: ArrowHead) => {
              for (const e of edges) A.updateEdge(e.id, { arrowEnd: v });
            }}
            title="End arrowhead"
          />
        </Row>
        {singleEdge ? (
          <Row label="Label">
            <input
              key={`${singleEdge.id}:${singleEdge.label ?? ''}`}
              className="thalyx-panel-input"
              defaultValue={singleEdge.label ?? ''}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && e.currentTarget.value !== (singleEdge.label ?? '')) {
                  A.updateEdge(singleEdge.id, { label: e.currentTarget.value });
                }
              }}
              onBlur={(e) => {
                if (e.currentTarget.value !== (singleEdge.label ?? '')) {
                  A.updateEdge(singleEdge.id, { label: e.currentTarget.value });
                }
              }}
              placeholder="edge label"
            />
          </Row>
        ) : null}
      </aside>
    );
  }

  // ---- node(s) selected ---------------------------------------------------
  return (
    <aside className="thalyx-panel" aria-label="Selection properties">
      <div className="thalyx-panel-title">
        {nodes.length === 1
          ? nodes[0]!.kind === 'container'
            ? 'Container'
            : nodes[0]!.kind === 'text'
              ? 'Text'
              : 'Shape'
          : `${nodes.length} nodes`}
      </div>

      <Row label="Fill">
        <div className="thalyx-palette" role="group" aria-label="Fill color">
          {PALETTE_TOKENS.map((t) => (
            <button
              key={t}
              className={`thalyx-swatch${nodes[0]?.style.fill === t ? ' is-active' : ''}`}
              style={{ background: `var(--${t}-fill)` }}
              title={t}
              aria-pressed={nodes[0]?.style.fill === t}
              onClick={() => onFill(t)}
            />
          ))}
          <label className="thalyx-swatch thalyx-swatch-custom" title="Custom (hex)">
            <input
              type="color"
              value={
                /^#[0-9a-fA-F]{6}$/.test(nodes[0]?.style.fill ?? '')
                  ? nodes[0]!.style.fill
                  : '#888888'
              }
              onChange={(e) => onFill(e.target.value)}
              aria-label="Custom fill color"
            />
          </label>
        </div>
      </Row>

      {nodes.length > 0 ? (
        <>
          <Row label="Stroke">
            <Segmented
              value={(shapeNodes[0] ?? nodes[0])!.style.strokeWidth}
              options={[
                { value: 1, label: '·', title: 'Thin' },
                { value: 2, label: '▪', title: 'Medium' },
                { value: 4, label: '■', title: 'Bold' },
              ]}
              onChange={onStrokeWidth}
              title="Stroke width"
            />
          </Row>
          <Row label="Font">
            <Segmented
              value={(shapeNodes[0] ?? nodes[0])!.style.fontSize}
              options={[
                { value: 12, label: 'S' },
                { value: 14, label: 'M' },
                { value: 18, label: 'L' },
                { value: 24, label: 'XL' },
              ]}
              onChange={onFontSize}
              title="Font size"
            />
          </Row>
        </>
      ) : null}

      {singleShape ? (
        <>
          {singleShape.shape === 'rect' || singleShape.shape === 'rounded' ? (
            <Row label="Corners">
              <Segmented
                value={singleShape.shape}
                options={[
                  { value: 'rect', label: 'Sharper', title: 'Sharp corners' },
                  { value: 'rounded', label: 'Round', title: 'Rounded corners' },
                ]}
                onChange={(v) => A.setNodeShape(singleShape.id, v)}
              />
            </Row>
          ) : null}
          <Row label="Shape">
            <select
              className="thalyx-panel-select"
              value={singleShape.shape}
              onChange={(e) => A.setNodeShape(singleShape.id, e.target.value as ShapeKind)}
              aria-label="Swap shape"
            >
              {SHAPE_KINDS.map((k) => (
                <option key={k} value={k}>
                  {k}
                  {ToolbarShapes.includes(k) ? ' ★' : ''}
                </option>
              ))}
            </select>
          </Row>
          <Row label="Link">
            <input
              key={`${singleShape.id}:${singleShape.meta?.mermaid?.link ?? ''}`}
              className="thalyx-panel-input"
              defaultValue={singleShape.meta?.mermaid?.link ?? ''}
              placeholder="https://…"
              onKeyDown={(e) => {
                if (
                  e.key === 'Enter' &&
                  e.currentTarget.value !== (singleShape.meta?.mermaid?.link ?? '')
                ) {
                  A.setNodeLink(singleShape.id, e.currentTarget.value);
                }
              }}
              onBlur={(e) => {
                if (e.currentTarget.value !== (singleShape.meta?.mermaid?.link ?? '')) {
                  A.setNodeLink(singleShape.id, e.currentTarget.value);
                }
              }}
            />
          </Row>
        </>
      ) : null}

      {nodes.length === 1 ? (
        <Row label="Lock">
          <Segmented
            value={nodes[0]!.locked ? 'locked' : 'free'}
            options={[
              { value: 'free', label: 'Editable' },
              { value: 'locked', label: '🔒' },
            ]}
            onChange={(v) => A.setNodesLocked([nodes[0]!.id], v === 'locked')}
          />
        </Row>
      ) : null}

      {nodes.length >= 2 ? (
        <Row label="Align">
          <div className={SEGGROUP}>
            {(
              [
                ['left', '⇤'],
                ['hcenter', '↔'],
                ['right', '⇥'],
                ['top', '⇧'],
                ['vcenter', '↕'],
                ['bottom', '⇩'],
              ] as const
            ).map(([edge, label]) => (
              <button
                key={edge}
                className={SEG}
                title={`Align ${edge}`}
                onClick={() => A.alignSelection(edge)}
              >
                {label}
              </button>
            ))}
          </div>
        </Row>
      ) : null}
      {containers.length > 0 && nodes.length === 1 && containers[0] === nodes[0] ? null : null}
    </aside>
  );
});

function arrowLabel(h: ArrowHead): string {
  switch (h) {
    case 'none':
      return '—';
    case 'arrow':
      return '→';
    case 'circle':
      return '●';
    case 'cross':
      return '✕';
  }
}
