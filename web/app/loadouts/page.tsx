import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { Badge } from '@/components/ui/badge';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { CreateLoadoutForm } from '@/components/create-loadout-form';
import { LoadoutImportForm } from '@/components/loadout-export-import';

export const dynamic = 'force-dynamic';

interface UserLoadoutItem {
  loadout_id: string;
  name: string;
  description: string | null;
  game_version: string | null;
  is_public: boolean;
  game_name: string;
  game_domain: string;
  score: number;
  status: 'healthy' | 'warnings' | 'broken';
  error_count: number;
  warning_count: number;
  mod_count: number;
}

interface GameItem {
  game_id: string;
  name: string;
  domain: string;
  current_version: string | null;
}

interface PublicLoadoutItem {
  loadout_id: string;
  name: string;
  game_version: string | null;
  username: string;
  game_name: string;
  score: number;
  status: 'healthy' | 'warnings' | 'broken';
  mod_count: number;
}

export default async function LoadoutsDashboardPage() {
  const session = await getSession();
  if (!session) {
    redirect('/login?next=/loadouts');
  }

  const userId = session.sub;
  let myLoadouts: UserLoadoutItem[] = [];
  let games: GameItem[] = [];
  let publicLoadouts: PublicLoadoutItem[] = [];

  try {
    const data = await withUser(session, async (client) => {
      // 1. Fetch user loadouts
      const loadoutsRes = await client.query<UserLoadoutItem>(
        `SELECT l.loadout_id, l.name, l.description, l.game_version, l.is_public,
                g.name AS game_name, g.domain AS game_domain,
                lh.score, lh.status, lh.error_count, lh.warning_count,
                (SELECT count(*)::int FROM loadout_mods lm WHERE lm.loadout_id = l.loadout_id) AS mod_count
         FROM loadouts l
         JOIN games g ON l.game_id = g.game_id
         JOIN loadout_health_view lh ON l.loadout_id = lh.loadout_id
         WHERE l.user_id = $1
         ORDER BY l.updated_at DESC`,
        [userId]
      );

      // 2. Fetch games for creation form
      const gamesRes = await client.query<GameItem>(
        'SELECT game_id, name, domain, current_version FROM games ORDER BY name ASC'
      );

      // 3. Fetch recent public loadouts
      const pubRes = await client.query<PublicLoadoutItem>(
        `SELECT l.loadout_id, l.name, l.game_version, u.username, g.name AS game_name,
                lh.score, lh.status,
                (SELECT count(*)::int FROM loadout_mods lm WHERE lm.loadout_id = l.loadout_id) AS mod_count
         FROM loadouts l
         JOIN users u ON l.user_id = u.user_id
         JOIN games g ON l.game_id = g.game_id
         JOIN loadout_health_view lh ON l.loadout_id = lh.loadout_id
         WHERE l.is_public = TRUE AND l.user_id <> $1
         ORDER BY l.created_at DESC
         LIMIT 6`,
        [userId]
      );

      return {
        myLoadouts: loadoutsRes.rows,
        games: gamesRes.rows,
        publicLoadouts: pubRes.rows,
      };
    });

    myLoadouts = data.myLoadouts;
    games = data.games;
    publicLoadouts = data.publicLoadouts;
  } catch (err) {
    console.error('Error loading loadouts dashboard:', err);
  }

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-10">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-extrabold tracking-tight">Loadout Manager</h1>
        <p className="text-muted-foreground text-sm mt-1">
          Build, diagnose, auto-sort, and verify your mod loadouts with automated conflict detection.
        </p>
      </div>

      {/* Main Grid: My Loadouts vs New / Import forms */}
      <div className="grid gap-8 lg:grid-cols-3">
        {/* Left Column (2 cols): My Loadouts */}
        <div className="lg:col-span-2 space-y-6">
          <div className="flex items-center justify-between border-b border-border pb-3">
            <h2 className="text-xl font-bold tracking-tight">My Loadouts</h2>
            <span className="text-xs text-muted-foreground font-mono">{myLoadouts.length} total</span>
          </div>

          {myLoadouts.length === 0 ? (
            <div className="p-12 rounded-2xl border border-dashed border-border text-center space-y-3">
              <p className="text-muted-foreground text-sm">You haven&apos;t created any loadouts yet.</p>
              <p className="text-xs text-muted-foreground">
                Create one using the form on the right or import an existing manifest JSON.
              </p>
            </div>
          ) : (
            <div className="grid gap-4 sm:grid-cols-2">
              {myLoadouts.map((l) => {
                let badgeVariant: 'success' | 'warning' | 'destructive' = 'success';
                let scoreRing = 'border-emerald-500/40 text-emerald-400 bg-emerald-500/10';
                if (l.status === 'broken') {
                  badgeVariant = 'destructive';
                  scoreRing = 'border-rose-500/40 text-rose-400 bg-rose-500/10';
                } else if (l.status === 'warnings') {
                  badgeVariant = 'warning';
                  scoreRing = 'border-amber-500/40 text-amber-400 bg-amber-500/10';
                }

                return (
                  <Link key={l.loadout_id} href={`/loadouts/${l.loadout_id}`} className="group block">
                    <Card className="h-full flex flex-col justify-between bg-card/40 hover:bg-card/70 border-border transition-all hover:border-cyan-500/40">
                      <CardHeader className="pb-3">
                        <div className="flex items-start justify-between gap-2">
                          <CardTitle className="text-base group-hover:text-cyan-300 transition-colors line-clamp-1">
                            {l.name}
                          </CardTitle>
                          <Badge variant={badgeVariant} className="text-[10px] uppercase font-bold shrink-0">
                            {l.status}
                          </Badge>
                        </div>
                        <div className="flex items-center gap-2 text-xs text-muted-foreground">
                          <span>{l.game_name}</span>
                          {l.game_version && (
                            <>
                              <span>&bull;</span>
                              <span className="font-mono">v{l.game_version}</span>
                            </>
                          )}
                        </div>
                      </CardHeader>
                      <CardContent className="space-y-4 flex-1 flex flex-col justify-between">
                        {l.description ? (
                          <p className="text-xs text-muted-foreground line-clamp-2">
                            {l.description}
                          </p>
                        ) : (
                          <div />
                        )}

                        <div className="flex items-center justify-between pt-3 border-t border-border/50 text-xs">
                          <div className="flex items-center gap-2">
                            <span
                              className={`w-8 h-8 rounded-full border flex items-center justify-center font-mono font-bold text-xs ${scoreRing}`}
                            >
                              {l.score}
                            </span>
                            <span className="text-muted-foreground">{l.mod_count} mods</span>
                          </div>
                          <span className="text-cyan-400 font-semibold group-hover:translate-x-1 transition-transform inline-flex items-center text-xs">
                            Manage &rarr;
                          </span>
                        </div>
                      </CardContent>
                    </Card>
                  </Link>
                );
              })}
            </div>
          )}

          {/* Public Community Loadouts */}
          {publicLoadouts.length > 0 && (
            <div className="space-y-4 pt-6 border-t border-border">
              <h3 className="text-lg font-bold tracking-tight">Community Shared Loadouts</h3>
              <div className="grid gap-3 sm:grid-cols-2">
                {publicLoadouts.map((pub) => (
                  <Link key={pub.loadout_id} href={`/loadouts/${pub.loadout_id}`} className="group block">
                    <div className="p-3.5 rounded-xl border border-border bg-card/30 hover:bg-card/60 transition-colors flex items-center justify-between">
                      <div className="space-y-0.5 overflow-hidden">
                        <div className="text-xs font-semibold truncate group-hover:text-cyan-300">
                          {pub.name}
                        </div>
                        <div className="text-[10px] text-muted-foreground">
                          By <span className="text-foreground">{pub.username}</span> &bull; {pub.game_name}
                        </div>
                      </div>
                      <div className="flex items-center gap-2 shrink-0">
                        <span className="text-[10px] text-muted-foreground">{pub.mod_count} mods</span>
                        <Badge
                          variant={pub.status === 'healthy' ? 'success' : pub.status === 'broken' ? 'destructive' : 'warning'}
                          className="text-[9px] uppercase"
                        >
                          {pub.status}
                        </Badge>
                      </div>
                    </div>
                  </Link>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Right Column (1 col): Creation and Import forms */}
        <div className="space-y-6">
          <Card className="bg-card/40 border-border">
            <CardHeader className="pb-3">
              <CardTitle className="text-base">Create New Loadout</CardTitle>
              <CardDescription className="text-xs">
                Initialize an empty loadout for mod assignment and order management.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <CreateLoadoutForm games={games} />
            </CardContent>
          </Card>

          <Card className="bg-card/40 border-border">
            <CardHeader className="pb-3">
              <CardTitle className="text-base">Import Loadout</CardTitle>
              <CardDescription className="text-xs">
                Import from a <code className="font-mono text-cyan-400">modvault-loadout/1</code> JSON manifest.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <LoadoutImportForm />
            </CardContent>
          </Card>
        </div>
      </div>
    </main>
  );
}
