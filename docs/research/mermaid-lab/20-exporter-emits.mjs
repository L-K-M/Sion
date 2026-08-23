// Task 2: verify every syntax the PLAN.md §9.4 step 5 exporter could emit.
// Each snippet is parsed in isolation (fresh text) so one failure doesn't hide others.
await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;

const cases = [
  // thick-open base + minlen extension
  'A === B',
  'A ==== B',
  // thick-point with minlen
  'A ===> B',
  // dotted with circle/cross heads
  'A -.-o B',
  'A -.-x B',
  // thick with circle/cross heads
  'A ==o B',
  'A ==x B',
  // double-sided dotted / thick
  'A <-.-> B',
  'A <==> B',
  // dotted minlen point
  'A -..-> B',
  // solid minlen with label
  'A --->|lbl| B',
  // invisible
  'A ~~~ B',
  // edge id with thick arrow
  'A e1@==> B',
  // extras the exporter might also emit per the plan's table-inversion rule:
  'A o-.-o B',   // double circle dotted
  'A x-.-x B',   // double cross dotted
  'A o==o B',    // double circle thick
  'A x==x B',    // double cross thick
  'A --- B',     // open solid (baseline sanity)
  'A ---- B',    // open solid minlen
  'A -.- B',     // open dotted baseline
  'A -..- B',    // open dotted minlen
  'A ~~~~ B',    // invisible minlen? (4 tildes)
  'A e1@--- B',  // edge id on open link
  'A e1@~~~ B',  // edge id on invisible link
];

for (const line of cases) {
  const text = 'flowchart TD\n  ' + line + '\n';
  let res;
  try {
    res = await mermaid.parse(text, { suppressErrors: true });
  } catch (e) {
    console.log(JSON.stringify({ syntax: line, result: 'THROWN', message: String(e.message).slice(0, 120) }));
    continue;
  }
  if (res === false) {
    // re-parse without suppression to capture the error message
    let msg = '';
    try { await mermaid.parse(text); } catch (e) { msg = String(e.message).split('\n').slice(0, 3).join(' | '); }
    console.log(JSON.stringify({ syntax: line, result: 'PARSE_ERROR', message: msg.slice(0, 160) }));
    continue;
  }
  const diagram = await mermaid.mermaidAPI.getDiagramFromText(text);
  const e = diagram.db.getEdges()[0];
  console.log(JSON.stringify({
    syntax: line, result: 'OK',
    type: e.type, stroke: e.stroke, length: e.length, id: e.id, isUserDefinedId: e.isUserDefinedId, text: e.text,
  }));
}
