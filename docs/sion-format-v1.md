# Sion document format v1

Status: implementation contract. Normative words such as MUST and SHOULD use
their RFC 2119 meanings.

Normative JSON Schemas: [`scene.json`](schema/scene-v1.schema.json) and
[`manifest.json`](schema/manifest-v1.schema.json).

## Goals

A `.sion` file is both an editable document and a recovery kit. A user without
Sion can unzip it, recover original assets, open a standalone SVG, and inspect
the diagram as Mermaid text. The current scene remains the only editable source
of truth.

The uniform type identifier is `ch.lkmc.sion.document`. The media type is
`application/vnd.lkmc.sion+zip`.

## Container

The file is a ZIP archive with this layout:

```text
drawing.sion
├── mimetype                         required, first entry
├── manifest.json                    required
├── scene.json                       required, authoritative
├── assets/<sha256>.<extension>      current/history originals
├── exports/diagram.svg              required, self-contained
├── exports/diagram.mmd              required, possibly partial
├── previews/preview.png             optional cached preview
├── history/index.json               optional, rebuildable
├── history/<utc>-<hash>.scene.json  retained canonical snapshots
└── README.txt                       required recovery instructions
```

`mimetype` MUST contain exactly `application/vnd.lkmc.sion+zip`, without a
newline. V1 writers use the ZIP STORED method for every entry. They fix ZIP
timestamps to 1980-01-01, emit no comments or extra fields, and use UTF-8 paths.
This sacrifices compression for deterministic, dependency-free recovery; image
assets are already compressed.

Entry order is the order above. Repeated families are sorted by path.

### Authority

- `scene.json` and assets referenced by its current scene are authoritative.
- Assets referenced only by retained history are derived with those snapshots.
- SVG, PNG, Mermaid, the history index, and README are derived.
- A corrupt current scene or referenced asset MUST block normal editing.
- A corrupt derived entry MAY be ignored and regenerated.
- Sion MUST NOT silently reconstruct a current scene from an export.
- Recovery from a valid history scene is an explicit user action and MUST save
  to a new file before replacing the damaged original.

## Manifest

`manifest.json` identifies both container and scene versions and hashes every
meaningful entry:

```json
{
  "format": "sion-document",
  "formatVersion": 1,
  "generator": { "name": "Sion", "version": "0.1.0" },
  "writtenAt": "2026-08-27T14:35:22Z",
  "scene": {
    "path": "scene.json",
    "schemaVersion": 1,
    "bytes": 18422,
    "sha256": "64-lowercase-hex"
  },
  "entries": [
    {
      "path": "assets/64-lowercase-hex.png",
      "role": "authoritative",
      "mediaType": "image/png",
      "bytes": 48219,
      "sha256": "64-lowercase-hex"
    },
    {
      "path": "exports/diagram.svg",
      "role": "derived",
      "mediaType": "image/svg+xml",
      "bytes": 9214,
      "sha256": "64-lowercase-hex"
    }
  ],
  "mermaidCoverage": "partial"
}
```

Roles are `authoritative` and `derived`. Mermaid coverage is `complete`,
`partial`, or `none`. SHA-256 detects accidental corruption, not hostile
rewriting; v1 has no signature or encryption.

## Scene

`scene.json` is UTF-8 JSON with sorted keys, two-space indentation, and one
trailing newline. It contains:

```json
{
  "format": "sion-scene",
  "schemaVersion": 1,
  "id": "c0a8012e-78ee-4b4f-9c06-2c52f655cb10",
  "title": "Service map",
  "scene": {
    "canvas": {
      "background": { "red": 0.965, "green": 0.969, "blue": 0.976, "alpha": 1 },
      "extent": { "type": "infinite" },
      "grid": { "spacing": 16, "subdivisions": 1, "visibility": "hidden" }
    },
    "elements": [],
    "extensions": {}
  },
  "assets": [],
  "extensions": {}
}
```

V1 has one canvas whose extent is either `infinite` or a fixed positive size.
Multi-page documents require a later scene version; readers must not guess page
semantics from unknown fields.

### Common rules

- Coordinates are points with a top-left origin, positive x rightward, and
  positive y downward.
- Numbers MUST be finite and geometry MUST remain inside ±1,000,000 points.
- IDs are lowercase UUID strings. Element array order is back-to-front z-order.
- Group membership uses stable IDs; coordinates remain absolute.
- Defaults are materialized when an element is created. A file never depends on
  the opening application's current preferences.
- Readers MUST reject unsupported `schemaVersion` values for editing.
- Unknown keys outside an `extensions` object MUST be rejected, never dropped.
- Writers SHOULD use reverse-DNS keys inside `extensions`. Readers MUST
  round-trip every extension key unchanged.

Elements form a tagged union:

- `shape`: frame, rotation, geometry, appearance, text, magnets.
- `text`: frame, rotation, text, appearance, magnets.
- `image`: frame, rotation, content-addressed asset ID, fit, appearance,
  magnets.
