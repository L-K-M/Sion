// Emit-grammar hazards: what a naive reading of PLAN §9.4 step 5 would produce.
await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', htmlLabels: false, flowchart: { htmlLabels: false } });

async function edge(line) {
  const text = 'flowchart TD\n  ' + line + '\n';
  let ok;
  try { ok = await mermaid.parse(text, { suppressErrors: true }); } catch (e) { return { line, result: 'THROWN', message: String(e.message).slice(0, 120) }; }
  if (ok === false) {
    let msg = '';
    try { await mermaid.parse(text); } catch (e) { msg = String(e.message).split('\n').slice(0, 3).join(' | '); }
    return { line, result: 'PARSE_ERROR', message: msg.slice(0, 130) };
  }
  const d = await mermaid.mermaidAPI.getDiagramFromText(text);
  return { line, result: 'OK', edges: d.db.getEdges().map(e => ({ start: e.start, end: e.end, type: e.type, stroke: e.stroke, length: e.length, id: e.id })) };
}

// 1. bases WITHOUT arrowhead — naive "base + nothing" for open edges
for (const l of ['A -- B', 'A == B', 'A -. B', 'A ~~ B']) console.log('1.', JSON.stringify(await edge(l)));

// 2. dotted extended with DASHES (naive "extra dashes") vs extra DOTS
for (const l of ['A -.--> B', 'A --.-> B', 'A -.-- B', 'A -...-> B', 'A -...- B']) console.log('2.', JSON.stringify(await edge(l)));

// 3. thick extended: extra equals (correct) — naive extra dashes
for (const l of ['A ==-> B', 'A --=> B']) console.log('3.', JSON.stringify(await edge(l)));

// 4. duplicate edges → occurrence ids (reconcile §9.6 occurrenceIndex assumption)
console.log('4.', JSON.stringify(await edge('A --> B\n  A --> B\n  A -->|x| B')));

// 5. click href form the exporter emits (§9.4 step 6)
{
  const text = 'flowchart TD\n  A[Start]\n  click A href "https://example.com" "tool tip"\n';
  const ok = await mermaid.parse(text, { suppressErrors: true });
  if (ok === false) {
    let msg = ''; try { await mermaid.parse(text); } catch (e) { msg = String(e.message).split('\n').slice(0, 3).join(' | '); }
    console.log('5.', JSON.stringify({ result: 'PARSE_ERROR', message: msg }));
  } else {
    const d = await mermaid.mermaidAPI.getDiagramFromText(text);
    console.log('5.', JSON.stringify({ result: 'OK', link: d.db.getVertices().get('A').link, tooltip: d.db.getTooltip('A') }));
  }
}

// 6. frontmatter passes through parse (§9.3 step 1)
{
  const text = '---\ntitle: Hello\n---\nflowchart LR\n  A --> B\n';
  const ok = await mermaid.parse(text, { suppressErrors: true });
  console.log('6.', JSON.stringify({ frontmatterParse: ok }));
}

// 7. label on invisible edge (exporter must not emit; check behavior anyway)
console.log('7.', JSON.stringify(await edge('A ~~~|ghost| B')));

// 8. no-space o/x fusing (why the id rule exists)
for (const l of ['A ---oK', 'A ---xK', 'B --oK', 'A --- ok[Okay]']) console.log('8.', JSON.stringify(await edge(l)));

// 9. what the CORRECT minlen emit looks like for each base (round-trip stability check)
//    minlen=2 should emit: '--->' (solid point), '----' (solid open), '-..->' (dotted point),
//    '-..-' (dotted open), '===>' (thick point), '====' (thick open), '~~~~' (invisible)
for (const l of ['A ---> B', 'A ---- B', 'A -..-> B', 'A -..- B', 'A ===> B', 'A ==== B', 'A ~~~~ B']) console.log('9.', JSON.stringify(await edge(l)));
