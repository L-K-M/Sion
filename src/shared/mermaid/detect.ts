/**
 * isProbablyMermaid (PLAN.md §9.7): cheap prefilter — final arbiter is
 * mermaid.parse. Skips frontmatter and leading %% comment/directive lines,
 * then requires a known diagram keyword header.
 */

const KEYWORDS = [
  'flowchart',
  'graph',
  'sequenceDiagram',
  'classDiagram',
  'stateDiagram',
  'stateDiagram-v2',
  'erDiagram',
  'gantt',
  'pie',
  'mindmap',
  'timeline',
  'gitGraph',
  'journey',
  'quadrantChart',
  'sankey',
  'xychart',
  'block',
  'kanban',
  'architecture',
  'packet',
  'radar',
  'treemap',
  'c4',
  'requirementDiagram',
  'c4Context',
];

export function isProbablyMermaid(text: string): boolean {
  const lines = text.split('\n');
  let i = 0;
  // optional frontmatter
  if (lines[0]?.trim() === '---') {
    const close = lines.findIndex((l, idx) => idx > 0 && l.trim() === '---');
    if (close !== -1) i = close + 1;
  }
  // skip leading %% comment/directive lines and blanks
  while (i < lines.length) {
    const t = lines[i]!.trim();
    if (t.length === 0 || t.startsWith('%%')) {
      i += 1;
      continue;
    }
    break;
  }
  const header = lines[i]?.trim() ?? '';
  const firstWord = header.split(/[\s(]/)[0] ?? '';
  return KEYWORDS.includes(firstWord);
}
