# Sion

Native macOS diagramming and digital illustration, paired with
[Lucerne](https://github.com/L-K-M/Lucerne).

> [!IMPORTANT]
> LLM disclosure: This codebase was written with substantial help from large language models: AI coding agents working from the [`AGENTS.md`](AGENTS.md) brief in this repo.

Sion opens directly onto a canvas. Shapes get useful typography, shadows, and
connection magnets by default. Connection points are directly editable, and
connectors preview their routed path before placement. Image paste keeps the
original plus a safe display rendition. Inspector, library, and history menus
detach into native palettes.

The native chrome — classic window shape, toolbar and inspector controls,
status bar, and the palette machinery — comes from
[RigiUI](https://github.com/L-K-M/Rigi), the Lucerne-style AppKit toolkit Sion
shares with its sibling apps.

`.sion` files are ZIP archives containing the editable scene, original assets,
standalone SVG, Mermaid, and retained history. The contract is documented in
[`docs/sion-format-v1.md`](docs/sion-format-v1.md).

## Build

Requirements: macOS 13+, Xcode command-line tools, Swift 6.

```bash
swift test
scripts/build.sh --clean
open build/Sion.app
```

`scripts/build.sh --run` launches the build. `--install` copies it to
`/Applications/Sion.app`.

A downloaded build is ad-hoc signed and not notarized. After moving the app to
Applications, run `xattr -dr com.apple.quarantine "/Applications/Sion.app"`.

The Foundation-only `SionCore` target also builds on Linux. A future Linux UI
will be a separate native application held compatible by the format spec and
shared fixtures.

## License

Sion is released under the [Unlicense](LICENSE).
