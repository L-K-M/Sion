# Contributing

Contributions are dedicated to the public domain under the [Unlicense](LICENSE).
Sign commits with `git commit -s`.

```bash
swift test
scripts/build.sh        # macOS
scripts/build-linux.sh  # Linux
```

Keep `SionCore` free of AppKit and Core Graphics, and keep SionKit's shared
files (the editor controller and its neighbours outside `#if canImport(AppKit)`)
free of both AppKit and GTK. Views call editor commands; documents call archive
services. A UI change lands in SionKit's AppKit files and in `SionGtk`, and in
`docs/feature-parity.md`. Format changes require a schema version, spec update,
migration, and shared fixture.
