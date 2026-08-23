// Test 11: class diagram + ER diagram db shapes (bonus beyond task minimum).
await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;

const show = (name, v) => {
  console.log(`\n=== ${name} ===`);
  console.log(JSON.stringify(v instanceof Map ? Object.fromEntries(v) : v, null, 2));
};

// --- class diagram ---
const classText = `classDiagram
  class Animal {
    +String name
    +eat() void
  }
  class Dog
  Animal <|-- Dog : inherits
  Animal "1" o-- "many" Toy
`;
await mermaid.parse(classText);
const cd = await mermaid.mermaidAPI.getDiagramFromText(classText);
console.log('class diagram type =', cd.type, '| db:', cd.db.constructor.name);
console.log('methods:', Object.getOwnPropertyNames(Object.getPrototypeOf(cd.db)).filter(m => m.startsWith('get')).sort().join(', '));
show('classDb.getClasses()', cd.db.getClasses());
show('classDb.getRelations()', cd.db.getRelations());

// --- ER diagram ---
const erText = `erDiagram
  CUSTOMER ||--o{ ORDER : places
  ORDER {
    int id PK
    string note
  }
`;
await mermaid.parse(erText);
const er = await mermaid.mermaidAPI.getDiagramFromText(erText);
console.log('\nER diagram type =', er.type, '| db:', er.db.constructor.name);
console.log('methods:', Object.getOwnPropertyNames(Object.getPrototypeOf(er.db)).filter(m => m.startsWith('get')).sort().join(', '));
show('erDb.getEntities()', er.db.getEntities());
show('erDb.getRelationships()', er.db.getRelationships());
