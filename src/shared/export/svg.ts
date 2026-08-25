/**
 * renderDocToSvg (PLAN.md §13.1): pure function from the model — canvas and
 * export share geometry by construction. No CSS classes, no foreignObject.
 */
import { shapePath } from '../geometry/shapes';
import { absolutePosition, boundsOfNodes } from '../model/queries';
import { edgeEndpoints } from '../geometry/anchors';
import { pointAtT, route } from '../geometry/elbow';
import type { ThalyxDoc, ThalyxNode } from '../model/types';

export interface RenderSvgOptions {
  selectionOnly?: boolean;
  background: 'light' | 'dark' | 'transparent';
  padding?: number;
  islandSvgs?: Record<string, string>;
}

const THEME_BG: Record<'light' | 'dark', string> = { light: '#ffffff', dark: '#14161a' };

function esc(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/** Character-width estimate for Inter line breaking (§13.1). */
function charWidth(fontSize: number): number {
  return fontSize * 0.54; // Inter average advance
}

function breakLines(label: string, maxWidth: number, fontSize: number): string[] {
  const lines: string[] = [];
  for (const raw of label.split('\n')) {
    let current = '';
    for (const word of raw.split(/(\s+)/)) {
      const candidate = current + word;
      if (candidate.length * charWidth(fontSize) > maxWidth && current.trim().length > 0) {
        lines.push(current);
        current = word.trimStart();
      } else {
        current = candidate;
      }
    }
    lines.push(current);
  }
  return lines;
}

export function renderDocToSvg(doc: ThalyxDoc, opts: RenderSvgOptions): string {
  const padding = opts.padding ?? 16;
  const nodes = doc.nodes.filter((n) => !n.hidden);
  let edges = doc.edges;
  if (opts.selectionOnly) {
    // caller passes selection via a wrapper doc; selectionOnly handled upstream
    void nodes;
    void edges;
  }

  const include = new Set(nodes.map((n) => n.id));
  edges = edges.filter((e) => include.has(e.source) && include.has(e.target) && !e.hidden);

  const bounds = boundsOfNodes(doc, nodes);
  if (!bounds) {
    const w = 2 * padding;
    const h = 2 * padding;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}"></svg>`;
  }

  const minX = bounds.x - padding;
  const minY = bounds.y - padding;
  const w = bounds.width + padding * 2;
  const h = bounds.height + padding * 2;

  const parts: string[] = [];
  parts.push(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${minX} ${minY} ${w} ${h}" width="${w}" height="${h}">`,
  );
  if (opts.background !== 'transparent') {
    parts.push(
      `<rect x="${minX}" y="${minY}" width="${w}" height="${h}" fill="${THEME_BG[opts.background]}"/>`,
    );
  }
  parts.push(`<defs>`);
  // markers per arrowhead/color
  const markerDefs = new Set<string>();
  for (const e of edges) {
    for (const [head, end] of [
      [e.arrowStart, 'start'],
      [e.arrowEnd, 'end'],
    ] as const) {
      if (head === 'none') continue;
      const key = `${head}-${e.style.stroke}-${end}`;
      if (markerDefs.has(key)) continue;
      markerDefs.add(key);
      const color = e.style.stroke; // token/hex — hex renders directly; tokens map below
      const paint = color.startsWith('#') ? color : '#495057'; // token fallback
      const body =
        head === 'arrow'
          ? `<path d="M 0 2 L 7 4 L 0 6 Z" fill="${paint}"/>`
          : head === 'circle'
            ? `<circle cx="3.5" cy="4" r="3" fill="${paint}"/>`
            : `<path d="M 0 0 L 7 4 L 0 8 M 7 0 L 0 4 L 7 8" stroke="${paint}" stroke-width="1.5" fill="none"/>`;
      const orient = end === 'end' ? 'auto' : 'auto-start-reverse';
      parts.push(
        `<marker id="mk-${key}" viewBox="0 0 8 8" markerWidth="8" markerHeight="8" refX="${end === 'end' ? 6.5 : 1}" refY="4" orient="${orient}" markerUnits="userSpaceOnUse">${body}</marker>`,
      );
    }
  }
  parts.push(`</defs>`);

  const zOrder = [...nodes].sort((a, b) => {
    // containers (back) first, then z-order = array order
    const rank = (n: ThalyxNode) => (n.kind === 'container' ? 0 : 1);
    return rank(a) - rank(b);
  });

  // containers + nodes
  for (const node of zOrder) {
    const abs = absolutePosition(doc, node);
    if (node.kind === 'container') {
      parts.push(
        `<rect x="${abs.x}" y="${abs.y}" width="${node.width}" height="${node.height}" rx="8" fill="none" stroke="#8888" stroke-dasharray="6 4"/>`,
      );
      parts.push(
        `<text x="${abs.x + 10}" y="${abs.y + 18}" font-family="Inter, system-ui, sans-serif" font-size="12" fill="#888">${esc(node.label)}</text>`,
      );
      continue;
    }
    if (node.kind === 'mermaid') {
      const island = opts.islandSvgs?.[node.id];
      if (island) {
        // embed the caller-provided sanitized SVG at the island bounds
        const inner = island.replace(/^<svg[^>]*>|<\/svg>$/g, '');
        parts.push(
          `<svg x="${abs.x}" y="${abs.y}" width="${node.width}" height="${node.height}" viewBox="0 0 ${node.width} ${node.height}" preserveAspectRatio="xMidYMid meet">${inner}</svg>`,
        );
      } else {
        parts.push(
          `<rect x="${abs.x}" y="${abs.y}" width="${node.width}" height="${node.height}" rx="8" fill="#f0f0f0" stroke="#999"/>`,
          `<text x="${abs.x + node.width / 2}" y="${abs.y + node.height / 2}" text-anchor="middle" font-family="Inter, system-ui, sans-serif" font-size="12" fill="#666">Mermaid island</text>`,
        );
      }
      continue;
    }
    // shape/text
    if (node.kind === 'text') {
      const lines = breakLines(node.label, node.width, node.style.fontSize);
      const lh = node.style.fontSize * 1.25;
      const y0 = abs.y + node.height / 2 - ((lines.length - 1) * lh) / 2;
      lines.forEach((line, i) => {
        parts.push(
          `<text x="${abs.x + node.width / 2}" y="${y0 + i * lh + node.style.fontSize * 0.35}" text-anchor="middle" font-family="Inter, system-ui, sans-serif" font-size="${node.style.fontSize}" fill="#1f2328">${esc(line)}</text>`,
        );
      });
      continue;
    }
    const fill = node.style.fill.startsWith('#') ? node.style.fill : '#ffffff';
    const stroke = node.style.stroke.startsWith('#') ? node.style.stroke : '#343a40';
    parts.push(
      `<path d="${shapePath(node.shape ?? 'rect', node.width, node.height)}" transform="translate(${abs.x} ${abs.y})" fill="${fill}" stroke="${stroke}" stroke-width="${node.style.strokeWidth}" stroke-linejoin="round"/>`,
    );
    const lines = breakLines(node.label, node.width - 12, node.style.fontSize);
    const lh = node.style.fontSize * 1.25;
    const y0 = abs.y + node.height / 2 - ((lines.length - 1) * lh) / 2;
    lines.forEach((line, i) => {
      parts.push(
        `<text x="${abs.x + node.width / 2}" y="${y0 + i * lh + node.style.fontSize * 0.35}" text-anchor="middle" font-family="Inter, system-ui, sans-serif" font-size="${node.style.fontSize}" fill="#1f2328">${esc(line)}</text>`,
      );
    });
  }

  // edges above nodes
  for (const e of edges) {
    const src = doc.nodes.find((n) => n.id === e.source)!;
    const tgt = doc.nodes.find((n) => n.id === e.target)!;
    const srcAbs = absolutePosition(doc, src);
    const tgtAbs = absolutePosition(doc, tgt);
    const { source, target, sourceSide, targetSide } = edgeEndpoints(
      src,
      srcAbs,
      tgt,
      tgtAbs,
      e.sourceAnchor,
      e.targetAnchor,
    );
    const pts =
      e.waypoints && e.waypoints.length > 0
        ? [source, ...e.waypoints, target]
        : e.kind === 'elbow'
          ? route(
              source,
              target,
              { x: srcAbs.x, y: srcAbs.y, width: src.width, height: src.height },
              { x: tgtAbs.x, y: tgtAbs.y, width: tgt.width, height: tgt.height },
              sourceSide,
              targetSide,
            )
          : [source, target];
    const d = pts.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ');
    const stroke = e.style.stroke.startsWith('#') ? e.style.stroke : '#1f2328';
    const dash = e.style.line === 'dashed' ? ' stroke-dasharray="6 4"' : '';
    const width = e.style.line === 'thick' ? 4 : 2;
    const mk = (head: string, end: 'start' | 'end') =>
      head === 'none' ? '' : ` marker-${end}="url(#mk-${head}-${e.style.stroke}-${end})"`;
    parts.push(
      `<path d="${d}" fill="none" stroke="${stroke}" stroke-width="${width}"${dash}${mk(e.arrowStart, 'start')}${mk(e.arrowEnd, 'end')}/>`,
    );
    if (e.label) {
      const p = pointAtT(pts, e.labelT ?? 0.5);
      parts.push(
        `<rect x="${p.x - e.label.length * 3.4 - 4}" y="${p.y - 9}" width="${e.label.length * 6.8 + 8}" height="18" rx="3" fill="${THEME_BG[opts.background === 'transparent' ? 'light' : opts.background]}"/>`,
        `<text x="${p.x}" y="${p.y + 4}" text-anchor="middle" font-family="Inter, system-ui, sans-serif" font-size="12" fill="#1f2328">${esc(e.label)}</text>`,
      );
    }
  }

  parts.push('</svg>');
  return parts.join('\n');
}
