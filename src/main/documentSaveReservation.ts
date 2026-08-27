export interface DocumentPathReservation {
  path: string;
  commit: () => void;
  rollback: () => void;
}

/** Document reservations replace aliases with their canonical owner path. */
export function saveTargetPath(
  selectedPath: string,
  reservation: DocumentPathReservation | null,
): string {
  return reservation?.path ?? selectedPath;
}
