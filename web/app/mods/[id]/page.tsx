import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  VersionTable,
  AddToLoadoutPicker,
  ReviewSection,
} from '@/components/mod-actions';
import {
  DependencyGraph,
  type DependencyNodeData,
} from '@/components/dependency-graph';

export const dynamic = 'force-dynamic';

interface ModDetailRow {
  mod_id: string;
  name: string;
  summary: string | null;
  category: string | null;
  nexus_author: string | null;
  nexus_mod_id: string | null;
  download_count: number;
  rating_avg: number;
  rating_count: number;
  game_id: string;
  game_name: string;
  game_domain: string;
  author_name: string | null;
}

interface ModStatsRow {
  version_count: number;
  dependent_count: number;
  conflict_count: number;
  rating_avg: number;
  rating_count: number;
  download_count: number;
}

interface VersionRow {
  version_id: string;
  semver: string;
  is_primary: boolean;
  supported_game_versions: string[];
  changelog: string | null;
  uploaded_at: string;
}

interface CompatRow {
  compat_id: string;
  status: 'compatible' | 'incompatible' | 'partial' | 'unknown';
  conflict_detail: Record<string, unknown> | null;
  semver_a: string;
  mod_a_id: string;
  mod_a_name: string;
  semver_b: string;
  mod_b_id: string;
  mod_b_name: string;
  verified_by_username: string | null;
}

interface ReviewRow {
  review_id: string;
  user_id: string;
  rating: number;
  body: string | null;
  created_at: string;
  username: string;
}

interface TagItem {
  tag_id: string;
  name: string;
  slug: string;
}

interface LoadoutOption {
  loadout_id: string;
  name: string;
  game_version: string | null;
}

type Props = {
  params: Promise<{ id: string }>;
};

