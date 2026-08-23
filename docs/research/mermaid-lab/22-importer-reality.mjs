// Task 4 + §9.4 emit checks: subgraph nesting, direction, graph keyword, ids, @{shape}, asymmetric combos.
await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', htmlLabels: false, flowchart: { htmlLabels: false } });

async function parseIt(text) {
  const ok = await mermaid.parse(text, { suppressErrors: true });
  if (ok === false) {
    let msg = '';
    try { await mermaid.parse(text); } catch (e) { msg = String(e.message).split('\n').slice(0, 4).join(' | '); }
    return { err: msg };
  }
  const d = await mermaid.mermaidAPI.getDiagramFromText(text);
  return { d, parseRes: ok };
}

// A. Nested subgraphs: what exactly is in outer.nodes?
{
  const text = `flowchart TD
  subgraph Outer [Outer title]
    O1
    subgraph Inner [Inner title]
      I1
      I2
    end
    O2
  end
  X --> O1
`;
  const { d } = await parseIt(text);
  console.log('A. nested getSubGraphs():', JSON.stringify(d.db.getSubGraphs()));
  console.log('A. vertices keys:', JSON.stringify([...d.db.getVertices().keys()]));
}

// B. direction: TD vs TB, graph keyword, missing direction
for (const head of ['flowchart TD', 'flowchart TB', 'graph TD', 'graph LR', 'flowchart']) {
  const text = head + '\n  A --> B\n';
  const { d, err } = await parseIt(text);
  if (err) { console.log('B.', JSON.stringify({ head, err })); continue; }
  console.log('B.', JSON.stringify({ head, type: d.type, direction: d.db.getDirection() }));
}

// C. special ids: 'end', leading o/x fusing
for (const body of ['  end[The End]\n  A --> end', '  A --- oK', '  A --- xK', '  A --> oK', '  B --o K']) {
  const text = 'flowchart TD\n' + body + '\n';
  const { d, err } = await parseIt(text);
  if (err) { console.log('C.', JSON.stringify({ body, result: 'PARSE_ERROR', err: err.slice(0, 120) })); continue; }
  console.log('C.', JSON.stringify({ body, edges: d.db.getEdges().map(e => ({ start: e.start, end: e.end, type: e.type })), verts: [...d.db.getVertices().keys()] }));
}

// D. asymmetric arrowhead combos the exporter must NOT emit (plan says degrade)
for (const line of ['A o--> B', 'A x--> B', 'A <--o B', 'A <--x B', 'A o--x B']) {
  const text = 'flowchart TD\n  ' + line + '\n';
  const { d, err } = await parseIt(text);
  if (err) { console.log('D.', JSON.stringify({ line, result: 'PARSE_ERROR', err: err.slice(0, 100) })); continue; }
  const e = d.db.getEdges()[0];
  console.log('D.', JSON.stringify({ line, result: 'OK', start: e.start, end: e.end, type: e.type, stroke: e.stroke, verts: [...d.db.getVertices().keys()] }));
}

// E. @{ shape: ..., label: ... } syntax the exporter emits for unmapped shapes
for (const line of ['A@{ shape: cyl, label: "Disk store" }', 'A@{ shape: cyl, label: "has #quot;q#quot;" }', 'A@{ shape: notreal, label: "x" }']) {
  const text = 'flowchart TD\n  ' + line + '\n  A --> B\n';
  const { d, err } = await parseIt(text);
  if (err) { console.log('E.', JSON.stringify({ line, result: 'PARSE_ERROR', err: err.slice(0, 160) })); continue; }
  const v = d.db.getVertices().get('A');
  console.log('E.', JSON.stringify({ line, result: 'OK', type: v.type, text: v.text, labelType: v.labelType }));
}

// F. does getVertices include subgraph ids? (checked in A) — also: getClasses Map?, getTooltip
{
  const text = 'flowchart TD\n  A[Start]\n  click A "https://x.example" "tip"\n  classDef red fill:#f00\n  class A red\n';
  const { d } = await parseIt(text);
  console.log('F. getClasses is Map:', d.db.getClasses() instanceof Map, 'tooltip:', JSON.stringify(d.db.getTooltip('A')), 'vertex.link:', JSON.stringify(d.db.getVertices().get('A').link));
}

// G. parse() return shape (for §9.1 res.config)
{
  const r = await mermaid.parse('flowchart TD\n A --> B', { suppressErrors: true });
  console.log('G. parse result:', JSON.stringify(r));
}
