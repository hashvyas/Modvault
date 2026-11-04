import { Pool, PoolClient } from 'pg';
import path from 'path';
import dotenv from 'dotenv';
if (!process.env.APP_DATABASE_URL && !process.env.DATABASE_URL) {
  dotenv.config({ path: path.resolve(process.cwd(), '../.env') });
  dotenv.config({ path: path.resolve(process.cwd(), '.env') });
}

export interface SessionUser {
  user_id?: string;
  sub?: string;
  username?: string;
  role?: string;
}
const connectionString =
  process.env.APP_DATABASE_URL ||
  process.env.DATABASE_URL ||
  'postgresql://modvault_app:modvault_app_dev@localhost:5432/modvault';

const globalForDb = globalThis as unknown as { pool: Pool | undefined };

export const pool =
  globalForDb.pool ??
  new Pool({
    connectionString,
    max: 5,
    idleTimeoutMillis: 30000,
  });

if (process.env.NODE_ENV !== 'production') {
  globalForDb.pool = pool;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function withUser<T>(
  session: SessionUser | null | undefined,
  fn: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const tokenUserId = session?.user_id || session?.sub || '';
    const userId = UUID_RE.test(tokenUserId) ? tokenUserId : null;
    await client.query(
      `SELECT set_config('app.user_id', coalesce(u.user_id::text, ''), true),
              set_config('app.role', coalesce(u.role::text, ''), true)
       FROM (SELECT 1) AS one
       LEFT JOIN users u ON u.user_id = $1::uuid AND u.is_active`,
      [userId]
    );

    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
    }
    throw error;
  } finally {
    client.release();
  }
}
