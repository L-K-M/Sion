// Test 6: state diagram (v2) db inspection.
await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;

const text = `stateDiagram-v2
  [*] --> Still
  Still --> [*]
  Still --> Moving : push & shove
  Moving --> Still
  Moving --> Crash
  Crash --> [*]
  state Composite {
    [*] --> Inner1
    Inner1 --> Inner2
  }
  state fork1 <<fork>>
  Moving --> fork1
  note right of Still : a note
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
show('getStates()', db.getStates());
show('getRelations()', db.getRelations());
if (db.getClasses) show('getClasses()', db.getClasses());
console.log('\n=== getData() nodes/edges summary ===');
const data = db.getData();
console.log('keys:', Object.keys(data));
console.log('nodes[1]:', JSON.stringify(data.nodes[1], null, 2));
console.log('edges[0]:', JSON.stringify(data.edges[0], null, 2));
