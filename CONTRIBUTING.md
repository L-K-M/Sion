# Contributing to Thalyx

Thanks for helping build Thalyx! A few ground rules keep the project healthy.

## License dedication (required)

Thalyx's own source is dedicated to the public domain under the
[Unlicense](LICENSE). To keep that dedication intact, **every contribution must
be given to the public domain under the Unlicense as well.**

By submitting a pull request, you certify that your contribution is dedicated
under the Unlicense, and that you have the right to make that dedication.
Please add a sign-off line to your commits (DCO-style):

```
git commit -s
```

which appends:

```
Signed-off-by: Jane Doe <jane@example.com>
```

If your contribution contains code originally licensed under anything other
than a public-domain-equivalent or permissive license (MIT, BSD, ISC,
Apache-2.0, 0BSD, BlueOak, CC0), it **cannot be accepted** as-is. GPL/LGPL/
AGPL/MPL/EPL-licensed code is never acceptable. If you believe a verbatim copy
from a permissively-licensed project is genuinely needed, open an issue first —
it must live under `src/vendor/` with its copyright header intact and an entry
in `THIRD_PARTY_LICENSES.md` (see PLAN.md §4).

## Dependency policy

New dependencies require an allowlist check, regeneration of
`THIRD_PARTY_LICENSES.md` (`npm run gen:licenses`), and a note in
`CHANGELOG.md` (PLAN.md §19.3). `npm run check:licenses` runs in CI and fails
on non-allowlisted **production** licenses.

## Development

```bash
npm install        # install toolchain
npm run dev        # launch the Electron app with hot reload
npm run typecheck  # tsc over main/preload (node) and renderer/shared (web)
npm run lint       # eslint
npm run format     # prettier (write)
npm test           # vitest unit suite
npm run e2e        # Playwright Electron smoke suite (build first: npm run build)
npm run package    # unsigned local packages via electron-builder
```

- All document mutations go through the actions layer; geometry/serialization
  logic lives in `src/shared/` (pure TS — the eslint config rejects React/
  Electron imports there).
- Follow the architecture and binding decisions in [PLAN.md](PLAN.md) §2 —
  they are settled; propose changes via an issue rather than re-litigating in
  a PR.
- Commit style: small, imperative subjects scoped by milestone
  (`M3: elbow router side cases`). Update `CHANGELOG.md` per milestone, not per
  commit.
- Never copy code from tldraw, JointJS, GoJS, or React Flow Pro examples.