- `path`: transform, SVG-compatible path commands, fill rule, appearance,
  magnets.
- `connector`: endpoints, route intent, saved resolved path, appearance, label.
- `group`: organizational parent with hidden and locked state.

Associated values MUST use explicit `type` or `kind` discriminators. Swift's
synthesized `_0` enum payload representation is forbidden.

### Assets

An asset ID is `sha256:<64 lowercase hexadecimal characters>`. Its path is
`assets/<hash>.<extension>`. The scene records media type, byte length, original
name, pixel dimensions when applicable, and hash. Original bytes are preserved;
Sion never silently re-encodes an imported image.
Media types MUST be nonempty. Pixel dimensions MUST be finite values above zero
and at most 1,000,000.

Saving MUST fail if a referenced asset is absent or hash-mismatched. An asset is
removed only when no current element or retained history snapshot references it.

### Magnets

The editor offers presets, but the scene persists their expanded, stable points:

```json
{
  "id": "east",
  "position": { "x": 1, "y": 0.5 },
  "normal": { "dx": 1, "dy": 0 },
  "direction": "both"
}
```

Positions are normalized local coordinates. Direction is `incoming`,
`outgoing`, or `both`. An empty magnet list means no explicit magnets. Preset
types are `none`, `cardinalFour`, `northSouth`, `eastWest`, `diagonalFour`,
`eight`, `vertices`, and `perSegment` with a count from 1 through 32. A custom
configuration stores its own points.

### Connectors

An endpoint is free or attached. Attached endpoints store an element ID, an
automatic or stable magnet attachment, and a fallback point for recovery.
Routing kinds are `straight`, `curved`, `orthogonal`, and `bezier`.

Routing stores both intent and a resolved vector path. Automatic routes may be
recomputed after related geometry changes; simply opening and saving a document
MUST preserve the resolved path. Manual waypoints and Bézier handles move with
their endpoint element instead of being discarded.

## Reusable exports

SVG is produced from the immutable scene, not a screenshot. It MUST be
self-contained: raster assets use data URIs, styles are inline, and scripts,
events, external URLs, `foreignObject`, and network fonts are forbidden. Fixed
canvases export their extent. Infinite canvases export content bounds plus 32
points of padding.

Mermaid is regenerated on save from the scene's graph projection. Stable
semantic IDs are retained. Illustration-only elements are listed in leading
comments and set coverage to `partial`; the file never pretends to be lossless.

PNG is an optional cached convenience preview. SVG remains the required
full-resolution recovery image.

## History

History stores full canonical scenes, not undo state or patches. The index is:

```json
{
  "format": "sion-history",
  "version": 1,
  "entries": [
    {
      "id": "sha256:scene-hash",
      "savedAt": "2026-08-27T14:35:22Z",
      "scene": "history/20260827T143522Z-12hex.scene.json",
      "reason": "manual"
    }
  ]
}
```

Writers add a distinct scene after explicit saves and rate-limited autosave
checkpoints. They keep the 12 newest; then hourly for one day, daily for 30
days, weekly for one year, and monthly thereafter, capped at 120. The index can
be rebuilt by scanning snapshot names and verifying hashes.

Selection, viewport, current tool, and the transient undo stack are never
persisted as history.

## Versions and migration

`manifest.formatVersion` versions the ZIP contract. `scene.schemaVersion`
versions model semantics. Any semantic model addition increments the scene
version, including an optional field.

Loading proceeds in this order:

1. Validate the ZIP envelope and budgets.
2. Validate format identifiers and versions.
3. Verify the current scene and referenced asset hashes.
4. Decode the supported scene into editor-domain values.
5. Strictly validate the scene.

V1 has no migrations. A later reader that supports older scene versions SHOULD
decode them into a raw JSON tree and run ordered, pure migrations before step 4.

A future version may open in preview or recovery mode, but Sion MUST NOT save
it.

## Security budgets

V1 readers reject archives exceeding any limit:

```text
entries                     4,096
single entry                256 MiB
total expanded archive      1 GiB
elements                    100,000
magnets per element         256
path commands               4,096
route segments/waypoints    4,096
group depth                 64
history snapshots           120
```

Readers also reject absolute paths, `..`, backslashes, NUL, empty components,
invalid UTF-8, duplicate names, encryption, spanning, ZIP64, non-STORED entries,
forged sizes, CRC failures, and integer overflow. Entries are read directly;
the archive is never extracted wholesale.

## Safe writes

`NSDocument` owns normal saves and macOS file coordination. A save captures an
immutable scene/assets generation, builds the entire archive at the safe-save
URL, verifies it, then commits candidate history only if encoding succeeded and
the editor generation still matches. Save intent is an enum: `manual`,
`autosave`, or `saveAs`.

Recovery writes outside `NSDocument` use a sibling temporary file, flush and
`fsync`, reopen and verify authoritative hashes, atomically replace the target,
then `fsync` its directory. A failed write leaves the prior file untouched.
