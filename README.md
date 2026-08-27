# Sion

Native macOS diagramming and digital illustration, paired with
[Lucerne](https://github.com/L-K-M/Lucerne).

Sion opens directly onto a canvas. Shapes get useful typography, shadows, and
connection magnets by default. Connection points are directly editable, and
connectors preview their routed path before placement. Images paste as original
embedded assets. Inspector, library, and history menus detach into native
palettes.

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

The Foundation-only `SionCore` target also builds on Linux. A future Linux UI
will be a separate native application held compatible by the format spec and
shared fixtures.

## License

Sion is released under the [Unlicense](LICENSE).
