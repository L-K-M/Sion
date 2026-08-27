import type { WindowBootstrap } from '../shared/windowBootstrap';

export type AssociationResult<T> =
  { kind: 'associated'; bootstrap: WindowBootstrap } | { kind: 'conflict'; owner: T };

export type ReservationResult<T> =
  | {
      kind: 'reserved';
      bootstrap: WindowBootstrap;
      commit: () => void;
      rollback: () => void;
    }
  | { kind: 'conflict'; owner: T };

/** Owns the reloadable document identity for each native window. */
export class WindowDocuments<T> {
  private readonly records = new Map<T, WindowBootstrap>();
  private readonly reservations = new Map<string, T>();

  constructor(
    private readonly createScratchId: () => string,
    private readonly idForPath: (path: string) => string,
    private readonly normalizePath: (path: string) => string = (path) => path,
  ) {}

  add(window: T, bootstrap: WindowBootstrap): void {
    this.records.set(window, bootstrap);
  }

  remove(window: T): void {
    this.records.delete(window);
    this.releaseReservations(window);
  }

  bootstrap(window: T): WindowBootstrap | null {
    return this.records.get(window) ?? null;
  }

  owner(path: string): T | null {
    const normalized = this.normalizePath(path);
    const reserved = this.reservations.get(normalized);
    if (reserved !== undefined) return reserved;

    for (const [window, bootstrap] of this.records) {
      if (bootstrap.openPath === normalized) return window;
    }

    return null;
  }

  associate(window: T, path: string | null, updateReady: boolean): AssociationResult<T> {
    if (path === null) {
      this.releaseReservations(window);
      const bootstrap = this.blankBootstrap(updateReady);
      this.records.set(window, bootstrap);
      return { kind: 'associated', bootstrap };
    }

    const normalized = this.normalizePath(path);
    const owner = this.owner(normalized);
    if (owner !== null && owner !== window) return { kind: 'conflict', owner };

    const current = this.records.get(window);
    const bootstrap: WindowBootstrap = {
      scratchId: current?.scratchId ?? this.idForPath(normalized),
      openPath: normalized,
      recovery: null,
      updateReady,
    };
    this.releaseReservations(window);
    this.records.set(window, bootstrap);
    return { kind: 'associated', bootstrap };
  }

  reserve(window: T, path: string, updateReady: boolean): ReservationResult<T> {
    const normalized = this.normalizePath(path);
    const owner = this.owner(normalized);
    if (owner !== null && owner !== window) return { kind: 'conflict', owner };

    this.releaseReservations(window);
    this.reservations.set(normalized, window);
    const current = this.records.get(window);
    const bootstrap: WindowBootstrap = {
      scratchId: current?.scratchId ?? this.idForPath(normalized),
      openPath: normalized,
      recovery: null,
      updateReady,
    };
    let active = true;

    return {
      kind: 'reserved',
      bootstrap,
      commit: () => {
        if (!active || this.reservations.get(normalized) !== window) return;

        active = false;
        const result = this.associate(window, normalized, updateReady);
        if (result.kind === 'conflict') throw new Error('reserved document ownership changed');
      },
      rollback: () => {
        if (!active || this.reservations.get(normalized) !== window) return;

        active = false;
        this.reservations.delete(normalized);
      },
    };
  }

  private releaseReservations(window: T): void {
    for (const [path, owner] of this.reservations) {
      if (owner === window) this.reservations.delete(path);
    }
  }

  private blankBootstrap(updateReady: boolean): WindowBootstrap {
    return {
      scratchId: this.createScratchId(),
      openPath: null,
      recovery: null,
      updateReady,
    };
  }
}

/** Scratch contents change after every autosave, so bootstrap resolves live. */
export async function resolveWindowBootstrap(
  bootstrap: WindowBootstrap,
  readRecovery: (docId: string) => Promise<string>,
): Promise<WindowBootstrap> {
  if (bootstrap.openPath) return { ...bootstrap, recovery: null };

  try {
    const contents = await readRecovery(bootstrap.scratchId);
    return {
      ...bootstrap,
      recovery: { docId: bootstrap.scratchId, contents },
    };
  } catch {
    return { ...bootstrap, recovery: null };
  }
}
