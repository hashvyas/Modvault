'use client';

import React, { useActionState } from 'react';
import Link from 'next/link';
import {
  promoteVersionAction,
  addToLoadoutAction,
  type ActionState,
} from '@/app/actions/mods';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';

interface VersionItem {
  version_id: string;
  semver: string;
  is_primary: boolean;
  supported_game_versions: string[];
  changelog: string | null;
  uploaded_at: string;
}

interface LoadoutOption {
  loadout_id: string;
  name: string;
  game_version: string | null;
  current_version_id: string | null;
}

// ---------------------------------------------------------------------------
// 1. Versions Table Component
// ---------------------------------------------------------------------------
export function VersionTable({
  versions,
  modId,
  canPromote,
}: {
  versions: VersionItem[];
  modId: string;
  canPromote: boolean;
}) {
  const [state, formAction, isPending] = useActionState<ActionState, FormData>(
    promoteVersionAction,
    {}
  );

  return (
    <div className="space-y-3">
      {state.error && (
        <div className="p-2.5 rounded-md bg-destructive/15 text-destructive text-xs border border-destructive/30">
          {state.error}
        </div>
      )}

      <div className="rounded-xl border border-border overflow-hidden bg-card/30">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="bg-card/70 border-b border-border text-muted-foreground uppercase tracking-wider text-[11px]">
              <tr>
                <th className="px-4 py-3">Version</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Supported Game Versions</th>
                <th className="px-4 py-3">Uploaded</th>
                {canPromote && <th className="px-4 py-3 text-right">Action</th>}
              </tr>
            </thead>
            <tbody className="divide-y divide-border/40 font-mono">
              {versions.map((ver) => (
                <tr key={ver.version_id} className="hover:bg-card/50 transition-colors">
                  <td className="px-4 py-3 font-semibold text-foreground">
                    {ver.semver}
                  </td>
                  <td className="px-4 py-3">
                    {ver.is_primary ? (
                      <Badge variant="default" className="bg-emerald-600/20 text-emerald-400 border border-emerald-500/30">
                        Primary
                      </Badge>
                    ) : (
                      <Badge variant="outline" className="text-muted-foreground">
                        Legacy
                      </Badge>
                    )}
                  </td>
                  <td className="px-4 py-3 text-muted-foreground">
                    {ver.supported_game_versions && ver.supported_game_versions.length > 0
                      ? ver.supported_game_versions.join(', ')
                      : 'Any'}
                  </td>
                  <td className="px-4 py-3 text-muted-foreground">
                    {new Date(ver.uploaded_at).toLocaleDateString()}
                  </td>
                  {canPromote && (
                    <td className="px-4 py-3 text-right">
                      {!ver.is_primary && (
                        <form action={formAction} className="inline">
                          <input type="hidden" name="version_id" value={ver.version_id} />
                          <input type="hidden" name="mod_id" value={modId} />
                          <Button
                            type="submit"
                            size="xs"
                            variant="outline"
                            disabled={isPending}
                            className="font-sans text-[11px] hover:bg-cyan-600/20 hover:text-cyan-400"
                          >
                            {isPending ? 'Promoting...' : 'Make Primary'}
                          </Button>
                        </form>
                      )}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// 2. Add To Loadout Component
// ---------------------------------------------------------------------------
export function AddToLoadoutPicker({
  modId,
  versions,
  loadouts,
  isLoggedIn,
}: {
  modId: string;
  versions: VersionItem[];
  loadouts: LoadoutOption[];
  isLoggedIn: boolean;
}) {
  const [state, formAction, isPending] = useActionState<ActionState, FormData>(
    addToLoadoutAction,
    {}
  );
  const primaryVer = versions.find((v) => v.is_primary) ?? versions[0];
  const [selectedId, setSelectedId] = React.useState(loadouts[0]?.loadout_id);
  const [selectedVersionId, setSelectedVersionId] = React.useState(primaryVer?.version_id);
  const currentVersionId = loadouts.find((l) => l.loadout_id === selectedId)?.current_version_id ?? null;
  const alreadyAdded = currentVersionId === selectedVersionId;
  const selectedSemver = versions.find((v) => v.version_id === selectedVersionId)?.semver;
  const idleLabel = alreadyAdded
    ? 'Already added'
    : currentVersionId
    ? `Switch to v${selectedSemver}`
    : 'Add to Loadout';

  if (!isLoggedIn) {
    return (
      <div className="p-4 rounded-xl border border-border bg-card/30 flex items-center justify-between">
        <span className="text-sm text-muted-foreground">Want to add this to your loadout?</span>
        <Link href="/login">
          <Button size="sm" variant="outline">Sign In</Button>
        </Link>
      </div>
    );
  }

  if (loadouts.length === 0) {
    return (
      <div className="p-4 rounded-xl border border-dashed border-border bg-card/20 flex items-center justify-between">
        <span className="text-sm text-muted-foreground">You have no loadouts for this game yet.</span>
        <Link href="/loadouts">
          <Button size="sm">Create Loadout</Button>
        </Link>
      </div>
    );
  }

  return (
    <div className="p-4 rounded-xl border border-border bg-card/40 space-y-3">
      <div className="flex items-center justify-between">
        <h4 className="text-sm font-semibold">Add to Loadout</h4>
        {state.success && (
          <span className="text-xs text-emerald-400 font-medium">Loadout updated!</span>
        )}
      </div>

      {state.error && (
        <div className="p-2 rounded bg-destructive/15 text-destructive text-xs">
          {state.error}
        </div>
      )}

      <form action={formAction} className="flex flex-col sm:flex-row gap-2">
        <input type="hidden" name="mod_id" value={modId} />

        <select
          name="loadout_id"
          required
          value={selectedId}
          onChange={(e) => setSelectedId(e.target.value)}
          className="h-8 flex-1 rounded-md border border-border bg-card px-2.5 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
        >
          {loadouts.map((l) => (
            <option key={l.loadout_id} value={l.loadout_id}>
              {l.name} {l.game_version ? `(${l.game_version})` : ''}
            </option>
          ))}
        </select>

        <select
          name="version_id"
          value={selectedVersionId}
          onChange={(e) => setSelectedVersionId(e.target.value)}
          className="h-8 w-36 rounded-md border border-border bg-card px-2.5 text-xs font-mono text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
        >
          {versions.map((v) => (
            <option key={v.version_id} value={v.version_id}>
              v{v.semver} {v.is_primary ? '(Primary)' : ''}
            </option>
          ))}
        </select>

        <Button type="submit" disabled={isPending || alreadyAdded}>
          {isPending ? 'Saving...' : idleLabel}
        </Button>
      </form>
    </div>
  );
}
