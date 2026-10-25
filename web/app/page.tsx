import Link from 'next/link';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { logoutAction } from '@/app/actions/auth';
import { Button } from '@/components/ui/button';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';

export const dynamic = 'force-dynamic';

export default async function HomePage() {
  const session = await getSession();

  let catalogCount = 0;
  let errorMsg: string | null = null;
  try {
    catalogCount = await withUser(session, async (client) => {
      const res = await client.query('SELECT count(*)::int as count FROM mod_catalog_view');
      return res.rows[0]?.count ?? 0;
    });
  } catch (err: unknown) {
    errorMsg = err instanceof Error ? err.message : String(err);
  }

  return (
    <main className="min-h-screen p-8 max-w-4xl mx-auto space-y-8">
      <header className="flex items-center justify-between border-b pb-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">ModVault</h1>
          <p className="text-muted-foreground text-sm">Mod Compatibility Checker & Discovery</p>
        </div>
        <div className="flex items-center space-x-3">
          {session ? (
            <div className="flex items-center space-x-4">
              <span className="text-sm">
                Signed in as <strong className="text-primary">{session.username}</strong> ({session.role})
              </span>
              <form action={logoutAction}>
                <Button variant="outline" size="sm" type="submit">
                  Sign Out
                </Button>
              </form>
            </div>
          ) : (
            <div className="flex items-center space-x-2">
              <Link href="/login">
                <Button variant="outline" size="sm">
                  Sign In
                </Button>
              </Link>
              <Link href="/register">
                <Button size="sm">Create Account</Button>
              </Link>
            </div>
          )}
        </div>
      </header>

      <section className="grid gap-6 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Catalog Status</CardTitle>
            <CardDescription>Live database query via withUser</CardDescription>
          </CardHeader>
          <CardContent>
            {errorMsg ? (
              <p className="text-destructive text-sm">{errorMsg}</p>
            ) : (
              <div className="space-y-1">
                <p className="text-3xl font-semibold">{catalogCount}</p>
                <p className="text-xs text-muted-foreground">Total mods listed in mod_catalog_view</p>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Role-Based Access Test</CardTitle>
            <CardDescription>Test middleware routing rules</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            <div className="flex flex-wrap gap-2">
              <Link href="/admin">
                <Button variant="secondary" size="sm">
                  /admin (Admin only)
                </Button>
              </Link>
              <Link href="/curate">
                <Button variant="secondary" size="sm">
                  /curate (Curator & Admin)
                </Button>
              </Link>
              <Link href="/loadouts">
                <Button variant="secondary" size="sm">
                  /loadouts (Auth required)
                </Button>
              </Link>
              <Link href="/test-db">
                <Button variant="secondary" size="sm">
                  /test-db
                </Button>
              </Link>
            </div>
          </CardContent>
        </Card>
      </section>
    </main>
  );
}
