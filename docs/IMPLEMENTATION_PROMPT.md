# Implementation kickoff prompt

Paste the prompt below into a fresh Claude Code session on this repo to execute
[`PLAN.md`](../PLAN.md) end-to-end: one PR per milestone, each babysat (CI kept green, review
feedback addressed, hourly check-ins) until it reaches steady state, then merged before the next
begins.

Note: as written, the prompt grants standing permission to **merge automatically** at steady
state. If you want a human approval gate instead, edit step 6 of the per-PR loop to
"wait for my approval before merging" — the babysitting loop still keeps the PR green while it
waits.

---

```text
Implement PLAN.md in this repo (L-K-M/Thalyx) from start to finish — milestone by
milestone, one PR at a time. Each PR gets babysat until it reaches steady state,
then merged; only then does the next one start. You have standing permission to
merge PRs that reach steady state as defined below — do not stop to ask.

CONTRACT
- PLAN.md at the repo root is the authoritative spec. Read it fully before
  starting, and re-read the sections relevant to each milestone before its PR.
  The binding decisions in §2 and the rules in §19 are final — never relitigate
  them. docs/research/ is background evidence; where it disagrees with PLAN.md,
  PLAN.md wins.
- If your context is ever summarized or you lose track mid-run, re-derive where
  you are from: PLAN.md, the PR sequence below, and the repo's open/merged PRs.

PR SEQUENCE (branch → scope; do not start N+1 before N is merged)
  1. impl/m0-scaffold      → M0: scaffold, security baseline, license gate, CI
  2. impl/m1-model         → M1: document model, store, snapshot history + tests
  3. impl/m2-canvas        → M2: canvas rendering/editing, theme, perf gate
  4. impl/m3-connections   → M3: connectors, elbow router, edge labels
  5. impl/m4-ux            → M4: editing UX floor (may split into 2–3 PRs:
                             text/duplicate/guides · panel/palette/keymap ·
                             chevrons/grow/layout-actions)
  6. impl/m5-mermaid-import→ M5: mermaid import, islands, corpus tests
  7. impl/m6-mermaid-export→ M6: exporter, round-trip/fixpoint tests, panel
  8. impl/m7-desktop       → M7: files/IPC/menus/autosave + SVG/PNG/PDF/clipboard
                             (may split: files+shell · exports)
  9. impl/m8-sync-release  → M8: reconcile/apply, a11y, packaging, updater;
                             after merge: tag v0.1.0 and verify release artifacts
Split a PR only when its non-test diff would exceed ~1500 lines, at the
boundaries suggested above; each split part goes through the same full loop.

PER-PR LOOP
1. Branch from freshly-pulled main. Implement the milestone's tasks exactly per
   its PLAN.md §17 entry and the sections it references.
2. Before opening the PR: run every local check (typecheck, lint, vitest,
   applicable Playwright suites); verify EACH acceptance criterion for the
   milestone and record how; adversarially re-read your own full diff and fix
   what you find. Do not open a PR you expect to go red.
3. Open the PR to main, ready for review (not draft). Description: milestone,
   what was built, per-criterion verification evidence (commands + results),
   and any deviations from PLAN.md (also logged in CHANGELOG.md per §19).
4. Subscribe to the PR's activity and babysit it:
   - Red CI or a merge conflict is work NOW — diagnose, fix, push, every time.
   - Address every review comment (human or bot): push the fix or reply with
     why not; resolve threads you addressed.
   - Schedule a self check-in roughly every hour; on each, re-check the PR's
     head (CI, mergeability, threads), act on anything open, re-arm the timer.
5. STEADY STATE = all of: CI fully green on the latest head; mergeable; zero
   unresolved review threads; milestone acceptance criteria verified on the
   final head; and no new human comments or pushes for ~2 consecutive check-ins
   since your last change.
6. At steady state: squash-merge, delete the branch, pull main, then start the
   next PR. Exception: if a human has requested changes without re-approving,
   or asked you to wait — address their feedback and wait for them instead of
   merging.
7. If blocked for more than 2 check-ins on something you cannot resolve inside
   PLAN.md's decisions (e.g. a genuine spec contradiction, missing signing
   secrets that gate a criterion): if the plan marks it conditional (macOS
   signing is), document and proceed; otherwise leave one comment on the PR
   stating precisely what you need, and ask me.

HARD RULES
- PLAN.md §19 applies throughout: no dependencies beyond §5 without the license
  gate; never copy code from tldraw, JointJS, GoJS, or React Flow Pro examples;
  all doc mutations through actions; mermaid stays pinned at 11.17.0 (upgrades
  only via the corpus gate).
- Never skip, weaken, or quarantine a failing test to get green. Never rewrite
  history on a pushed branch. Keep every commit compiling.
- Keep CHANGELOG.md current per milestone.
- After the final merge: tag v0.1.0, confirm the release workflow produced the
  dmg/AppImage/deb/rpm artifacts and updater feed, then post a final summary
  here: PRs merged, deviations from plan, and remaining risks/open items.

Start now with impl/m0-scaffold.
```
