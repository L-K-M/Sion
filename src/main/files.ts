/**
 * Main-process file services (PLAN.md §12.4): atomic writes, .bak copies,
 * and the recovery store. IPC-registered in ipc.ts.
 */
import { app } from 'electron';
import { copyFile, mkdir, open, readdir, readFile, rename, rm, stat } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { z } from 'zod';

const recoveryDir = () => join(app.getPath('userData'), 'recovery');

/** docId rule (§12.4): sha256(absPath).slice(0,16) for file docs. */
export function docIdForPath(absPath: string): string {
  return createHash('sha256').update(absPath).digest('hex').slice(0, 16);
}

/** ATOMIC write: unique tmp in the same directory, fsync, then rename (§12.4). */
export async function writeAtomic(path: string, contents: string): Promise<void> {
  const tmp = `${path}.${process.pid}.${Date.now()}.tmp`;
  const fh = await open(tmp, 'w');
  try {
    await fh.writeFile(contents, 'utf8');
    await fh.sync(); // fsync before rename
  } catch (err) {
    await fh.close();
    await rm(tmp, { force: true }); // no orphaned tmp on failure
    throw err;
  }
  await fh.close();
  await rename(tmp, path);
}

/** .bak copy before the first in-place save of a session per file. */
const backedUpThisSession = new Set<string>();
export async function backupOnce(path: string): Promise<void> {
  if (backedUpThisSession.has(path)) return;
  if (!existsSync(path)) return;
  await copyFile(path, `${path}.bak`);
  backedUpThisSession.add(path); // marked only after the copy succeeded
}

// ---------------------------------------------------------------------------
// Recovery store: recovery/<docId>.thalyx + manifest.json
// ---------------------------------------------------------------------------

interface ManifestEntry {
  docId: string;
  originalPath: string | null;
  savedAt: number;
}

const manifestPath = () => join(recoveryDir(), 'manifest.json');

const DOC_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;

/** Guard recovery file paths against traversal via crafted docIds. */
function assertDocId(docId: string): void {
  if (!DOC_ID_RE.test(docId)) throw new Error('invalid docId');
}

async function readManifest(): Promise<ManifestEntry[]> {
  try {
    const raw = JSON.parse(await readFile(manifestPath(), 'utf8'));
    return z
      .array(
        z.object({ docId: z.string(), originalPath: z.string().nullable(), savedAt: z.number() }),
      )
      .parse(raw);
  } catch {
    return [];
  }
}

async function writeManifest(entries: ManifestEntry[]): Promise<void> {
  await mkdir(recoveryDir(), { recursive: true });
  await writeAtomic(manifestPath(), JSON.stringify(entries, null, 2));
}

export async function recoveryWrite(
  docId: string,
  contents: string,
  originalPath: string | null,
): Promise<void> {
  await mkdir(recoveryDir(), { recursive: true });
  await writeAtomic(join(recoveryDir(), `${docId}.thalyx`), contents);
  const entries = (await readManifest()).filter((e) => e.docId !== docId);
  entries.push({ docId, originalPath, savedAt: Date.now() });
  await writeManifest(entries);
}

export async function recoveryList(): Promise<ManifestEntry[]> {
  return readManifest();
}

export async function recoveryRead(docId: string): Promise<string> {
  assertDocId(docId);
  return readFile(join(recoveryDir(), `${docId}.thalyx`), 'utf8');
}

export async function recoveryClear(docId: string): Promise<void> {
  assertDocId(docId);
  const file = join(recoveryDir(), `${docId}.thalyx`);
  if (existsSync(file)) await rm(file);
  await writeManifest((await readManifest()).filter((e) => e.docId !== docId));
}

export async function recoveryListFiles(): Promise<string[]> {
  if (!existsSync(recoveryDir())) return [];
  return readdir(recoveryDir());
}

// ---------------------------------------------------------------------------
// Prefs (§12.5): userData/prefs.json, atomic, zod-validated, normalize-on-load
// ---------------------------------------------------------------------------

export interface Recent {
  path: string;
  name: string;
  lastOpened: number;
}

export interface Prefs {
  theme: 'system' | 'light' | 'dark';
  recents: Recent[];
  windowState?: { x: number; y: number; width: number; height: number; maximized: boolean };
  chevronsEnabled: boolean;
  lastExportDir?: string;
  updateChannelOptIn: boolean;
}

const prefsPath = () => join(app.getPath('userData'), 'prefs.json');

const prefsSchema = z.object({
  theme: z.enum(['system', 'light', 'dark']).default('system'),
  recents: z
    .array(z.object({ path: z.string(), name: z.string(), lastOpened: z.number() }))
    .max(10)
    .default([]),
  windowState: z
    .object({
      x: z.number(),
      y: z.number(),
      width: z.number(),
      height: z.number(),
      maximized: z.boolean(),
    })
    .optional(),
  chevronsEnabled: z.boolean().default(true),
  lastExportDir: z.string().optional(),
  updateChannelOptIn: z.boolean().default(false),
});

export async function readPrefs(): Promise<Prefs> {
  try {
    const raw = JSON.parse(await readFile(prefsPath(), 'utf8'));
    return prefsSchema.parse(raw) as Prefs;
  } catch {
    return prefsSchema.parse({}) as Prefs;
  }
}

export async function writePrefs(prefs: Prefs): Promise<void> {
  await writeAtomic(prefsPath(), JSON.stringify(prefs, null, 2));
}

/** Existence-checked recents (§12.5). */
export async function pruneRecents(prefs: Prefs): Promise<Prefs> {
  const kept: Recent[] = [];
  for (const r of prefs.recents) {
    try {
      await stat(r.path);
      kept.push(r);
    } catch {
      // dropped
    }
  }
  return { ...prefs, recents: kept.slice(0, 10) };
}

export async function addRecent(prefs: Prefs, path: string): Promise<Prefs> {
  const name = path.split(/[\\/]/).pop() ?? path;
  const recents = [
    { path, name, lastOpened: Date.now() },
    ...prefs.recents.filter((r) => r.path !== path),
  ].slice(0, 10);
  return { ...prefs, recents };
}
