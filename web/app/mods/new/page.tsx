import { redirect } from 'next/navigation';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { PublishForm } from '@/components/publish-form';

export const dynamic = 'force-dynamic';

interface GameItem {
  game_id: string;
  name: string;
  domain: string;
}

export default async function NewModPage() {
  const session = await getSession();

  if (!session) {
    redirect('/login?next=/mods/new');
  }

  let games: GameItem[] = [];

  try {
    games = await withUser(session, async (client) => {
      const res = await client.query<GameItem>(
        'SELECT game_id, name, domain FROM games ORDER BY name ASC'
      );
      return res.rows;
    });
  } catch (err) {
    console.error('Error fetching games for mod publication:', err);
  }

  return (
    <main className="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-10 space-y-6">
      <div>
        <h1 className="text-3xl font-extrabold tracking-tight">Publish a Mod</h1>
        <p className="text-muted-foreground text-sm mt-1">
          Add a new mod entry to the ModVault catalog with automated vector embedding generation.
        </p>
      </div>

      <Card className="bg-card/50 border-border">
        <CardHeader>
          <CardTitle>Mod Information</CardTitle>
          <CardDescription>
            Stored via PostgreSQL stored procedure <code className="text-cyan-400 font-mono">pr_publish_mod</code> with immediate semantic indexing.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <PublishForm games={games} />
        </CardContent>
      </Card>
    </main>
  );
}
