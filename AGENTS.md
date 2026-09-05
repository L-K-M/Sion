# AGENTS.md

## Tooling

Use Swift 6.3.3 (`.swift-version` pins the toolchain).

- `swift test` verifies the portable core and the shared editor layer; on
  Linux it also runs the GTK tests (`xvfb-run -a swift test` without a display).
- `scripts/build.sh [--clean] [--run] [--install]` verifies and packages the
  native macOS app. `--install` copies it to `/Applications`.
- `scripts/build-linux.sh [--clean] [--run] [--install]` verifies and packages
  the native Linux app as a `.deb` (`scripts/make-deb.sh` assembles it).
- `scripts/release.sh X.Y.Z [--push]` bumps, commits, tags, and optionally
  pushes a release; the tag builds both the macOS and the Linux artifacts.
- A UI feature lands on both platforms: `Sources/SionKit` (AppKit) and
  `Sources/SionGtk` (GTK) mirror each other file for file. Update
  `docs/feature-parity.md` with every UI change.

## AI review scope

GLM review defaults to **hybrid**: the first review is full, then follow-ups
review changes since the last completed review plus a rotating sample of older
PR changes. Keep hybrid for normal implementation/fix cycles.

Before the next review-triggering push, apply at most one override label:

- `zai-review:full` for high-risk changes, force-push recovery, or a deliberate
  final deep audit.
- `zai-review:hybrid` to explicitly select the normal delta-plus-audit mode.
- `zai-review:incremental` only for low-risk, latency-sensitive follow-ups
  after a completed full review; this omits the rotating old-code audit.

Labels select the next run but do not trigger one themselves. Remove an override
to return to hybrid. Missing/incomplete state and non-ancestor history safely
fall back to a full review.
