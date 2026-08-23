// Test 4: every arrow variant + edge id + animation + getData() shape.
await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;

const text = `flowchart TD
  A --o B
  B --x C
  C <--> D
  D o--o E
  E x--x F
  F ~~~ G
  G ----> H
  H -..-> I
  I <==> J
  J e1@--> K
  A e2@==>|lbl| C
`;

await mermaid.parse(text);
const diagram = await mermaid.mermaidAPI.getDiagramFromText(text);
const db = diagram.db;
const edges = db.getEdges();
console.log('=== getEdges() (arrow variants) ===');
console.log(JSON.stringify(edges, null, 2));

// getData(): unified rendering data (nodes+edges pre-processed for layout)
console.log('\n=== getData() keys ===');
const data = db.getData();
console.log(Object.keys(data));
console.log('\n=== getData().nodes[0] ===');
console.log(JSON.stringify(data.nodes[0], null, 2));
console.log('\n=== getData().edges[0] ===');
console.log(JSON.stringify(data.edges[0], null, 2));
console.log('\n=== getData().config is big; direction:', data.direction, '===');
