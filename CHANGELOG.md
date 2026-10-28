# Changelog

## Unreleased

- Adopted [RigiUI](https://github.com/L-K-M/Rigi) for the native chrome: the
  document window is now an Aqua-pinned `ClassicWindow` with separate
  title/toolbar bands and a shared status bar carrying zoom controls and
  hover/selection context. Toolbar items, customization, and shortcuts are
  unchanged.
- Moved the palette machinery (`PaletteKind`, `PaletteDefinition`,
  `PaletteCenter`, `Palette`, panel, and popover) to `RigiUI`; `SionKit`
  re-exports it so `import SionKit` keeps working. Palette positions persist
  under the existing `Sion.palette.*` autosave names.
- Restyled the inspector, library, and history contents on the shared classic
  panel backing with compact metrics and classic pop-up/color-well controls;
  checkboxes and text fields stay native.
