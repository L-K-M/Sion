export interface RecoveryBootstrap {
  docId: string;
  contents: string;
}

/** Stable initial document state returned again after a renderer reload. */
export interface WindowBootstrap {
  scratchId: string;
  openPath: string | null;
  recovery: RecoveryBootstrap | null;
  updateReady: boolean;
}
