// Test 5: sequence diagram db inspection.
await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;

const text = `sequenceDiagram
  participant A as Alice
  actor B as Bob
  A->>B: Hello Bob & friends
  activate B
  B-->>A: Hi "Alice"
  deactivate B
  A-)B: async fire
  B--xA: fail
  loop Every day
    A->B: solid no arrow
  end
  Note right of A: A note here
  alt success
    A->>B: ok
  else failure
    A->>B: nope
  end
  par one
    A->>B: p1
  and two
    B->>A: p2
  end
`;

await mermaid.parse(text);
const diagram = await mermaid.mermaidAPI.getDiagramFromText(text);
const db = diagram.db;
console.log('diagram.type =', diagram.type);
console.log('db class:', db.constructor.name);
console.log('db proto methods:', Object.getOwnPropertyNames(Object.getPrototypeOf(db)).sort().join(', '));

const show = (name, v) => {
  console.log(`\n=== ${name} ===`);
  console.log(JSON.stringify(v instanceof Map ? Object.fromEntries(v) : v, null, 2));
};
show('getActors()', db.getActors());
show('getMessages()', db.getMessages());
if (db.getBoxes) show('getBoxes()', db.getBoxes());
if (db.getCreatedActors) show('getCreatedActors()', db.getCreatedActors());
// The numeric message `type` values map to LINETYPE constants:
if (db.LINETYPE) show('db.LINETYPE', db.LINETYPE);
