# Manual QA checklist (M4 draft — PLAN.md §15.3; finalized at M8)

Per-release manual pass. Checked on Ubuntu LTS (X11 + Wayland) and macOS.

## I1–I18 interaction floor (PLAN.md §10 / ux.md)

- [ ] I1 — opens straight onto an empty canvas; hint visible; no dialogs
- [ ] I2 — pan: space-drag, middle-drag, right-drag; zoom: wheel/pinch at cursor; Mod+= / Mod+- / Mod+0
- [ ] I3 — no minimap; Shift+1 zoom-to-fit; Shift+2 zoom-to-selection
- [ ] I4 — shape tool: click-place; drag-size; tool lock via double-press/alt-click
- [ ] I5 — Mod+Arrow grow from a selected node; Tab cycles shape; chevron click = same gesture; corridor connect (existing node in 48px lane)
- [ ] I6 — select: click, shift-click, rubber-band; Esc deselects
- [ ] I7 — connect by handle drag from any side; floating endpoints re-derive on node moves
- [ ] I8 — edge selection (click path), delete, undo (one entry per intent)
- [ ] I9 — edge label chip: drag along route (labelT), legible over the line
- [ ] I10 — label editing: double-click, Enter, type-to-edit (incl. Shift+letter capitals); Esc commits + deselects; IME guard (type Japanese via ibus/macOS IME)
- [ ] I11 — duplicate: Mod+D; Alt+drag leaves a copy at the drop, original returns
- [ ] I12 — smart guides during drag (6px threshold, both axes); gap chips with px values; grid 8px; Mod disables all
- [ ] I13 — Tidy Up Alt+Shift+T; Auto-layout Alt+Shift+L (one-shot, undoable)
- [ ] I14 — one-shot actions only; no persistent layout mode
- [ ] I15 — everything undoable: import, layout, style, group, grow (one Mod+Z each)
- [ ] I16 — Mod+G wraps selection in container; Mod+Shift+G dissolves (absolute positions preserved)
- [ ] I17 — theme toggle Shift+Alt+D cycles system → light → dark; canvas remaps live
- [ ] I18 — autosave behavior verified at M7

## Editing floor extras (§10.2)

- [ ] Tool keys V/R/O/D/A/L/T/F/H + digit aliases; Q chevron toggle
- [ ] Type-to-edit precedence beats tool keys (single node selected)
- [ ] Nudge 1px / 8px (Shift)
- [ ] Z-order Mod+[ / Mod+] / Mod+Shift+[ / Mod+Shift+]
- [ ] Context panel: selection-scoped rows; palette tokens + custom hex; corner toggle; shape popup; link field (scheme validated)
- [ ] Help overlay Shift+/: search, Esc close

## Demo timing (M4 acceptance)

- [ ] Login-flow demo (7 nodes, 6 edges incl. Auth container) built in < 90 s
      with keyboard + mouse

## M6 manual checks

- [ ] M4 demo export renders correctly on mermaid.live (paste the panel text)
- [ ] Copy as Mermaid (Mod+Shift+C) → paste into mermaid.live → identical graph

## Platform notes

- [ ] Wayland: `ELECTRON_OZONE_PLATFORM_HINT=auto` (set in main); text crispness
- [ ] HiDPI/fractional scaling window at 125%/150%
- [ ] Trackpad two-finger pan/zoom vs mouse
