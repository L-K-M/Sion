type OpenPath = (path: string) => Promise<void>;
type SendMenuAction = (action: string, arg: unknown) => void;

export async function routeMenuAction(
  action: string,
  arg: unknown,
  openPath: OpenPath,
  send: SendMenuAction,
): Promise<void> {
  // Recent paths must pass through main so the exact file is granted before read.
  if (action === 'openRecent') {
    if (typeof arg !== 'string' || arg.length === 0) return;

    try {
      await openPath(arg);
    } catch (error) {
      console.error('Failed to open recent file', { path: arg, error });
    }
    return;
  }

  send(action, arg);
}
