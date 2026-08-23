# Thalyx

A cross-platform (macOS + Linux) desktop diagramming tool in the spirit of OmniGraffle, with a
ruthless focus on **simple, fast, user-friendly UX** — and with **Mermaid as a first-class
citizen**:

- **Paste or open Mermaid text** and it becomes a fully editable diagram (flowcharts convert to
  native shapes and connectors; every other Mermaid diagram type renders as a live, text-editable
  "island").
- **Export the logical structure of any diagram back to clean, idiomatic Mermaid** — the graph
  (nodes, edges, labels, containers) is always a first-class model, so Mermaid export is pure
  serialization, never inference.
- **Native high-fidelity drag-and-drop editing**: real shapes, elbow connectors that never
  detach, smart alignment guides, keyboard-driven diagram growth, one-shot auto-layout, dark
  mode, SVG/PNG/PDF export.

## Status

**Planning complete, implementation not started.** The full implementation plan — researched,
decision-complete, and written to be executed milestone-by-milestone — is in
[**PLAN.md**](PLAN.md). The research behind it (desktop shell evaluation, canvas library
evaluation, hands-on verification of the Mermaid API, UX pattern catalog, persistence
architecture) is in [`docs/research/`](docs/research/).

Planned stack (see PLAN.md §2 for the reasoning): Electron · React · TypeScript ·
React Flow (`@xyflow/react`) · zustand · mermaid (pinned) · `@dagrejs/dagre` · vitest ·
Playwright.

## License

Thalyx's own code is dedicated to the public domain under the [Unlicense](LICENSE).
Bundled dependencies keep their own permissive licenses (see PLAN.md §4 for the dependency
licensing policy).
