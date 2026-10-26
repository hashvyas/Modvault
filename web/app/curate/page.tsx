import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';

export const dynamic = 'force-dynamic';

interface GameCompatSummary {
  game_id: string;
  name: string;
  domain: string;
  total_mods: number;
  compat_count: number;
  incompatible_count: number;
}

interface ConflictSummaryItem {
  mod_id: string;
  mod_name: string;
  incompatible_pairs: number;
  partial_pairs: number;
  declared_conflicts: number;
  dependent_mods: number;
}

export default async function CurateDashboardPage() {
  const session = await getSession();
  if (!session || (session.role !== 'curator' && session.role !== 'admin')) {
    redirect('/login?next=/curate');
  }

  let gameSummaries: GameCompatSummary[] = [];
  let topConflicts: ConflictSummaryItem[] = [];

  try {
    const data = await withUser(session, async (client) => {
      // 1. Fetch game summaries
      const gRes = await client.query<GameCompatSummary>(`
        SELECT g.game_id, g.name, g.domain,
               (SELECT count(*)::int FROM mods m WHERE m.game_id = g.game_id) AS total_mods,
               (SELECT count(*)::int FROM compatibility_matrix cm
                JOIN mod_versions v ON cm.version_a_id = v.version_id
                JOIN mods m ON v.mod_id = m.mod_id
                WHERE m.game_id = g.game_id) AS compat_count,
               (SELECT count(*)::int FROM compatibility_matrix cm
                JOIN mod_versions v ON cm.version_a_id = v.version_id
                JOIN mods m ON v.mod_id = m.mod_id
                WHERE m.game_id = g.game_id AND cm.status = 'incompatible') AS incompatible_count
        FROM games g
        ORDER BY g.name ASC
      `);

      // 2. Fetch top conflicting mods from mod_conflict_summary_view
      const confRes = await client.query<ConflictSummaryItem>(`
        SELECT mod_id, mod_name, incompatible_pairs, partial_pairs, declared_conflicts, dependent_mods
        FROM mod_conflict_summary_view
        WHERE (incompatible_pairs + partial_pairs + declared_conflicts) > 0
        ORDER BY (incompatible_pairs * 3 + partial_pairs * 2 + declared_conflicts) DESC
        LIMIT 10
      `);

      return { games: gRes.rows, conflicts: confRes.rows };
    });

    gameSummaries = data.games;
    topConflicts = data.conflicts;
  } catch (err) {
    console.error('Error fetching curator dashboard:', err);
  }

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-10">
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4 border-b border-border pb-6">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-extrabold tracking-tight">Curation Operations Hub</h1>
            <Badge variant="secondary" className="capitalize">
              {session.role}
            </Badge>
          </div>
          <p className="text-muted-foreground text-sm mt-1">
            Maintain mod relationships, verify matrix compatibility, and inspect potential conflicts.
          </p>
        </div>
      </div>

      {/* Game Heatmaps Quick Access */}
      <section className="space-y-4">
        <div>
          <h2 className="text-xl font-bold tracking-tight">Compatibility Heatmaps by Game</h2>
          <p className="text-xs text-muted-foreground">Select a game to open the pairwise matrix editor.</p>
        </div>

        <div className="grid gap-6 md:grid-cols-3">
          {gameSummaries.map((g) => (
            <Card key={g.game_id} className="bg-card/40 border-border hover:border-cyan-500/40 transition-colors">
              <CardHeader className="pb-3">
                <CardTitle className="text-lg flex items-center justify-between">
                  <span>{g.name}</span>
                  <Badge variant="outline" className="text-xs font-mono">{g.domain}</Badge>
                </CardTitle>
                <CardDescription className="text-xs">
                  {g.total_mods} curated mods listed
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 gap-2 text-xs">
                  <div className="p-2.5 rounded-lg bg-card/60 border border-border/60">
                    <div className="text-muted-foreground text-[10px] uppercase font-semibold">Total Pairs</div>
                    <div className="text-base font-bold text-foreground mt-0.5">{g.compat_count}</div>
                  </div>
                  <div className="p-2.5 rounded-lg bg-card/60 border border-border/60">
                    <div className="text-muted-foreground text-[10px] uppercase font-semibold">Incompatible</div>
                    <div className="text-base font-bold text-destructive mt-0.5">{g.incompatible_count}</div>
                  </div>
                </div>

                <Link href={`/games/${g.domain}/compat`} className="block">
                  <Button className="w-full bg-cyan-600 hover:bg-cyan-500 text-white font-medium text-xs">
                    Open Heatmap Grid &rarr;
                  </Button>
                </Link>
              </CardContent>
            </Card>
          ))}
        </div>
      </section>

      {/* Top Conflicting Mods from mod_conflict_summary_view */}
      <section className="space-y-4">
        <div>
          <h2 className="text-xl font-bold tracking-tight">Conflict Intelligence Summary</h2>
          <p className="text-xs text-muted-foreground">
            Aggregated from view <code className="text-cyan-400 font-mono">mod_conflict_summary_view</code>.
          </p>
        </div>

        <div className="rounded-xl border border-border overflow-hidden bg-card/25">
          <table className="w-full text-left text-xs">
            <thead className="bg-card/70 border-b border-border text-muted-foreground uppercase tracking-wider text-[11px]">
              <tr>
                <th className="px-4 py-3">Mod Name</th>
                <th className="px-4 py-3 text-center">Incompatible Pairs</th>
                <th className="px-4 py-3 text-center">Partial Pairs</th>
                <th className="px-4 py-3 text-center">Declared Conflicts</th>
                <th className="px-4 py-3 text-center">Dependent Mods</th>
                <th className="px-4 py-3 text-right">Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border/40 font-mono">
              {topConflicts.map((c) => (
                <tr key={c.mod_id} className="hover:bg-card/40 transition-colors">
                  <td className="px-4 py-3 font-semibold font-sans text-foreground">
                    {c.mod_name}
                  </td>
                  <td className="px-4 py-3 text-center">
                    <Badge variant={c.incompatible_pairs > 0 ? 'destructive' : 'outline'} className="text-[10px]">
                      {c.incompatible_pairs}
                    </Badge>
                  </td>
                  <td className="px-4 py-3 text-center">
                    <Badge variant={c.partial_pairs > 0 ? 'warning' : 'outline'} className="text-[10px]">
                      {c.partial_pairs}
                    </Badge>
                  </td>
                  <td className="px-4 py-3 text-center text-muted-foreground">
                    {c.declared_conflicts}
                  </td>
                  <td className="px-4 py-3 text-center text-muted-foreground">
                    {c.dependent_mods}
                  </td>
                  <td className="px-4 py-3 text-right font-sans">
                    <Link href={`/mods/${c.mod_id}`}>
                      <Button size="xs" variant="ghost" className="text-[11px]">
                        Inspect Mod &rarr;
                      </Button>
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </main>
  );
}
