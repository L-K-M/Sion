import { JSDOM } from 'jsdom';
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', { url: 'https://localhost/' });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
const mermaid = (await import('mermaid')).default;

export async function extract(text) {
  const ok = await mermaid.parse(text, { suppressErrors: true });
  if (ok === false) return { ok: false };
  const diagram = await mermaid.mermaidAPI.getDiagramFromText(text);
  const db = diagram.db;
  switch (diagram.type) {
    case 'flowchart-v2': return { ok: true, type: diagram.type,
      direction: db.getDirection(),
      vertices: Object.fromEntries(db.getVertices()),
      edges: db.getEdges(), subGraphs: db.getSubGraphs(),
      classes: Object.fromEntries(db.getClasses()) };
    case 'sequence': return { ok: true, type: diagram.type,
      actors: Object.fromEntries(db.getActors()), messages: db.getMessages(),
      boxes: db.getBoxes() };
    case 'stateDiagram': return { ok: true, type: diagram.type,
      data: db.getData(), relations: db.getRelations() };
    default: return { ok: true, type: diagram.type, db };
  }
}

// self-test
const r1 = await extract('flowchart TD\n A[Hi] -->|go| B{Q}');
console.log('flowchart ok:', r1.ok, '| verts:', Object.keys(r1.vertices).join(','), '| edge0:', r1.edges[0].start, '->', r1.edges[0].end, r1.edges[0].text);
const r2 = await extract('sequenceDiagram\n A->>B: hey');
console.log('sequence ok:', r2.ok, '| msg0:', JSON.stringify(r2.messages[0]));
const r3 = await extract('stateDiagram-v2\n [*] --> S1');
console.log('state ok:', r3.ok, '| rel0:', JSON.stringify(r3.relations[0]));
const r4 = await extract('flowchart TD\n A --> --> B');
console.log('invalid ok flag:', r4.ok);
