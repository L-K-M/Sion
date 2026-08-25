/**
 * Mermaid label entity decode/encode (PLAN.md §9.2, verified out-21/24).
 *
 * CRITICAL: mermaid surfaces #quot; etc. in db text as internal placeholders.
 * Decode does: (1) placeholder decode, (2) EXACTLY ONE html-entity pass,
 * (3) <br> → '\n'. Encode: order matters (# first, then &, then ", then \n).
 */

const HTML_ENTITIES: Record<string, string> = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  apos: "'",
  nbsp: '\u00a0',
};

function decodeHtmlEntityOnce(s: string): string {
  return s.replace(/&(?:#x([0-9a-fA-F]+)|#(\d+)|([a-zA-Z]+));/g, (m, hex, dec, name) => {
    if (hex) return String.fromCodePoint(parseInt(hex, 16));
    if (dec) return String.fromCodePoint(parseInt(dec, 10));
    if (name && HTML_ENTITIES[name]) return HTML_ENTITIES[name]!;
    return m; // unknown entity left verbatim
  });
}

/**
 * db `text` → Thalyx label. ONE entity pass — a recursive decoder would
 * re-break '&amp;lt;'.
 */
export function decodeMermaidLabel(t: string): string {
  return decodeHtmlEntityOnce(
    t
      .replace(/\uFB02\u00B0\u00B0/g, '&#')
      .replace(/\uFB02\u00B0/g, '&')
      .replace(/\u00C2\u00A7\u00DF/g, ';')
      // Some builds use the ligature 'ﬂ°' pair; also cover the composed form.
      .replace(/ﬂ°°/g, '&#')
      .replace(/ﬂ°/g, '&')
      .replace(/¶ß/g, ';'),
  ).replace(/<br\s*\/?>/gi, '\n');
}

/** Thalyx label → quoted mermaid label token (§9.4 escaping, order matters). */
export function encodeLabel(s: string): string {
  const inner = s
    .replace(/#/g, '#35;')
    .replace(/&/g, '#38;')
    .replace(/"/g, '#quot;')
    .replace(/\n/g, '<br>');
  return `"${inner}"`;
}

/** Unencoded label for `|lbl|` edge position or titles — same escaping. */
export const encodeEdgeLabel = encodeLabel;
