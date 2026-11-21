// Starts a real PostgreSQL cluster from the embedded-postgres npm binaries (no Docker needed).
import EmbeddedPostgres from 'embedded-postgres';
import { execSync } from 'node:child_process';
import { mkdtempSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import net from 'node:net';

export async function freePort() {
  return new Promise((res, rej) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => res(p)); }); s.on('error', rej); });
}

/** @returns {{pg: EmbeddedPostgres, url: string}} */
export async function startPg({ dir, port, database = 'lotto_day', persistent = false } = {}) {
  const dataDir = dir ?? mkdtempSync(join(tmpdir(), 'lotto-pg-'));
  const fresh = !existsSync(join(dataDir, 'PG_VERSION'));
  port ??= await freePort();
  const pg = new EmbeddedPostgres({ databaseDir: dataDir, user: 'lotto', password: 'localpass', port, persistent, initdbFlags: ['--encoding=UTF8', '--locale=C'], onLog: () => {}, onError: () => {} });
  if (fresh) await pg.initialise();
  await pg.start();
  if (fresh) await pg.createDatabase(database);
  const url = `postgresql://lotto:localpass@127.0.0.1:${port}/${database}?schema=public`;
  return { pg, url };
}

export function migrate(url, cwd) {
  execSync('npx prisma migrate deploy', { cwd, env: { ...process.env, DATABASE_URL: url }, stdio: 'pipe' });
}
