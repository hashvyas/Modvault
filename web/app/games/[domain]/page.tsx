import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';

export const dynamic = 'force-dynamic';

interface GameInfo {
  game_id: string;
  name: string;
  domain: string;
  current_version: string | null;
}

interface ModCatalogItem {
  mod_id: string;
  mod_name: string;
  author_name: string | null;
  category: string | null;
  created_at: string;
  download_count: number;
  rating_avg: number;
  rating_count: number;
  summary: string | null;
}

type Props = {
  params: Promise<{ domain: string }>;
  searchParams: Promise<{
    sort?: string;
    category?: string;
    tag?: string;
    page?: string;
  }>;
};

export default async function GameBrowsePage({ params, searchParams }: Props) {
  const session = await getSession();
  const { domain } = await params;
  const sParams = await searchParams;

  const currentSort = sParams.sort || 'downloads';
  const currentCategory = sParams.category || '';
  const currentTag = sParams.tag || '';
  const currentPage = Math.max(1, parseInt(sParams.page || '1', 10));
  const PAGE_SIZE = 24;
  const offset = (currentPage - 1) * PAGE_SIZE;

  let game: GameInfo | null = null;
  let categories: string[] = [];
  let tags: { slug: string; name: string }[] = [];
  let mods: ModCatalogItem[] = [];
  let totalCount = 0;

  try {
    const data = await withUser(session, async (client) => {
      // 1. Fetch game details
      const gameRes = await client.query<GameInfo>(
        'SELECT game_id, name, domain, current_version FROM games WHERE domain = $1',
        [domain]
      );
      if (gameRes.rows.length === 0) {
        return null;
      }
      const g = gameRes.rows[0];

      // 2. Fetch distinct categories for this game
      const catRes = await client.query<{ category: string }>(
        'SELECT DISTINCT category FROM mods WHERE game_id = $1 AND category IS NOT NULL ORDER BY category ASC',
        [g.game_id]
      );

      // 3. Fetch distinct tags for this game
      const tagRes = await client.query<{ slug: string; name: string }>(`
        SELECT DISTINCT t.slug, t.name
        FROM tags t
        JOIN mod_tags mt ON t.tag_id = mt.tag_id
        JOIN mods m ON mt.mod_id = m.mod_id
        WHERE m.game_id = $1
        ORDER BY t.name ASC
      `, [g.game_id]);

      // 4. Construct SQL for sorted, filtered, paginated query
      let orderClause = 'ORDER BY m.download_count DESC, m.name';
      if (currentSort === 'rating') {
        orderClause = 'ORDER BY m.rating_avg DESC, m.rating_count DESC, m.download_count DESC';
      } else if (currentSort === 'newest') {
        orderClause = 'ORDER BY v.created_at DESC, m.name';
      }

      const conditions: string[] = ['m.game_id = $1'];
      const queryParams: unknown[] = [g.game_id];

      if (currentCategory) {
        queryParams.push(currentCategory);
        conditions.push(`m.category = $${queryParams.length}`);
      }

      if (currentTag) {
        queryParams.push([currentTag]);
        conditions.push(`m.mod_id IN (SELECT mod_id FROM fn_search_mods_by_tag(VARIADIC $${queryParams.length}::text[]))`);
      }

      const whereClause = conditions.join(' AND ');

      // Total count query
      const countRes = await client.query<{ count: string }>(
        `SELECT count(*)::text as count
         FROM mod_catalog_view v
         JOIN mods m ON v.mod_id = m.mod_id
         WHERE ${whereClause}`,
        queryParams
      );
      const total = parseInt(countRes.rows[0]?.count ?? '0', 10);

      // Paginated mods query
      queryParams.push(PAGE_SIZE);
      const limitParamIdx = queryParams.length;
      queryParams.push(offset);
      const offsetParamIdx = queryParams.length;

      const modsRes = await client.query<ModCatalogItem>(
        `SELECT v.mod_id, v.mod_name, v.author_name, v.category, v.created_at,
                m.download_count, m.rating_avg, m.rating_count, m.summary
         FROM mod_catalog_view v
         JOIN mods m ON v.mod_id = m.mod_id
         WHERE ${whereClause}
         ${orderClause}
         LIMIT $${limitParamIdx} OFFSET $${offsetParamIdx}`,
        queryParams
      );

      return {
        game: g,
        categories: catRes.rows.map((r) => r.category),
        tags: tagRes.rows,
        mods: modsRes.rows,
        totalCount: total,
      };
    });

    if (!data) {
      notFound();
    }

    game = data.game;
    categories = data.categories;
    tags = data.tags;
    mods = data.mods;
    totalCount = data.totalCount;
  } catch (err) {
    console.error('Error fetching game catalog:', err);
    notFound();
  }

  const totalPages = Math.ceil(totalCount / PAGE_SIZE);

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
      {/* Game Header Banner */}
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4 border-b border-border pb-6">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-extrabold tracking-tight">{game.name}</h1>
            <Badge variant="secondary" className="font-mono text-xs">
              {game.domain}
            </Badge>
          </div>
          <p className="text-muted-foreground text-sm mt-1">
            Standard Game Version: <span className="font-mono text-foreground font-semibold">{game.current_version ?? 'Any'}</span> &bull; {totalCount} total catalog mods
          </p>
        </div>

        <div className="flex items-center gap-3">
          <Link href={`/search?game=${game.domain}`}>
            <Button variant="outline" size="sm">
              Search in {game.name}
            </Button>
          </Link>
          <Link href="/mods/new">
            <Button size="sm">
              Publish Mod
            </Button>
          </Link>
        </div>
      </div>

      {/* Filters and Sorting Controls */}
      <form method="GET" className="grid gap-3 sm:grid-cols-2 md:grid-cols-4 bg-card/40 p-4 rounded-xl border border-border">
        {/* Category Filter */}
        <div className="space-y-1">
          <label className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
            Category
          </label>
          <select
            name="category"
            defaultValue={currentCategory}
            className="w-full h-9 rounded-md border border-border bg-card px-2.5 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
          >
            <option value="">All Categories</option>
            {categories.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </div>

        {/* Tag Filter */}
        <div className="space-y-1">
          <label className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
            Tag
          </label>
          <select
            name="tag"
            defaultValue={currentTag}
            className="w-full h-9 rounded-md border border-border bg-card px-2.5 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
          >
            <option value="">All Tags</option>
            {tags.map((t) => (
              <option key={t.slug} value={t.slug}>
                {t.name}
              </option>
            ))}
          </select>
        </div>

        {/* Sort Order */}
        <div className="space-y-1">
          <label className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
            Sort By
          </label>
          <select
            name="sort"
            defaultValue={currentSort}
            className="w-full h-9 rounded-md border border-border bg-card px-2.5 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
          >
            <option value="downloads">Most Downloaded</option>
            <option value="rating">Highest Rated</option>
            <option value="newest">Newest Added</option>
          </select>
        </div>

        {/* Apply & Reset */}
        <div className="flex items-end gap-2">
          <Button type="submit" size="sm" className="flex-1 bg-cyan-600 hover:bg-cyan-500 text-white font-medium">
            Filter
          </Button>
          {(currentCategory || currentTag || currentSort !== 'downloads') && (
            <Link href={`/games/${domain}`}>
              <Button variant="ghost" size="sm" type="button" className="text-xs">
                Reset
              </Button>
            </Link>
          )}
        </div>
      </form>

      {/* Mods Grid */}
      {mods.length === 0 ? (
        <div className="text-center py-16 space-y-4 border border-dashed border-border rounded-xl">
          <p className="text-lg font-medium text-muted-foreground">No mods match the selected filters.</p>
          <Link href={`/games/${domain}`}>
            <Button variant="outline" size="sm">
              Clear Filters
            </Button>
          </Link>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {mods.map((mod) => (
            <Link key={mod.mod_id} href={`/mods/${mod.mod_id}`} className="group block">
              <Card className="h-full flex flex-col justify-between bg-card/40 hover:bg-card/70 border-border transition-all hover:border-cyan-500/40">
                <CardContent className="p-5 space-y-3 flex-1 flex flex-col justify-between">
                  <div className="space-y-2">
                    <div className="flex items-start justify-between gap-2">
                      <h3 className="text-base font-bold group-hover:text-cyan-300 transition-colors line-clamp-1">
                        {mod.mod_name}
                      </h3>
                      {mod.category && (
                        <Badge variant="outline" className="text-[10px] shrink-0">
                          {mod.category}
                        </Badge>
                      )}
                    </div>

                    <div className="text-xs text-muted-foreground">
                      By <span className="text-foreground font-medium">{mod.author_name ?? 'Unknown Author'}</span>
                    </div>

                    <p className="text-sm text-muted-foreground line-clamp-2 pt-1">
                      {mod.summary ?? 'No summary available.'}
                    </p>
                  </div>

                  <div className="flex items-center justify-between text-xs pt-3 border-t border-border/50 text-muted-foreground">
                    <span className="flex items-center gap-1 text-amber-400 font-medium">
                      ★ {Number(mod.rating_avg).toFixed(1)}
                      <span className="text-muted-foreground text-[10px]">({mod.rating_count})</span>
                    </span>
                    <span>{Number(mod.download_count).toLocaleString()} dl</span>
                  </div>
                </CardContent>
              </Card>
            </Link>
          ))}
        </div>
      )}

      {/* Pagination Controls */}
      {totalPages > 1 && (
        <div className="flex items-center justify-center gap-2 pt-4">
          {currentPage > 1 && (
            <Link
              href={`/games/${domain}?page=${currentPage - 1}&sort=${currentSort}&category=${currentCategory}&tag=${currentTag}`}
            >
              <Button variant="outline" size="sm">
                &larr; Previous
              </Button>
            </Link>
          )}

          <span className="text-xs text-muted-foreground px-3">
            Page <strong className="text-foreground">{currentPage}</strong> of <strong>{totalPages}</strong>
          </span>

          {currentPage < totalPages && (
            <Link
              href={`/games/${domain}?page=${currentPage + 1}&sort=${currentSort}&category=${currentCategory}&tag=${currentTag}`}
            >
              <Button variant="outline" size="sm">
                Next &rarr;
              </Button>
            </Link>
          )}
        </div>
      )}
    </main>
  );
}
