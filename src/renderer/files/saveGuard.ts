export function isCompletedSaveCurrent(
  savedContents: string,
  savedPath: string | null,
  currentContents: string,
  currentPath: string | null,
): boolean {
  return savedContents === currentContents && savedPath === currentPath;
}