export default async function ModDetailPage({ params }: Props) {
  const session = await getSession();
  const { id } = await params;

  let mod: ModDetailRow | null = null;
  let stats: ModStatsRow | null = null;
  let versions: VersionRow[] = [];
  let dependencies: DependencyNodeData[] = [];
  let compatRows: CompatRow[] = [];
  let reviews: ReviewRow[] = [];
  let tags: TagItem[] = [];
  let userLoadouts: LoadoutOption[] = [];

  try {
    const data = await withUser(session, async (client) => {
      // 1. Fetch Mod Details
      const modRes = await client.query<ModDetailRow>(
        `SELECT m.mod_id, m.name, m.summary, m.category, m.nexus_author, m.nexus_mod_id,
                m.download_count, m.rating_avg, m.rating_count, m.game_id,
                g.name AS game_name, g.domain AS game_domain,
                coalesce(u.username, m.nexus_author) AS author_name
         FROM mods m
         JOIN games g ON m.game_id = g.game_id
         LEFT JOIN users u ON m.author_id = u.user_id
         WHERE m.mod_id = $1`,
        [id]
      );

      if (modRes.rows.length === 0) {
        return null;
      }
      const modData = modRes.rows[0];

      // 2. Fetch Stats via fn_mod_stats
      const statsRes = await client.query<ModStatsRow>(
        'SELECT * FROM fn_mod_stats($1)',
        [id]
      );

      // 3. Fetch Versions
      const versionsRes = await client.query<VersionRow>(
        `SELECT version_id, semver, is_primary, supported_game_versions, changelog, uploaded_at::text
         FROM mod_versions
         WHERE mod_id = $1
         ORDER BY is_primary DESC, uploaded_at DESC`,
        [id]
      );

      const primaryVer = versionsRes.rows.find((v) => v.is_primary) ?? versionsRes.rows[0];

      // 4. Fetch Dependency Tree via fn_get_mod_dependency_tree
      let deps: DependencyNodeData[] = [];
      if (primaryVer) {
        const depRes = await client.query<DependencyNodeData>(
          'SELECT version_id, mod_id, mod_name, parent_version_id, depth, dep_type, path FROM fn_get_mod_dependency_tree($1)',
          [primaryVer.version_id]
        );
        deps = depRes.rows;
      }

      // 5. Fetch Compatibility Matrix Rows
      const compatRes = await client.query<CompatRow>(
        `SELECT cm.compat_id, cm.status, cm.conflict_detail,
                va.semver AS semver_a, ma.mod_id AS mod_a_id, ma.name AS mod_a_name,
                vb.semver AS semver_b, mb.mod_id AS mod_b_id, mb.name AS mod_b_name,
                u.username AS verified_by_username
         FROM compatibility_matrix cm
         JOIN mod_versions va ON cm.version_a_id = va.version_id
         JOIN mods ma ON va.mod_id = ma.mod_id
         JOIN mod_versions vb ON cm.version_b_id = vb.version_id
         JOIN mods mb ON vb.mod_id = mb.mod_id
         LEFT JOIN users u ON cm.verified_by = u.user_id
         WHERE ma.mod_id = $1 OR mb.mod_id = $1
         ORDER BY cm.status, cm.updated_at DESC`,
        [id]
      );

      // 6. Fetch Reviews
      const revRes = await client.query<ReviewRow>(
        `SELECT r.review_id, r.user_id, r.rating, r.body, r.created_at::text, u.username
         FROM reviews r
         JOIN users u ON r.user_id = u.user_id
         WHERE r.mod_id = $1
         ORDER BY r.created_at DESC`,
        [id]
      );

      // 7. Fetch Tags
      const tagRes = await client.query<TagItem>(
        `SELECT t.tag_id, t.name, t.slug
         FROM tags t
         JOIN mod_tags mt ON t.tag_id = mt.tag_id
         WHERE mt.mod_id = $1
         ORDER BY t.name ASC`,
        [id]
      );

      // 8. Fetch User's Loadouts for this game (if logged in)
      let loadouts: LoadoutOption[] = [];
      const currentUserId = session?.sub;
      if (currentUserId) {
        const lRes = await client.query<LoadoutOption>(
          `SELECT loadout_id, name, game_version
           FROM loadouts
           WHERE user_id = $1 AND game_id = $2
           ORDER BY name ASC`,
          [currentUserId, modData.game_id]
        );
        loadouts = lRes.rows;
      }

      return {
        mod: modData,
        stats: statsRes.rows[0] ?? null,
        versions: versionsRes.rows,
        dependencies: deps,
        compatRows: compatRes.rows,
        reviews: revRes.rows,
        tags: tagRes.rows,
        userLoadouts: loadouts,
      };
    });

    if (!data) {
      notFound();
    }

    mod = data.mod;
    stats = data.stats;
    versions = data.versions;
    dependencies = data.dependencies;
    compatRows = data.compatRows;
    reviews = data.reviews;
    tags = data.tags;
    userLoadouts = data.userLoadouts;
  } catch (err) {
    console.error('Error loading mod details:', err);
    notFound();
  }

  const nexusUrl =
    mod.nexus_mod_id && mod.game_domain
      ? `https://www.nexusmods.com/${mod.game_domain}/mods/${mod.nexus_mod_id}`
      : null;

  const canPromote = session?.role === 'curator' || session?.role === 'admin';
  const currentUserId = session?.sub || null;

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-10">
      {/* Mod Header */}
      <section className="space-y-4 border-b border-border pb-8">
        <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-4">
          <div className="space-y-2 max-w-3xl">
            <div className="flex items-center gap-2">
              <Link href={`/games/${mod.game_domain}`}>
                <Badge variant="secondary" className="hover:bg-secondary/70">
                  {mod.game_name}
                </Badge>
              </Link>
              {mod.category && (
                <Badge variant="outline" className="text-muted-foreground">
                  {mod.category}
                </Badge>
              )}
            </div>

            <h1 className="text-3xl sm:text-4xl font-extrabold tracking-tight">
              {mod.name}
            </h1>

            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <span>Author: <strong className="text-foreground">{mod.author_name ?? 'Unknown'}</strong></span>
              {mod.nexus_author && mod.author_name !== mod.nexus_author && (
                <span>(Original Nexus creator: {mod.nexus_author})</span>
              )}
            </div>
          </div>

          <div className="flex items-center gap-3">
            {nexusUrl && (
              <a
                href={nexusUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-block"
              >
                <Button variant="outline" size="sm" className="gap-1.5">
                  View on Nexus Mods &nearr;
                </Button>
              </a>
            )}
          </div>
        </div>

        {/* Tags */}
        {tags.length > 0 && (
          <div className="flex flex-wrap gap-1.5 pt-1">
            {tags.map((t) => (
              <Link key={t.tag_id} href={`/search?tag=${t.slug}`}>
                <Badge
                  variant="outline"
                  className="hover:bg-muted text-xs cursor-pointer text-muted-foreground"
                >
                  #{t.name}
                </Badge>
              </Link>
            ))}
          </div>
        )}

        {/* Summary */}
        {mod.summary && (
          <p className="text-base text-muted-foreground leading-relaxed pt-2 max-w-4xl">
            {mod.summary}
          </p>
        )}

        {/* Mod Stats Strip (from fn_mod_stats) */}
        {stats && (
          <div className="grid grid-cols-2 sm:grid-cols-5 gap-3 pt-4">
            <div className="p-3 rounded-xl bg-card/40 border border-border text-center">
              <div className="text-xs text-muted-foreground uppercase font-semibold">Rating</div>
              <div className="text-lg font-bold text-amber-400 mt-0.5">
                ★ {Number(stats.rating_avg).toFixed(1)}
              </div>
              <div className="text-[10px] text-muted-foreground">{stats.rating_count} reviews</div>
            </div>

            <div className="p-3 rounded-xl bg-card/40 border border-border text-center">
              <div className="text-xs text-muted-foreground uppercase font-semibold">Downloads</div>
              <div className="text-lg font-bold text-foreground mt-0.5">
                {Number(stats.download_count).toLocaleString()}
              </div>
              <div className="text-[10px] text-muted-foreground">Total users</div>
            </div>

            <div className="p-3 rounded-xl bg-card/40 border border-border text-center">
              <div className="text-xs text-muted-foreground uppercase font-semibold">Versions</div>
              <div className="text-lg font-bold text-foreground mt-0.5">
                {stats.version_count}
              </div>
              <div className="text-[10px] text-muted-foreground">Released files</div>
            </div>

            <div className="p-3 rounded-xl bg-card/40 border border-border text-center">
              <div className="text-xs text-muted-foreground uppercase font-semibold">Dependents</div>
              <div className="text-lg font-bold text-cyan-400 mt-0.5">
                {stats.dependent_count}
              </div>
              <div className="text-[10px] text-muted-foreground">Mods depend on this</div>
            </div>

            <div className="p-3 rounded-xl bg-card/40 border border-border text-center">
              <div className="text-xs text-muted-foreground uppercase font-semibold">Conflicts</div>
              <div className="text-lg font-bold text-destructive mt-0.5">
                {stats.conflict_count}
              </div>
              <div className="text-[10px] text-muted-foreground">Known incompatibilities</div>
            </div>
          </div>
        )}
      </section>

      {/* Add To Loadout Picker */}
      <section>
        <AddToLoadoutPicker
          modId={mod.mod_id}
          versions={versions}
          loadouts={userLoadouts}
          isLoggedIn={Boolean(currentUserId)}
        />
      </section>

      {/* Two Column Layout: Versions & Compatibility */}
      <div className="grid gap-8 lg:grid-cols-2">
        {/* Versions Table */}
        <section className="space-y-4">
          <div>
            <h2 className="text-xl font-bold tracking-tight">Available Versions</h2>
            <p className="text-xs text-muted-foreground">
              Compatible game versions and file releases. Curators can promote any version to primary.
            </p>
          </div>
          <VersionTable
            versions={versions}
            modId={mod.mod_id}
            canPromote={canPromote}
          />
        </section>

        {/* Compatibility Matrix List */}
        <section className="space-y-4">
          <div>
            <h2 className="text-xl font-bold tracking-tight">Compatibility Matrix</h2>
            <p className="text-xs text-muted-foreground">
              Pairwise compatibility status verified by curators and community reports.
            </p>
          </div>

          {compatRows.length === 0 ? (
            <div className="p-6 rounded-xl border border-dashed border-border text-center text-muted-foreground text-xs">
              No pairwise compatibility assessments recorded for this mod yet.
            </div>
          ) : (
            <div className="space-y-2.5">
              {compatRows.map((row) => {
                const isModA = row.mod_a_id === mod?.mod_id;
                const otherModId = isModA ? row.mod_b_id : row.mod_a_id;
                const otherModName = isModA ? row.mod_b_name : row.mod_a_name;
                const otherSemver = isModA ? row.semver_b : row.semver_a;
                const thisSemver = isModA ? row.semver_a : row.semver_b;

                let badgeVariant: 'success' | 'destructive' | 'warning' | 'secondary' = 'secondary';
                if (row.status === 'compatible') badgeVariant = 'success';
                else if (row.status === 'incompatible') badgeVariant = 'destructive';
                else if (row.status === 'partial') badgeVariant = 'warning';

                const reason = (row.conflict_detail as { reason?: string } | null)?.reason;

                return (
                  <div
                    key={row.compat_id}
                    className="p-3.5 rounded-xl border border-border bg-card/30 flex flex-col gap-2"
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center space-x-2">
                        <Link
                          href={`/mods/${otherModId}`}
                          className="font-semibold text-xs text-foreground hover:text-cyan-400 transition-colors"
                        >
                          {otherModName}
                        </Link>
                        <span className="text-[10px] text-muted-foreground font-mono">
                          (v{otherSemver} vs v{thisSemver})
                        </span>
                      </div>
                      <Badge variant={badgeVariant} className="text-[10px] capitalize">
                        {row.status}
                      </Badge>
                    </div>

                    {reason && (
                      <p className="text-xs text-muted-foreground bg-muted/30 p-2 rounded">
                        {reason}
                      </p>
                    )}

                    {row.verified_by_username && (
                      <div className="text-[10px] text-muted-foreground">
                        Verified by <span className="text-foreground">{row.verified_by_username}</span>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </section>
      </div>

      {/* Dependency Graph (React Flow) */}
      <section className="space-y-4">
        <div>
          <h2 className="text-xl font-bold tracking-tight">Dependency Architecture Graph</h2>
          <p className="text-xs text-muted-foreground">
            Interactive visualization generated by recursive query (<code className="text-cyan-400 font-mono">fn_get_mod_dependency_tree</code>).
          </p>
        </div>
        <DependencyGraph dependencies={dependencies} />
      </section>

      {/* Reviews Section */}
      <section className="border-t border-border pt-8">
        <ReviewSection
          modId={mod.mod_id}
          reviews={reviews}
          currentUserId={currentUserId}
        />
      </section>
    </main>
  );
}
