// Test 3: full flowchart db inspection WITH jsdom globals installed before import.
await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;

const text = `flowchart LR
  A[Start] --> B{"Decision #quot;quoted#quot;"}
  B -->|yes| C["a & b"]
  B -.->|no| D(Round)
  C ==> E[[Sub end]]
  D --text label--> E
  E --- F[(db)]
  A -.- G
  subgraph SG1 [Group One]
    C
    D
  end
  subgraph SG2
    direction TB
    E
    F
  end
  click A "https://example.com" "tooltip"
  style A fill:#f9f
  classDef red fill:#f00
  class B red
`;

const parseResult = await mermaid.parse(text);
console.log('mermaid.parse() result:', JSON.stringify(parseResult));

const diagram = await mermaid.mermaidAPI.getDiagramFromText(text);
console.log('diagram.type =', diagram.type);
const db = diagram.db;
console.log('db class:', db.constructor.name);
console.log('db proto methods:', Object.getOwnPropertyNames(Object.getPrototypeOf(db)).sort().join(', '));

const show = (name, v) => {
  console.log(`\n=== ${name} ===`);
  console.log(JSON.stringify(v instanceof Map ? Object.fromEntries(v) : v, null, 2));
};
show('getDirection()', db.getDirection());
const vertices = db.getVertices();
console.log('\ngetVertices() returns a', vertices?.constructor?.name);
show('getVertices()', vertices);
show('getEdges()', db.getEdges());
show('getSubGraphs()', db.getSubGraphs());
show('getClasses()', db.getClasses());
console.log('getTooltip("A"):', JSON.stringify(db.getTooltip('A')));
if (db.getLinks) show('getLinks()', db.getLinks());
