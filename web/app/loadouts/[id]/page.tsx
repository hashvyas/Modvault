import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  LoadoutModList,
  type LoadoutModItem,
  type ModVersionOption,
} from '@/components/loadout-dnd-list';
import {
  LoadoutHealthPanel,
  type HealthSummary,
  type HealthIssueItem,
} from '@/components/loadout-health-panel';

export const dynamic = 'force-dynamic';

interface LoadoutDetail {
  loadout_id: string;
  name: string;
  description: string | null;
  game_version: string | null;
  is_public: boolean;
  user_id: string;
  owner_username: string;
  game_id: string;
  game_name: string;
  game_domain: string;
}

interface RawModRow {
  id: string;
  version_id: string;
  position: number;
  enabled: boolean;
  mod_id: string;
  mod_name: string;
  current_semver: string;
}

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ imported?: string; skipped?: string }>;
};

export default async function LoadoutBuilderPage({ params, searchParams }: Props) {
  const session = await getSession();
  const { id } = await params;
  const sParams = await searchParams;
  const isImported = sParams.imported === 'true';
  const skippedCount = parseInt(sParams.skipped || '0', 10);

  let loadout: LoadoutDetail | null = null;
  let mods: LoadoutModItem[] = [];
  let health: HealthSummary = {
    score: 100,
    status: 'healthy',
    error_count: 0,
    warning_count: 0,
    info_count: 0,
  };
  let issues: HealthIssueItem[] = [];
  let manifestJson = '{}';

  try {
    const data = await withUser(session, async (client) => {
      // 1. Fetch loadout details
      const lRes = await client.query<LoadoutDetail>(
        `SELECT l.loadout_id, l.name, l.description, l.game_version, l.is_public, l.user_id,
                u.username AS owner_username, g.game_id, g.name AS game_name, g.domain AS game_domain
         FROM loadouts l
         JOIN users u ON l.user_id = u.user_id
         JOIN games g ON l.game_id = g.game_id
         WHERE l.loadout_id = $1`,
        [id]
      );

      if (lRes.rows.length === 0) return null;
      const lData = lRes.rows[0];

      // 2. Fetch loadout mods in position order
      const modsRes = await client.query<RawModRow>(
        `SELECT lm.id, lm.version_id, lm.position, lm.enabled,
                m.mod_id, m.name AS mod_name, v.semver AS current_semver
         FROM loadout_mods lm
         JOIN mod_versions v ON lm.version_id = v.version_id
         JOIN mods m ON v.mod_id = m.mod_id
         WHERE lm.loadout_id = $1
         ORDER BY lm.position ASC, lm.id ASC`,
        [id]
      );

      // 3. Fetch all available versions for these mods
      const modIds = Array.from(new Set(modsRes.rows.map((r) => r.mod_id)));
      const versionMap: Record<string, ModVersionOption[]> = {};
      if (modIds.length > 0) {
        const vRes = await client.query<{
          version_id: string;
          mod_id: string;
          semver: string;
          is_primary: boolean;
        }>(
          `SELECT version_id, mod_id, semver, is_primary
           FROM mod_versions
           WHERE mod_id = ANY($1::uuid[])
           ORDER BY is_primary DESC, uploaded_at DESC`,
          [modIds]
        );
        vRes.rows.forEach((ver) => {
          if (!versionMap[ver.mod_id]) versionMap[ver.mod_id] = [];
          versionMap[ver.mod_id].push({
            version_id: ver.version_id,
            semver: ver.semver,
            is_primary: ver.is_primary,
          });
        });
      }

      const formattedMods: LoadoutModItem[] = modsRes.rows.map((r) => ({
        id: r.id,
        version_id: r.version_id,
        mod_id: r.mod_id,
        mod_name: r.mod_name,
        current_semver: r.current_semver,
        position: r.position,
        enabled: r.enabled,
        available_versions: versionMap[r.mod_id] || [],
      }));

      // 4. Fetch Health status from loadout_health_view
      const hRes = await client.query<HealthSummary>(
        `SELECT score, status, error_count, warning_count, info_count
         FROM loadout_health_view
         WHERE loadout_id = $1`,
        [id]
      );

      // 5. Fetch Diagnostic Issues via fn_check_loadout_compatibility
      const issuesRes = await client.query<HealthIssueItem>(
        `SELECT c.issue_type, c.severity, c.version_id, c.other_version_id, c.related_mod_id,
                c.message, m.name AS related_mod_name
         FROM fn_check_loadout_compatibility($1) c
         LEFT JOIN mods m ON c.related_mod_id = m.mod_id
         ORDER BY
           CASE c.severity WHEN 'error' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,
           c.issue_type, c.message`,
        [id]
      );

      // 6. Fetch Export Manifest JSON via fn_export_loadout
      const exportRes = await client.query<{ manifest: unknown }>(
        'SELECT fn_export_loadout($1) AS manifest',
        [id]
      );

      return {
        loadout: lData,
        mods: formattedMods,
        health: hRes.rows[0] ?? {
          score: 100,
          status: 'healthy',
          error_count: 0,
          warning_count: 0,
          info_count: 0,
        },
        issues: issuesRes.rows,
        manifest: JSON.stringify(exportRes.rows[0]?.manifest ?? {}, null, 2),
      };
    });

    if (!data) notFound();

    loadout = data.loadout;
    mods = data.mods;
    health = data.health;
    issues = data.issues;
    manifestJson = data.manifest;
  } catch (err) {
    console.error('Error fetching loadout builder details:', err);
    notFound();
  }

  const currentUserId = session?.sub || null;
  const isOwner = currentUserId === loadout.user_id || session?.role === 'admin';

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
      {/* Import Notification Banner */}
      {isImported && (
        <div className="p-4 rounded-xl bg-cyan-500/10 border border-cyan-500/30 text-cyan-300 text-sm flex items-center justify-between">
          <span>
            Loadout successfully imported!
            {skippedCount > 0 && ` (${skippedCount} unresolved mod entries skipped)`}
          </span>
          <Link href={`/loadouts/${id}`}>
            <Button size="xs" variant="ghost">Dismiss</Button>
          </Link>
        </div>
      )}

      {/* Header Banner */}
      <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-4 border-b border-border pb-6">
        <div className="space-y-1">
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-extrabold tracking-tight">{loadout.name}</h1>
            <Badge variant="outline" className="text-xs">
              {loadout.game_name}
            </Badge>
            {loadout.is_public && (
              <Badge variant="secondary" className="text-[10px]">
                Public
              </Badge>
            )}
          </div>
          <p className="text-muted-foreground text-xs">
            Owner: <strong className="text-foreground">{loadout.owner_username}</strong>
            {loadout.game_version && ` • Target Game Version: v${loadout.game_version}`}
          </p>
          {loadout.description && (
            <p className="text-sm text-muted-foreground pt-1 max-w-2xl">{loadout.description}</p>
          )}
        </div>

        <div className="flex items-center gap-2">
          <Link href={`/games/${loadout.game_domain}`}>
            <Button variant="outline" size="sm" className="text-xs">
              + Find Mods for {loadout.game_name}
            </Button>
          </Link>
          <Link href="/loadouts">
            <Button variant="ghost" size="sm" className="text-xs">
              &larr; Back to Loadouts
            </Button>
          </Link>
        </div>
      </div>

      {/* Two Panes Layout */}
      <div className="grid gap-8 lg:grid-cols-12">
        {/* Left Pane (7 cols): Sortable DND Mod List */}
        <div className="lg:col-span-7">
          <LoadoutModList
            loadoutId={loadout.loadout_id}
            initialMods={mods}
            isOwner={isOwner}
          />
        </div>

        {/* Right Pane (5 cols): Diagnostic Health Panel */}
        <div className="lg:col-span-5">
          <LoadoutHealthPanel
            loadoutId={loadout.loadout_id}
            health={health}
            issues={issues}
            isOwner={isOwner}
            manifestJson={manifestJson}
            loadoutName={loadout.name}
          />
        </div>
      </div>
    </main>
  );
}
