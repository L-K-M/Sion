/**
 * shapePath(kind, w, h) → SVG path data for every ShapeKind (PLAN.md §7.3).
 *
 * Pure function, shared by the canvas node components AND renderDocToSvg —
 * canvas and export share geometry by construction. All shapes are centered
 * in a (0,0,w,h) box (top-left origin).
 */
import type { ShapeKind } from '../model/types';

/** Fixed skew fraction for parallelogram/trapezoid family (§7.3: 0.2·w). */
const SKEW = 0.2;

/** Corner radius for the 'rounded' kind (scaled with size, capped). */
export function roundedRadius(w: number, h: number): number {
  return Math.min(w, h) * 0.2;
}

function round(value: number): number {
  // Trim float noise so path data is stable for snapshot tests.
  return Math.round(value * 100) / 100;
}

function ellipsePath(cx: number, cy: number, rx: number, ry: number): string {
  // A path-based ellipse (two arcs) — composable with other segments.
  return [
    `M ${round(cx - rx)} ${round(cy)}`,
    `A ${round(rx)} ${round(ry)} 0 1 0 ${round(cx + rx)} ${round(cy)}`,
    `A ${round(rx)} ${round(ry)} 0 1 0 ${round(cx - rx)} ${round(cy)}`,
    'Z',
  ].join(' ');
}

export function shapePath(kind: ShapeKind, w: number, h: number): string {
  const W = Math.max(0, w);
  const H = Math.max(0, h);
  switch (kind) {
    case 'rect':
      return `M 0 0 H ${round(W)} V ${round(H)} H 0 Z`;

    case 'rounded': {
      const r = Math.min(roundedRadius(W, H), W / 2, H / 2);
      return [
        `M ${round(r)} 0`,
        `H ${round(W - r)}`,
        `A ${round(r)} ${round(r)} 0 0 1 ${round(W)} ${round(r)}`,
        `V ${round(H - r)}`,
        `A ${round(r)} ${round(r)} 0 0 1 ${round(W - r)} ${round(H)}`,
        `H ${round(r)}`,
        `A ${round(r)} ${round(r)} 0 0 1 0 ${round(H - r)}`,
        `V ${round(r)}`,
        `A ${round(r)} ${round(r)} 0 0 1 ${round(r)} 0`,
        'Z',
      ].join(' ');
    }

    case 'ellipse':
      return ellipsePath(W / 2, H / 2, W / 2, H / 2);

    case 'circle': {
      // A circle node keeps a square bounding box; use the inscribed circle.
      const r = Math.min(W, H) / 2;
      return ellipsePath(W / 2, H / 2, r, r);
    }

    case 'doublecircle': {
      // Two concentric ellipses joined as one path (outer + inner).
      const cx = W / 2;
      const cy = H / 2;
      const rx = W / 2;
      const ry = H / 2;
      const irx = rx * 0.78;
      const iry = ry * 0.78;
      return `${ellipsePath(cx, cy, rx, ry)} ${ellipsePath(cx, cy, irx, iry)}`;
    }

    case 'diamond':
      return [
        `M ${round(W / 2)} 0`,
        `L ${round(W)} ${round(H / 2)}`,
        `L ${round(W / 2)} ${round(H)}`,
        `L 0 ${round(H / 2)}`,
        'Z',
      ].join(' ');

    case 'cylinder': {
      // Body + top/bottom ellipse caps (mermaid database shape).
      const ry = Math.min(H * 0.125, W * 0.2);
      const top = ry;
      const bottom = H - ry;
      return [
        `M 0 ${round(top)}`,
        `A ${round(W / 2)} ${round(ry)} 0 0 1 ${round(W)} ${round(top)}`,
        `L ${round(W)} ${round(bottom)}`,
        `A ${round(W / 2)} ${round(ry)} 0 0 1 0 ${round(bottom)}`,
        'Z',
      ].join(' ');
    }

    case 'stadium': {
      // Fully-rounded sides ("pill"): two semicircular caps, closed outline.
      // Wide boxes cap top/bottom; tall boxes (H > W) cap left/right.
      const r = Math.min(W, H) / 2;
      if (H > W) {
        return [
          `M 0 ${round(r)}`,
          `V ${round(H - r)}`,
          `A ${round(r)} ${round(r)} 0 0 1 ${round(W)} ${round(H - r)}`,
          `V ${round(r)}`,
          `A ${round(r)} ${round(r)} 0 0 1 0 ${round(r)}`,
          'Z',
        ].join(' ');
      }
      return [
        `M ${round(r)} 0`,
        `H ${round(W - r)}`,
        `A ${round(r)} ${round(r)} 0 0 1 ${round(W - r)} ${round(H)}`,
        `H ${round(r)}`,
        `A ${round(r)} ${round(r)} 0 0 1 ${round(r)} 0`,
        'Z',
      ].join(' ');
    }

    case 'subroutine': {
      // Rectangle with two vertical division lines (joined as one path).
      const inset = Math.max(6, W * 0.1);
      return [
        `M 0 0 H ${round(W)} V ${round(H)} H 0 Z`,
        `M ${round(inset)} 0 V ${round(H)}`,
        `M ${round(W - inset)} 0 V ${round(H)}`,
      ].join(' ');
    }

    case 'hexagon': {
      const c = Math.min(W * 0.15, H / 2);
      return [
        `M ${round(c)} 0`,
        `H ${round(W - c)}`,
        `L ${round(W)} ${round(H / 2)}`,
        `L ${round(W - c)} ${round(H)}`,
        `H ${round(c)}`,
        `L 0 ${round(H / 2)}`,
        'Z',
      ].join(' ');
    }

    case 'parallelogram': {
      const dx = W * SKEW;
      return [
        `M ${round(dx)} 0`,
        `H ${round(W)}`,
        `L ${round(W - dx)} ${round(H)}`,
        `H 0`,
        'Z',
      ].join(' ');
    }

    case 'parallelogram-alt': {
      const dx = W * SKEW;
      return [
        `M 0 0`,
        `H ${round(W - dx)}`,
        `L ${round(W)} ${round(H)}`,
        `H ${round(dx)}`,
        'Z',
      ].join(' ');
    }

    case 'trapezoid': {
      const dx = W * SKEW;
      return [
        `M ${round(dx)} 0`,
        `H ${round(W - dx)}`,
        `L ${round(W)} ${round(H)}`,
        `H 0`,
        'Z',
      ].join(' ');
    }

    case 'trapezoid-alt': {
      const dx = W * SKEW;
      return [
        `M 0 0`,
        `H ${round(W)}`,
        `L ${round(W - dx)} ${round(H)}`,
        `H ${round(dx)}`,
        'Z',
      ].join(' ');
    }

    case 'asymmetric': {
      // Mermaid 'odd' shape: a flag with a pointed right edge.
      const dx = W * SKEW;
      return [
        `M 0 0`,
        `H ${round(W - dx)}`,
        `L ${round(W)} ${round(H / 2)}`,
        `L ${round(W - dx)} ${round(H)}`,
        `H 0`,
        'Z',
      ].join(' ');
    }

    default: {
      // Exhaustiveness guard — a new ShapeKind must be handled here.
      const _never: never = kind;
      void _never;
      return `M 0 0 H ${round(W)} V ${round(H)} H 0 Z`;
    }
  }
}

