/**
 * Application menu (PLAN.md §12.3): roles only for items with no canvas
 * meaning; Edit menu items are role-LESS custom items dispatching to the
 * renderer (the renderer routes them by focus context).
 */
import { app, Menu, type BrowserWindow, type MenuItemConstructorOptions } from 'electron';

export type MenuAction =
  | 'undo'
  | 'redo'
  | 'cut'
  | 'copy'
  | 'paste'
  | 'selectAll'
  | 'delete'
  | 'new'
  | 'open'
  | 'save'
  | 'saveAs'
  | 'importMermaid'
  | 'export'
  | 'print'
  | 'zoomIn'
  | 'zoomOut'
  | 'zoomReset'
  | 'zoomFit'
  | 'zoomSelection'
  | 'toggleTheme'
  | 'toggleGrid'
  | 'toggleMermaidPanel'
  | 'toggleDevTools'
  | 'help'
  | 'about'
  | 'openRecent';

export function buildMenu(
  getMainWindow: () => BrowserWindow | null,
  onAction: (action: MenuAction, arg?: unknown) => void,
  recents: Array<{ path: string; name: string }>,
): Menu {
  const isMac = process.platform === 'darwin';
  const cmd = (accelerator: string) => accelerator.replace('Mod+', isMac ? 'Cmd+' : 'Ctrl+');

  const editItems: MenuItemConstructorOptions[] = [
    {
      label: 'Undo',
      accelerator: cmd('Mod+Z'),
      click: () => onAction('undo'),
    },
    {
      label: 'Redo',
      accelerator: cmd('Mod+Shift+Z'),
      click: () => onAction('redo'),
    },
    { type: 'separator' },
    { label: 'Cut', accelerator: cmd('Mod+X'), click: () => onAction('cut') },
    { label: 'Copy', accelerator: cmd('Mod+C'), click: () => onAction('copy') },
    { label: 'Paste', accelerator: cmd('Mod+V'), click: () => onAction('paste') },
    {
      label: 'Select All',
      accelerator: cmd('Mod+A'),
      click: () => onAction('selectAll'),
    },
    { type: 'separator' },
    {
      label: 'Delete',
      accelerator: 'Delete',
      click: () => onAction('delete'),
    },
  ];

  const recentItems: MenuItemConstructorOptions[] =
    recents.length === 0
      ? [{ label: 'No recent files', enabled: false }]
      : recents.slice(0, 10).map((r, i) => ({
          label: r.name,
          accelerator: i < 9 ? `CmdOrCtrl+Shift+${i + 1}` : undefined,
          click: () => onAction('openRecent', r.path),
        }));

  const macAppMenu: MenuItemConstructorOptions = {
    label: app.name,
    submenu: [
      { role: 'about' },
      { type: 'separator' },
      { role: 'hide' },
      { role: 'hideOthers' },
      { type: 'separator' },
      { role: 'quit' },
    ],
  };
  const windowMenu: MenuItemConstructorOptions = {
    role: 'window',
    submenu: [{ role: 'minimize' }, { role: 'zoom' }, { role: 'close' }],
  };

  const template: MenuItemConstructorOptions[] = [
    ...(isMac ? [macAppMenu] : []),
    {
      label: 'File',
      submenu: [
        { label: 'New', accelerator: cmd('Mod+N'), click: () => onAction('new') },
        { label: 'Open…', accelerator: cmd('Mod+O'), click: () => onAction('open') },
        {
          label: 'Open Recent',
          submenu: [
            ...recentItems,
            { type: 'separator' },
            { label: 'Clear Menu', click: () => onAction('openRecent', null) },
          ],
        },
        { type: 'separator' },
        { label: 'Save', accelerator: cmd('Mod+S'), click: () => onAction('save') },
        { label: 'Save As…', accelerator: cmd('Mod+Shift+S'), click: () => onAction('saveAs') },
        { type: 'separator' },
        { label: 'Import Mermaid…', click: () => onAction('importMermaid') },
        { label: 'Export…', accelerator: cmd('Mod+Shift+E'), click: () => onAction('export') },
        { type: 'separator' },
        { label: 'Print…', accelerator: cmd('Mod+P'), click: () => onAction('print') },
        ...(isMac ? [] : [{ type: 'separator' as const }, { role: 'quit' as const }]),
      ],
    },
    { label: 'Edit', submenu: editItems },
    {
      label: 'View',
      submenu: [
        { label: 'Zoom In', accelerator: cmd('Mod+='), click: () => onAction('zoomIn') },
        { label: 'Zoom Out', accelerator: cmd('Mod+-'), click: () => onAction('zoomOut') },
        { label: 'Actual Size', accelerator: cmd('Mod+0'), click: () => onAction('zoomReset') },
        { type: 'separator' },
        { label: 'Zoom to Fit', accelerator: 'Shift+1', click: () => onAction('zoomFit') },
        {
          label: 'Zoom to Selection',
          accelerator: 'Shift+2',
          click: () => onAction('zoomSelection'),
        },
        { type: 'separator' },
        { label: 'Toggle Grid', click: () => onAction('toggleGrid') },
        {
          label: 'Toggle Mermaid Panel',
          accelerator: cmd('Mod+Shift+M'),
          click: () => onAction('toggleMermaidPanel'),
        },
        { type: 'separator' },
        {
          label: 'Toggle Developer Tools',
          accelerator: isMac ? 'Cmd+Alt+I' : 'Ctrl+Shift+I',
          click: () => getMainWindow()?.webContents.toggleDevTools(),
        },
      ],
    },
    ...(isMac ? [windowMenu] : []),
    {
      role: 'help',
      submenu: [
        { label: 'Keyboard Shortcuts', accelerator: 'Shift+/', click: () => onAction('help') },
        {
          label: 'GitHub Repository',
          click: () => onAction('about', 'github'),
        },
        { label: 'About Thalyx', click: () => onAction('about') },
      ],
    },
  ];

  return Menu.buildFromTemplate(template);
}
