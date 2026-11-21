import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { startPg, migrate } from '../../scripts/embedded-pg.mjs';

export default async function () {
  const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const { pg, url } = await startPg();
  migrate(url, root);
  process.env.DATABASE_URL = url;
  process.env.NODE_ENV = 'test';
  process.env.JWT_SECRET = 'e2e-test-secret-0123456789abcdefghijklmnop';
  process.env.RATE_LIMIT_PER_MINUTE = '100000';
  process.env.AUTH_RATE_LIMIT = '1000';
  globalThis.__PG__ = pg;
}
