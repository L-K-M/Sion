type OpenPath = (path: string) => Promise<void>;
type SendMenuAction = (action: string, arg: unknown) => void;

export async function routeMenuAction(
  action: string,
  arg: unknown,
  openPath: OpenPath,
  send: SendMenuAction,
): Promise<void> {
  // Recent paths must pass through main so the exact file is granted before read.
  if (action === 'openRecent' && typeof arg === 'string' && arg.length > 0) {
    await openPath(arg);
    return;
  }

  send(action, arg);
}
