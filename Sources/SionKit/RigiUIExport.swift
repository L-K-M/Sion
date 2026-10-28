#if canImport(AppKit)
  // The palette API (PaletteKind, PaletteDefinition, PaletteCenter, Palette,
  // and friends) and the Lucerne classic controls live in Rigi's RigiUI
  // module now. SionKit re-exports it so existing `import SionKit` consumers
  // keep the same palette source surface they had before the move.
  @_exported import RigiUI
#endif
