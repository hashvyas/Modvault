import { withUser } from '@/lib/db';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function TestDbPage() {
  const session = await getSession();

  const count = await withUser(session, async (client) => {
    const res = await client.query('SELECT count(*)::int as count FROM mod_catalog_view');
    return res.rows[0].count;
  });

  return (
    <main className="p-8 space-y-4">
      <h1 className="text-2xl font-bold">Database Test Page</h1>
      <p className="text-muted-foreground">
        Queried <code className="bg-muted px-1.5 py-0.5 rounded">mod_catalog_view</code> through{' '}
        <code className="bg-muted px-1.5 py-0.5 rounded">withUser</code>:
      </p>
      <div className="p-4 rounded-md border bg-card text-card-foreground">
        Catalog row count: <strong id="catalog-row-count">{count}</strong>
      </div>
      <div className="text-sm text-muted-foreground">
        Active session: {session ? `${session.username} (${session.role})` : 'Anonymous'}
      </div>
    </main>
  );
}
