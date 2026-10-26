import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  CompatibilityHeatmap,
  type PrimaryVersionItem,
  type HeatmapCellData,
} from '@/components/compat-heatmap';

export const dynamic = 'force-dynamic';

interface GameInfo {
  game_id: string;
  name: string;
  domain: string;
  current_version: string | null;
}

type Props = {
  params: Promise<{ domain: string }>;
};

export default async function GameCompatibilityPage({ params }: Props) {
  const session = await getSession();
  const { domain } = await params;

  let game: GameInfo | null = null;
  let versions: PrimaryVersionItem[] = [];
  let cells: HeatmapCellData[] = [];

  try {
    const data = await withUser(session, async (client) => {
      // 1. Fetch game details
      const gRes = await client.query<GameInfo>(
        'SELECT game_id, name, domain, current_version FROM games WHERE domain = $1',
        [domain]
      );
      if (gRes.rows.length === 0) return null;
      const g = gRes.rows[0];

      // 2. Fetch primary versions for this game
      const vRes = await client.query<PrimaryVersionItem>(
        `SELECT v.version_id, v.semver, m.mod_id, m.name AS mod_name
         FROM mod_versions v
         JOIN mods m ON v.mod_id = m.mod_id
         WHERE m.game_id = $1 AND v.is_primary = TRUE
         ORDER BY m.name ASC`,
        [g.game_id]
      );

      const verList = vRes.rows;
      const versionIds = verList.map((v) => v.version_id);

      // 3. Fetch compatibility matrix rows
      let matrixCells: HeatmapCellData[] = [];
      if (versionIds.length > 0) {
        const cRes = await client.query<HeatmapCellData>(
          `SELECT cm.compat_id, cm.version_a_id, cm.version_b_id, cm.status,
                  cm.conflict_detail, u.username AS verified_by_username
           FROM compatibility_matrix cm
           LEFT JOIN users u ON cm.verified_by = u.user_id
           WHERE cm.version_a_id = ANY($1::uuid[]) AND cm.version_b_id = ANY($1::uuid[])`,
          [versionIds]
        );
        matrixCells = cRes.rows;
      }

      return { game: g, versions: verList, cells: matrixCells };
    });

    if (!data) notFound();

    game = data.game;
    versions = data.versions;
    cells = data.cells;
  } catch (err) {
    console.error('Error fetching compatibility heatmap:', err);
    notFound();
  }

  const canEdit = session?.role === 'curator' || session?.role === 'admin';

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4 border-b border-border pb-6">
        <div className="space-y-1">
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-extrabold tracking-tight">Compatibility Heatmap</h1>
            <Badge variant="outline" className="font-mono text-xs">
              {game.name}
            </Badge>
          </div>
          <p className="text-muted-foreground text-sm">
            Pairwise matrix of primary versions. Curators can directly assess and flag incompatible pairs.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <Link href={`/games/${game.domain}`}>
            <Button variant="outline" size="sm">
              &larr; Browse {game.name} Mods
            </Button>
          </Link>
          {canEdit && (
            <Link href="/curate">
              <Button size="sm">
                Curator Hub
              </Button>
            </Link>
          )}
        </div>
      </div>

      {/* Heatmap Grid */}
      <CompatibilityHeatmap
        domain={game.domain}
        gameName={game.name}
        versions={versions}
        cells={cells}
        canEdit={canEdit}
      />
    </main>
  );
}
