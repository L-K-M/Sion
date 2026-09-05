# Sion

Native diagramming and digital illustration for macOS and Linux, paired with
[Lucerne](https://github.com/L-K-M/Lucerne).

Sion opens directly onto a canvas. Shapes get useful typography, shadows, and
connection magnets by default. Connection points are directly editable, and
connectors preview their routed path before placement. Image paste keeps the
original plus a safe display rendition. Inspector, library, and history menus
detach into native palettes.

`.sion` files are ZIP archives containing the editable scene, original assets,
standalone SVG, Mermaid, and retained history. The contract is documented in
[`docs/sion-format-v1.md`](docs/sion-format-v1.md).

## Build

Both applications share `SionCore` and the editor layer of `SionKit`; the
AppKit and GTK front ends mirror each other file for file, and
[`docs/feature-parity.md`](docs/feature-parity.md) lists every feature with
the file that implements it on each platform.

### macOS

Requirements: macOS 13+, Xcode command-line tools, Swift 6.

```bash
swift test
scripts/build.sh --clean
open build/Sion.app
```

`scripts/build.sh --run` launches the build. `--install` copies it to
`/Applications/Sion.app`.

### Linux

Requirements: Ubuntu 24.04 or newer, Swift 6.3.3, GTK 4.10+, libadwaita 1.5+.

```bash
sudo apt install libgtk-4-dev libadwaita-1-dev libpoppler-glib-dev \
  librsvg2-common dpkg-dev lintian
swift test
scripts/build-linux.sh
sudo dpkg -i build/linux/sion_*.deb
```

`scripts/build-linux.sh --run` launches the staged build and `--install`
installs the package. Without a display, run the tests as
`xvfb-run -a swift test`.

## License

Sion is released under the [Unlicense](LICENSE).
