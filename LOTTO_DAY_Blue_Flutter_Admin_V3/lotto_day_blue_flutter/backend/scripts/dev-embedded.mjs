// One-command local run WITHOUT Docker: embedded PostgreSQL (persistent in .pgdata) + migrate + seed + API (+ Flutter web if built).
// Usage: npm run build && npm run dev:embedded
import { spawn, execSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { startPg, migrate } from './embedded-pg.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const port = Number(process.env.PG_PORT || 54329);
const { pg, url } = await startPg({ dir: join(root, '.pgdata'), port, persistent: true });
console.log(`[dev] PostgreSQL ready: ${url}`);
migrate(url, root);
const env = { ...process.env, DATABASE_URL: url, PORT: process.env.PORT || '3000' };
execSync('node dist/seed.js', { cwd: root, env, stdio: 'inherit' });
const api = spawn(process.execPath, ['dist/main.js'], { cwd: root, env, stdio: 'inherit' });
const stop = async () => { api.kill(); await pg.stop(); process.exit(0); };
process.on('SIGINT', stop); process.on('SIGTERM', stop);
api.on('exit', async (code) => { await pg.stop(); process.exit(code ?? 0); });
