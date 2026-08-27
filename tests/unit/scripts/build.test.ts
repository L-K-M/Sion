import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join, resolve } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';

const REPOSITORY_ROOT = resolve(import.meta.dirname, '../../..');
const BUILD_SCRIPT = join(REPOSITORY_ROOT, 'scripts/build.sh');
const TEST_NODE_VERSION = 'v24.0.0';
const TEST_NPM_VERSION = '11.0.0';
const TEST_PACKAGE_VERSION = '0.1.0';
const INSTALL_TARGET = '/Applications/Thalyx.app';
const INSTALL_CASES = [
  { architecture: 'arm64', app: 'release/mac-arm64/Thalyx.app' },
  { architecture: 'x86_64', app: 'release/mac/Thalyx.app' },
] as const;

const temporaryDirectories: string[] = [];

afterEach(() => {
  for (const directory of temporaryDirectories) {
    rmSync(directory, { recursive: true, force: true });
  }

  temporaryDirectories.length = 0;
});

function writeCommand(directory: string, name: string, body: string): void {
  const command = join(directory, name);
  writeFileSync(command, `#!/usr/bin/env bash\n${body}\n`);
  chmodSync(command, 0o755);
}

describe('scripts/build.sh', () => {
  it.each(INSTALL_CASES)(
    'selects the $architecture macOS app for installation',
    ({ architecture, app }) => {
      // Fake only host and tool versions so the check stays deterministic and read-only.
      const commandDirectory = mkdtempSync(join(tmpdir(), 'thalyx-build-test-'));
      temporaryDirectories.push(commandDirectory);

      writeCommand(
        commandDirectory,
        'uname',
        `if [[ "\${1:-}" == "-m" ]]; then echo '${architecture}'; else echo 'Darwin'; fi`,
      );
      writeCommand(
        commandDirectory,
        'node',
        `if [[ "\${1:-}" == "--version" ]]; then echo '${TEST_NODE_VERSION}'; else echo '${TEST_PACKAGE_VERSION}'; fi`,
      );
      writeCommand(commandDirectory, 'npm', `echo '${TEST_NPM_VERSION}'`);

      const result = spawnSync(BUILD_SCRIPT, ['--install', '--check'], {
        cwd: REPOSITORY_ROOT,
        encoding: 'utf8',
        env: {
          ...process.env,
          PATH: `${commandDirectory}${delimiter}${process.env.PATH ?? ''}`,
        },
      });

      expect(result.status, result.stderr).toBe(0);
      expect(result.stdout).toContain(join(REPOSITORY_ROOT, app));
      expect(result.stdout).toContain(INSTALL_TARGET);
    },
  );
});
