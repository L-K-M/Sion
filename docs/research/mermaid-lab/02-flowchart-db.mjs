// Test 2: getDiagramFromText + db inspection for a flowchart with subgraphs,
// special-char labels, and varied arrow types. NO jsdom shims.
import mermaid from 'mermaid';

const text = `flowchart LR
  A[Start] --> B{Decision "quoted"}
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

// WORKAROUND TEST: getDiagramFromText alone throws UnknownDiagramError because
// lazy-loaded diagram detectors are only registered via mermaid.parse()/render().
// Calling mermaid.parse() first loads them.
await mermaid.parse(text);
const diagram = await mermaid.mermaidAPI.getDiagramFromText(text);
console.log('=== diagram.type ===');
console.log(diagram.type);
console.log('=== db method names ===');
console.log(Object.getOwnPropertyNames(Object.getPrototypeOf(diagram.db)).sort().join(', '));
console.log('own props:', Object.keys(diagram.db).sort().join(', '));

const db = diagram.db;
const show = (name, v) => {
  console.log(`\n=== ${name} ===`);
  console.log(JSON.stringify(v instanceof Map ? Object.fromEntries(v) : v, null, 2));
};

show('getDirection()', db.getDirection());
const vertices = db.getVertices();
console.log('\nvertices is a', vertices?.constructor?.name);
show('getVertices()', vertices);
show('getEdges()', db.getEdges());
show('getSubGraphs()', db.getSubGraphs());
if (db.getClasses) show('getClasses()', db.getClasses());
if (db.getTooltip) console.log('\ngetTooltip("A"):', db.getTooltip('A'));
