// Full §7.3 shape table check + keyword node ids + '&' escaping verification.
await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', htmlLabels: false, flowchart: { htmlLabels: false } });

const decodePlaceholders = (t) => t.replace(/ﬂ°°/g, '&#').replace(/ﬂ°/g, '&').replace(/¶ß/g, ';');

async function tryText(tag, text, dump) {
  let ok;
  try { ok = await mermaid.parse(text, { suppressErrors: true }); } catch (e) { console.log(tag, JSON.stringify({ result: 'THROWN', message: String(e.message).slice(0, 140) })); return; }
  if (ok === false) {
    let msg = '';
    try { await mermaid.parse(text); } catch (e) { msg = String(e.message).split('\n').slice(0, 3).join(' | '); }
    console.log(tag, JSON.stringify({ result: 'PARSE_ERROR', message: msg.slice(0, 130) }));
    return;
  }
  const d = await mermaid.mermaidAPI.getDiagramFromText(text);
  console.log(tag, JSON.stringify({ result: 'OK', ...dump(d.db) }));
}

// A. full shape bracket table (plan §7.3)
const shapes = [
  ['A[sq]', 'square'], ['A(rd)', 'round'], ['A([st])', 'stadium'], ['A((ci))', 'circle'],
  ['A(((dc)))', 'doublecircle'], ['A(-el-)', 'ellipse'], ['A{di}', 'diamond'], ['A{{hx}}', 'hexagon'],
  ['A[(cy)]', 'cylinder'], ['A[[sr]]', 'subroutine'], ['A[/lr/]', 'lean_right'], ['A[\\ll\\]', 'lean_left'],
  ['A[/tz\\]', 'trapezoid'], ['A[\\it/]', 'inv_trapezoid'], ['A>od]', 'odd'],
];
for (const [syntax, expected] of shapes) {
  await tryText('A. ' + syntax + ' expect=' + expected, 'flowchart TD\n  ' + syntax + '\n',
    (db) => { const v = db.getVertices().get('A'); return { type: v.type, text: v.text }; });
}

// B. keyword-ish node ids the exporter's CamelCase/label-derived ids could produce
for (const id of ['style', 'class', 'subgraph', 'direction', 'click', 'graph', 'flowchart', 'linkStyle', 'classDef', 'default', 'o', 'x']) {
  await tryText('B. id=' + id, 'flowchart TD\n  ' + id + '[Label]\n  Z --> ' + id + '\n',
    (db) => ({ verts: [...db.getVertices().keys()], edges: db.getEdges().map(e => e.start + '->' + e.end) }));
}

// C. '&' escaping: literal &quot; typed in source; #38; escape; bare & before entity-like text
await tryText('C. &quot;-literal', 'flowchart TD\n  A["say &quot;hi&quot;"]\n',
  (db) => { const v = db.getVertices().get('A'); return { rawText: v.text, decoded: decodePlaceholders(v.text) }; });
await tryText('C. #38;-escape', 'flowchart TD\n  A["5 #38;lt; 6"]\n',
  (db) => { const v = db.getVertices().get('A'); return { rawText: v.text, decoded: decodePlaceholders(v.text) }; });
await tryText('C. amp-hash', 'flowchart TD\n  A["a &#35; b"]\n',
  (db) => { const v = db.getVertices().get('A'); return { rawText: v.text, decoded: decodePlaceholders(v.text) }; });
