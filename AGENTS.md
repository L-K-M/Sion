# AGENTS.md

## Tooling

Use Node.js 24+ and npm 11+ (`.node-version` pins CI's release).

- `npm ci` installs the locked dependency tree.
- `npm run check` mirrors the static, license, and unit-test gate.
- `scripts/build.sh [--clean] [--run] [--install]` verifies and packages the
  app; `--install` copies the native macOS build to `/Applications`.
- `scripts/release.sh X.Y.Z [--push]` bumps, commits, tags, and optionally
  pushes a release through the shared `lkm-release` engine.

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
