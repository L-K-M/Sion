enum QuitState {
  Idle = 'idle',
  Requested = 'requested',
  Resuming = 'resuming',
}

/** Keeps a failed asynchronous close from becoming a delayed app quit. */
export class QuitCoordinator {
  private state = QuitState.Idle;

  request(): void {
    this.state = QuitState.Requested;
  }

  cancel(): void {
    if (this.state === QuitState.Requested) this.state = QuitState.Idle;
  }

  beginResumeWhenEmpty(openWindowCount: number): boolean {
    if (this.state !== QuitState.Requested || openWindowCount > 0) return false;

    this.state = QuitState.Resuming;
    return true;
  }

  isResuming(): boolean {
    return this.state === QuitState.Resuming;
  }
}
