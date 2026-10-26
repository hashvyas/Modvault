import Link from 'next/link';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { Button } from '@/components/ui/button';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';

export const dynamic = 'force-dynamic';

interface GameRow {
  game_id: string;
  name: string;
  domain: string;
  current_version: string | null;
  mod_count: number;
}

interface FeaturedModRow {
  mod_id: string;
  name: string;
  summary: string | null;
  category: string | null;
  rating_avg: number;
  download_count: number;
  game_name: string;
  game_domain: string;
}

interface LeaderboardRow {
  mod_id: string;
  mod_name: string;
  rating_count: number;
  rating_avg: number;
  bayes_score: number;
  download_count: number;
  rank_in_game: number;
  game_name: string;
  game_domain: string;
}

export default async function HomePage() {
  const session = await getSession();

  let games: GameRow[] = [];
  let featuredMods: FeaturedModRow[] = [];
  let leaderboard: LeaderboardRow[] = [];

  try {
    const data = await withUser(session, async (client) => {
      const gamesRes = await client.query<GameRow>(`
        SELECT g.game_id, g.name, g.domain, g.current_version,
               (SELECT count(*)::int FROM mods m WHERE m.game_id = g.game_id) AS mod_count
        FROM games g
        ORDER BY g.name ASC
      `);

      const featuredRes = await client.query<FeaturedModRow>(`
        SELECT m.mod_id, m.name, m.summary, m.category, m.rating_avg, m.download_count,
               g.name AS game_name, g.domain AS game_domain
        FROM mods m
        JOIN games g ON m.game_id = g.game_id
        WHERE m.is_featured = TRUE
        ORDER BY m.download_count DESC
        LIMIT 6
      `);

      const leaderboardRes = await client.query<LeaderboardRow>(`
        SELECT l.mod_id, l.mod_name, l.rating_count, l.rating_avg, l.bayes_score,
               l.download_count, l.rank_in_game, g.name AS game_name, g.domain AS game_domain
        FROM mv_game_leaderboard l
        JOIN games g ON l.game_id = g.game_id
        WHERE l.rank_in_game <= 3
        ORDER BY g.name, l.rank_in_game
      `);

      return {
        games: gamesRes.rows,
        featured: featuredRes.rows,
        leaderboard: leaderboardRes.rows,
      };
    });

    games = data.games;
    featuredMods = data.featured;
    leaderboard = data.leaderboard;
  } catch (err) {
    console.error('Error loading home page data:', err);
  }

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-10 space-y-16">
      {/* Hero & Search Bar */}
      <section className="text-center space-y-6 max-w-3xl mx-auto">
        <Badge variant="outline" className="border-cyan-500/40 text-cyan-400">
          PES Mini Project &bull; Hybrid Semantic Mod Intelligence
        </Badge>
        <h1 className="text-4xl sm:text-5xl font-extrabold tracking-tight">
          Pre-flight mod compatibility and smart discovery.
        </h1>
        <p className="text-muted-foreground text-lg">
          Detect missing dependencies, conflicting pairs, and game version mismatches before launching.
          Find mods with hybrid semantic and keyword search.
        </p>

        <form action="/search" method="GET" className="flex items-center gap-2 max-w-2xl mx-auto pt-2">
          <Input
            type="search"
            name="q"
            placeholder="Search mods by keywords or meaning (e.g., 'make the menus look better')..."
            className="h-12 px-4 text-base bg-card/80 border-border focus-visible:ring-cyan-500"
          />
          <Button type="submit" size="lg" className="h-12 px-6 bg-cyan-600 hover:bg-cyan-500 text-white font-medium">
            Search
          </Button>
        </form>
      </section>

      {/* Three Game Cards */}
      <section className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold tracking-tight">Supported Games</h2>
          <p className="text-muted-foreground text-sm">Select a game to browse curated mods and compatibility.</p>
        </div>
        <div className="grid gap-6 md:grid-cols-3">
          {games.map((g) => (
            <Link key={g.game_id} href={`/games/${g.domain}`} className="group block">
              <Card className="h-full bg-card/50 hover:bg-card/80 border-border transition-all hover:border-cyan-500/50 hover:shadow-lg hover:shadow-cyan-500/5">
                <CardHeader>
                  <div className="flex items-center justify-between">
                    <CardTitle className="text-xl group-hover:text-cyan-400 transition-colors">
                      {g.name}
                    </CardTitle>
                    <Badge variant="secondary" className="font-mono text-xs">
                      {g.domain}
                    </Badge>
                  </div>
                  <CardDescription>
                    Current version: <span className="font-mono text-foreground font-medium">{g.current_version ?? 'Latest'}</span>
                  </CardDescription>
                </CardHeader>
                <CardContent className="flex justify-between items-center text-sm">
                  <span className="text-muted-foreground">{g.mod_count} Curated Mods</span>
                  <span className="text-cyan-400 group-hover:translate-x-1 transition-transform inline-flex items-center text-xs font-semibold">
                    Explore &rarr;
                  </span>
                </CardContent>
              </Card>
            </Link>
          ))}
        </div>
      </section>

      {/* Featured Mods */}
      {featuredMods.length > 0 && (
        <section className="space-y-6">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-2xl font-bold tracking-tight">Featured Mods</h2>
              <p className="text-muted-foreground text-sm">Top verified community essentials with high ratings.</p>
            </div>
            <Link href="/search">
              <Button variant="ghost" size="sm" className="text-xs">
                View all mods &rarr;
              </Button>
            </Link>
          </div>
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {featuredMods.map((mod) => (
              <Link key={mod.mod_id} href={`/mods/${mod.mod_id}`} className="group block">
                <Card className="h-full flex flex-col justify-between bg-card/40 hover:bg-card/70 border-border transition-all hover:border-border/80">
                  <CardHeader className="pb-3">
                    <div className="flex items-start justify-between gap-2">
                      <CardTitle className="text-lg group-hover:text-cyan-300 transition-colors line-clamp-1">
                        {mod.name}
                      </CardTitle>
                      <Badge variant="outline" className="text-xs shrink-0">
                        {mod.game_name}
                      </Badge>
                    </div>
                    {mod.category && (
                      <p className="text-xs text-muted-foreground">{mod.category}</p>
                    )}
                  </CardHeader>
                  <CardContent className="space-y-4 flex-1 flex flex-col justify-between">
                    <p className="text-sm text-muted-foreground line-clamp-2">
                      {mod.summary ?? 'No summary available.'}
                    </p>
                    <div className="flex items-center justify-between text-xs pt-2 border-t border-border/50 text-muted-foreground">
                      <span className="flex items-center gap-1 font-medium text-amber-400">
                        ★ {Number(mod.rating_avg).toFixed(1)}
                      </span>
                      <span>{Number(mod.download_count).toLocaleString()} downloads</span>
                    </div>
                  </CardContent>
                </Card>
              </Link>
            ))}
          </div>
        </section>
      )}

      {/* Leaderboard Strip from mv_game_leaderboard */}
      {leaderboard.length > 0 && (
        <section className="space-y-6">
          <div>
            <h2 className="text-2xl font-bold tracking-tight">Community Leaderboard</h2>
            <p className="text-muted-foreground text-sm">
              Materialized leaderboard (<code className="text-xs text-cyan-400 font-mono">mv_game_leaderboard</code>) ranked by Bayesian rating and download popularity.
            </p>
          </div>
          <div className="grid gap-6 md:grid-cols-3">
            {games.map((g) => {
              const gameMods = leaderboard.filter((item) => item.game_name === g.name);
              return (
                <Card key={g.game_id} className="bg-card/30 border-border">
                  <CardHeader className="pb-3 border-b border-border/40">
                    <CardTitle className="text-base flex items-center justify-between">
                      <span>{g.name}</span>
                      <Badge variant="secondary" className="text-[10px]">Top 3</Badge>
                    </CardTitle>
                  </CardHeader>
                  <CardContent className="p-0 divide-y divide-border/40">
                    {gameMods.map((item) => (
                      <Link
                        key={item.mod_id}
                        href={`/mods/${item.mod_id}`}
                        className="flex items-center justify-between p-3.5 hover:bg-card/70 transition-colors group"
                      >
                        <div className="flex items-center space-x-3 overflow-hidden">
                          <span
                            className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold shrink-0 ${
                              item.rank_in_game === 1
                                ? 'bg-amber-500/20 text-amber-400 border border-amber-500/40'
                                : item.rank_in_game === 2
                                ? 'bg-slate-400/20 text-slate-300 border border-slate-400/40'
                                : 'bg-amber-800/20 text-amber-600 border border-amber-700/40'
                            }`}
                          >
                            #{item.rank_in_game}
                          </span>
                          <span className="text-sm font-medium truncate group-hover:text-cyan-300 transition-colors">
                            {item.mod_name}
                          </span>
                        </div>
                        <div className="text-right shrink-0 pl-2">
                          <div className="text-xs font-mono font-semibold text-cyan-400">
                            {Number(item.bayes_score).toFixed(2)}
                          </div>
                          <div className="text-[10px] text-muted-foreground">
                            {Number(item.download_count).toLocaleString()} dl
                          </div>
                        </div>
                      </Link>
                    ))}
                  </CardContent>
                </Card>
              );
            })}
          </div>
        </section>
      )}
    </main>
  );
}