/**
 * Vertex boundary intersection for floating anchors (PLAN.md §11.2):
 * rect/ellipse/diamond analytic; other shapes use their bounding rect.
 * `from` is a point in the shape's LOCAL box coordinates (top-left origin)
 * that the boundary is aimed at — typically the other node's center.
 */
export function shapeBoundaryIntersection(
  kind: ShapeKind,
  w: number,
  h: number,
  from: { x: number; y: number },
): { x: number; y: number } {
  const cx = w / 2;
  const cy = h / 2;
  const dx = from.x - cx;
  const dy = from.y - cy;
  // Degenerate aim (target center): every boundary point is equally valid;
  // pick the top-center so callers get a finite, stable point.
  if (dx === 0 && dy === 0) return { x: cx, y: 0 };
  switch (kind) {
    case 'ellipse':
    case 'circle':
    case 'doublecircle':
    case 'stadium': {
      // Scale the aim ray onto the unit circle, then onto the ellipse.
      const rx = w / 2;
      const ry = h / 2;
      const t = 1 / Math.hypot(dx / rx, dy / ry);
      return { x: cx + dx * t, y: cy + dy * t };
    }
    case 'diamond': {
      // |x|/rx + |y|/ry = 1
      const rx = w / 2;
      const ry = h / 2;
      const t = 1 / (Math.abs(dx) / rx + Math.abs(dy) / ry);
      return { x: cx + dx * t, y: cy + dy * t };
    }
    default: {
      // Bounding rect: scale the aim ray onto the rect border.
      const sx = dx === 0 ? Infinity : cx / Math.abs(dx);
      const sy = dy === 0 ? Infinity : cy / Math.abs(dy);
      const t = Math.min(sx, sy);
      return { x: cx + dx * (t === Infinity ? 0 : t), y: cy + dy * (t === Infinity ? 0 : t) };
    }
  }
}
