/**
 * Document-model constants (PLAN.md §7). The `.thalyx` file is
 * `{ type: 'thalyx', version: 1, ... }`; this module exists from M0 so the
 * shared test surface and the renderer have a single source of truth.
 */
export const DOC_TYPE = 'thalyx' as const;

export const DOC_VERSION = 1 as const;

/** Identifier of the schema variant a doc carries (used in errors/diagnostics). */
export const DOC_SCHEMA_ID = `${DOC_TYPE}@v${DOC_VERSION}` as const;
