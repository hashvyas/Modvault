import Link from 'next/link';
import { Download } from 'lucide-react';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { embed, toPgVector } from '@/lib/embed';
import { formatErrorMessage } from '@/lib/errors';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent } from '@/components/ui/card';

export const dynamic = 'force-dynamic';

interface SearchResultItem {
  mod_id: string;
  name: string;
  summary: string | null;
  game_id: string;
  semantic_rank: number | null;
  keyword_rank: number | null;
  score: number;
  game_name: string;
  game_domain: string;
  category: string | null;
  rating_avg: number;
  download_count: number;
}

interface GameFilter {
  game_id: string;
  name: string;
  domain: string;
}

interface TagFilter {
  slug: string;
  name: string;
  count: number;
}

type Props = {
  searchParams: Promise<{
    q?: string;
    game?: string;
    tag?: string | string[];
  }>;
};

export default async function SearchPage({ searchParams }: Props) {
  const session = await getSession();
  const params = await searchParams;
  const q = (params.q ?? '').trim();
  const gameFilterParam = (params.game ?? '').trim();

  // Normalize tag parameter to an array of slugs
  let selectedTags: string[] = [];
  if (params.tag) {
    if (Array.isArray(params.tag)) {
      selectedTags = params.tag.filter(Boolean);
    } else {
      selectedTags = [params.tag].filter(Boolean);
    }
  }

  let results: SearchResultItem[] = [];
  let games: GameFilter[] = [];
  let availableTags: TagFilter[] = [];
  let errorMsg: string | null = null;
  let activeGameId: string | null = null;

  try {
    // Start embedding now so it overlaps with the filter queries below.
    const embeddingPromise = q
      ? embed(q).then(toPgVector).catch((embErr) => {
          console.error('Embedding generation failed, falling back to keyword search:', embErr);
          return null;
        })
      : Promise.resolve(null);

    // 1. Load games and tags for filters
    const filterData = await withUser(session, async (client) => {
      const gRes = await client.query<GameFilter>(
        'SELECT game_id, name, domain FROM games ORDER BY name'
      );
      const tRes = await client.query<TagFilter>(`
        SELECT t.slug, t.name, count(mt.mod_id)::int AS count
        FROM tags t
        JOIN mod_tags mt ON t.tag_id = mt.tag_id
        GROUP BY t.slug, t.name
        ORDER BY count(mt.mod_id) DESC, t.name ASC
      `);
      return { games: gRes.rows, tags: tRes.rows };
    });

    games = filterData.games;
    availableTags = filterData.tags;

    // Resolve game filter to UUID if set
    if (gameFilterParam) {
      const found = games.find(
        (g) => g.domain === gameFilterParam || g.game_id === gameFilterParam
      );
      if (found) {
        activeGameId = found.game_id;
      }
    }

    // 2. Perform search or browse
    const tagArrayArg = selectedTags.length > 0 ? selectedTags : null;

    if (q) {
      // Compute vector embedding for query text
      const pgEmbedding = await embeddingPromise;

      results = await withUser(session, async (client) => {
        const queryText = `
          WITH search_res AS (
            SELECT * FROM fn_search_mods_hybrid($1, $2::vector, $3::uuid, 50)
          )
          SELECT s.mod_id, s.name, s.summary, s.game_id, s.semantic_rank, s.keyword_rank, s.score,
                 g.name AS game_name, g.domain AS game_domain,
                 m.category, m.rating_avg, m.download_count
          FROM search_res s
          JOIN games g ON s.game_id = g.game_id
          JOIN mods m ON s.mod_id = m.mod_id
          WHERE ($4::text[] IS NULL OR s.mod_id IN (SELECT mod_id FROM fn_search_mods_by_tag(VARIADIC $4::text[])))
          ORDER BY s.score DESC, s.name
        `;
        const res = await client.query<SearchResultItem>(queryText, [
          q,
          pgEmbedding,
          activeGameId,
          tagArrayArg,
        ]);
        return res.rows;
      });
    } else if (tagArrayArg) {
      // Tag-only search
      results = await withUser(session, async (client) => {
        const queryText = `
          SELECT m.mod_id, m.name, m.summary, m.game_id,
                 NULL::int AS semantic_rank, NULL::int AS keyword_rank, 1.0::float8 AS score,
                 g.name AS game_name, g.domain AS game_domain,
                 m.category, m.rating_avg, m.download_count
          FROM fn_search_mods_by_tag(VARIADIC $1::text[]) m
          JOIN games g ON m.game_id = g.game_id
          WHERE ($2::uuid IS NULL OR m.game_id = $2::uuid)
          ORDER BY m.download_count DESC
        `;
        const res = await client.query<SearchResultItem>(queryText, [
          tagArrayArg,
          activeGameId,
        ]);
        return res.rows;
      });
    } else {
      // Default: show catalog sorted by popularity
      results = await withUser(session, async (client) => {
        const queryText = `
          SELECT m.mod_id, m.name, m.summary, m.game_id,
                 NULL::int AS semantic_rank, NULL::int AS keyword_rank, 1.0::float8 AS score,
                 g.name AS game_name, g.domain AS game_domain,
                 m.category, m.rating_avg, m.download_count
          FROM mods m
          JOIN games g ON m.game_id = g.game_id
          WHERE ($1::uuid IS NULL OR m.game_id = $1::uuid)
          ORDER BY m.download_count DESC
          LIMIT 30
        `;
        const res = await client.query<SearchResultItem>(queryText, [activeGameId]);
        return res.rows;
      });
    }
  } catch (err: unknown) {
    errorMsg = formatErrorMessage(err);
  }

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
      {/* Header and Search Form */}
      <div className="space-y-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Hybrid Mod Discovery</h1>
          <p className="text-muted-foreground text-sm">
            Reciprocal Rank Fusion of pgvector cosine similarity (384-dim HNSW) and PostgreSQL full-text search (GIN).
          </p>
        </div>

        <form action="/search" method="GET" className="grid gap-3 md:grid-cols-[1fr_220px_auto]">
          <Input
            type="search"
            name="q"
            defaultValue={q}
            placeholder="Search keywords or semantic meaning..."
            className="bg-card border-border"
          />

          <select
            name="game"
            defaultValue={gameFilterParam}
            className="h-8 rounded-lg border border-border bg-card px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
          >
            <option value="">All Games</option>
            {games.map((g) => (
              <option key={g.game_id} value={g.domain}>
                {g.name}
              </option>
            ))}
          </select>

          {/* Preserve tag filter on search submission */}
          {selectedTags.map((t) => (
            <input key={t} type="hidden" name="tag" value={t} />
          ))}

          <Button type="submit">Search</Button>
        </form>
      </div>

      {/* Tag Filter Pills */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
            Filter by Tags
          </span>
          {(selectedTags.length > 0 || gameFilterParam || q) && (
            <Link href="/search" className="text-xs text-cyan-400 hover:underline">
              Clear all filters
            </Link>
          )}
        </div>
        <div className="flex flex-wrap gap-2">
          {availableTags.map((tag) => {
            const isSelected = selectedTags.includes(tag.slug);
            // Toggle tag URL
            let newTags: string[];
            if (isSelected) {
              newTags = selectedTags.filter((t) => t !== tag.slug);
            } else {
              newTags = [...selectedTags, tag.slug];
            }

            const searchParamsObj = new URLSearchParams();
            if (q) searchParamsObj.set('q', q);
            if (gameFilterParam) searchParamsObj.set('game', gameFilterParam);
            newTags.forEach((t) => searchParamsObj.append('tag', t));

            return (
              <Link key={tag.slug} href={`/search?${searchParamsObj.toString()}`}>
                <Badge
                  variant={isSelected ? 'default' : 'outline'}
                  className={`cursor-pointer transition-all ${
                    isSelected
                      ? 'bg-cyan-600 text-white hover:bg-cyan-500 border-cyan-500'
                      : 'hover:bg-muted text-muted-foreground'
                  }`}
                >
                  {tag.name}
                  <span className="ml-1 text-[10px] opacity-70">({tag.count})</span>
                </Badge>
              </Link>
            );
          })}
        </div>
      </div>

      {/* Error Display */}
      {errorMsg && (
        <div className="p-4 rounded-lg bg-destructive/10 border border-destructive/30 text-destructive text-sm">
          Failed to perform search: {errorMsg}
        </div>
      )}

      {/* Results Header */}
      <div className="flex items-center justify-between border-b border-border pb-3">
        <span className="text-sm text-muted-foreground">
          Found <strong className="text-foreground">{results.length}</strong> {results.length === 1 ? 'mod' : 'mods'}
          {q && (
            <>
              {' '}for &ldquo;<span className="text-cyan-400 font-medium">{q}</span>&rdquo;
            </>
          )}
        </span>
      </div>

      {/* Results Grid */}
      {results.length === 0 ? (
        <div className="text-center py-16 space-y-4 border border-dashed border-border rounded-xl">
          <p className="text-lg font-medium text-muted-foreground">No mods matched your query.</p>
          <p className="text-sm text-muted-foreground max-w-md mx-auto">
            Try adjusting your search terms, choosing a broader description, or clearing tag filters.
          </p>
          <Link href="/search">
            <Button variant="outline" size="sm">
              Reset Filters
            </Button>
          </Link>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {results.map((mod) => (
            <Link key={mod.mod_id} href={`/mods/${mod.mod_id}`} className="group block">
              <Card className="h-full flex flex-col justify-between bg-card/50 hover:bg-card/80 border-border transition-all hover:border-cyan-500/40">
                <CardContent className="p-5 space-y-3 flex-1 flex flex-col justify-between">
                  <div className="space-y-2">
                    {/* Ranking & Match Badges */}
                    <div className="flex flex-wrap items-center gap-1.5">
                      {mod.semantic_rank != null && (
                        <Badge variant="meaning" className="text-[11px]">
                          Meaning #{mod.semantic_rank}
                        </Badge>
                      )}
                      {mod.keyword_rank != null && (
                        <Badge variant="keyword" className="text-[11px]">
                          Keyword #{mod.keyword_rank}
                        </Badge>
                      )}
                      {q && mod.score > 0 && (
                        <Badge variant="outline" className="text-[10px] font-mono text-muted-foreground">
                          RRF {(mod.score * 100).toFixed(2)}
                        </Badge>
                      )}
                    </div>

                    <h3 className="text-lg font-bold group-hover:text-cyan-300 transition-colors line-clamp-1">
                      {mod.name}
                    </h3>

                    <div className="flex items-center gap-2 text-xs text-muted-foreground">
                      <span className="font-medium text-foreground">{mod.game_name}</span>
                      {mod.category && (
                        <>
                          <span>&bull;</span>
                          <span>{mod.category}</span>
                        </>
                      )}
                    </div>

                    <p className="text-sm text-muted-foreground line-clamp-2 pt-1">
                      {mod.summary ?? 'No summary available.'}
                    </p>
                  </div>

                  <div className="flex items-center justify-between text-xs pt-3 border-t border-border/50 text-muted-foreground">
                    <span className="inline-flex items-center gap-1" title="Downloads">
                      <Download className="size-3.5" aria-label="Downloads" />
                      {Number(mod.download_count).toLocaleString()}
                    </span>
                  </div>
                </CardContent>
              </Card>
            </Link>
          ))}
        </div>
      )}
    </main>
  );
}
