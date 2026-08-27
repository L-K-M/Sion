/** Tracks document windows without coupling routing decisions to Electron. */
export class WindowRegistry<T> {
  private readonly windows = new Set<T>();
  private lastActive: T | null = null;

  constructor(private readonly isDestroyed: (window: T) => boolean) {}

  add(window: T): void {
    this.windows.add(window);
    this.lastActive = window;
  }

  remove(window: T): void {
    this.windows.delete(window);
    if (this.lastActive === window) this.lastActive = null;
  }

  markActive(window: T): void {
    if (!this.windows.has(window) || this.isDestroyed(window)) return;

    this.lastActive = window;
  }

  target(focused: T | null): T | null {
    if (focused && this.windows.has(focused) && !this.isDestroyed(focused)) return focused;
    if (this.lastActive && !this.isDestroyed(this.lastActive)) return this.lastActive;

    const live = this.all();
    return live.at(-1) ?? null;
  }

  all(): T[] {
    return [...this.windows].filter((window) => !this.isDestroyed(window));
  }
}
