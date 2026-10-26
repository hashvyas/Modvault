'use client';

import React, { useState, useActionState } from 'react';
import {
  upsertCompatibilityAction,
  type ActionState,
} from '@/app/actions/curate';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';

export interface PrimaryVersionItem {
  version_id: string;
  semver: string;
  mod_id: string;
  mod_name: string;
}

export interface HeatmapCellData {
  compat_id: string;
  version_a_id: string;
  version_b_id: string;
  status: 'compatible' | 'incompatible' | 'partial' | 'unknown';
  conflict_detail: { reason?: string; files?: string[] } | null;
  verified_by_username: string | null;
}

interface Props {
  domain: string;
  gameName: string;
  versions: PrimaryVersionItem[];
  cells: HeatmapCellData[];
  canEdit: boolean;
}

export function CompatibilityHeatmap({
  domain,
  gameName,
  versions,
  cells,
  canEdit,
}: Props) {
  const [selectedPair, setSelectedPair] = useState<{
    verA: PrimaryVersionItem;
    verB: PrimaryVersionItem;
  } | null>(null);

  const [state, formAction, isPending] = useActionState<ActionState, FormData>(
    upsertCompatibilityAction,
    {}
  );

  // Index cell lookup by canonical key
  const cellMap = new Map<string, HeatmapCellData>();
  cells.forEach((c) => {
    const key =
      c.version_a_id < c.version_b_id
        ? `${c.version_a_id}_${c.version_b_id}`
        : `${c.version_b_id}_${c.version_a_id}`;
    cellMap.set(key, c);
  });

  const getCell = (v1: string, v2: string) => {
    if (v1 === v2) return null;
    const key = v1 < v2 ? `${v1}_${v2}` : `${v2}_${v1}`;
    return cellMap.get(key) || null;
  };

  const handleCellClick = (vA: PrimaryVersionItem, vB: PrimaryVersionItem) => {
    if (vA.version_id === vB.version_id) return;
    if (!canEdit) return;
    setSelectedPair({ verA: vA, verB: vB });
  };

  // Read the cell from live props, not a click-time snapshot: React resets the form
  // after each save, and a stale snapshot would reset reason/files to empty.
  const existing = selectedPair
    ? getCell(selectedPair.verA.version_id, selectedPair.verB.version_id)
    : null;

  return (
    <div className="space-y-6">
      {/* Legend & Instructions */}
      <div className="flex flex-wrap items-center justify-between gap-4 p-4 rounded-xl border border-border bg-card/40">
        <div className="flex flex-wrap items-center gap-3 text-xs">
          <span className="font-semibold text-foreground">{gameName} Matrix:</span>
          <span className="flex items-center gap-1.5">
            <span className="w-3.5 h-3.5 rounded bg-emerald-500/80 inline-block" /> Compatible
          </span>
          <span className="flex items-center gap-1.5">
            <span className="w-3.5 h-3.5 rounded bg-rose-500/80 inline-block" /> Incompatible
          </span>
          <span className="flex items-center gap-1.5">
            <span className="w-3.5 h-3.5 rounded bg-amber-500/80 inline-block" /> Partial
          </span>
          <span className="flex items-center gap-1.5">
            <span className="w-3.5 h-3.5 rounded bg-blue-500/80 inline-block" /> Unknown
          </span>
          <span className="flex items-center gap-1.5">
            <span className="w-3.5 h-3.5 rounded bg-muted inline-block" /> Unchecked
          </span>
        </div>

        <div className="text-xs text-muted-foreground">
          {canEdit ? (
            <span className="text-cyan-400 font-medium">Click any matrix cell to record or edit compatibility</span>
          ) : (
            <span>Hover over any cell to inspect compatibility notes</span>
          )}
        </div>
      </div>

      {/* Matrix Grid */}
      <div className="rounded-xl border border-border overflow-x-auto bg-card/20 p-4">
        <table className="border-collapse text-xs select-none mx-auto">
          <thead>
            <tr>
              <th className="p-2 text-left font-mono text-[10px] text-muted-foreground max-w-[120px] truncate">
                Mod Matrix
              </th>
              {versions.map((col, idx) => (
                <th
                  key={col.version_id}
                  title={`${col.mod_name} (v${col.semver})`}
                  className="p-1.5 text-center font-mono text-[10px] text-muted-foreground w-9"
                >
                  <span className="inline-block transform -rotate-45 origin-bottom-left max-w-[80px] truncate text-[9px]">
                    #{idx + 1}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {versions.map((rowMod, rowIdx) => (
              <tr key={rowMod.version_id} className="hover:bg-muted/10">
                <td
                  title={`${rowMod.mod_name} (v${rowMod.semver})`}
                  className="p-1.5 font-medium text-xs text-foreground max-w-[180px] truncate pr-3"
                >
                  <span className="text-muted-foreground text-[10px] font-mono mr-1.5">
                    #{rowIdx + 1}
                  </span>
                  {rowMod.mod_name}
                </td>

                {versions.map((colMod) => {
                  const isSelf = rowMod.version_id === colMod.version_id;
                  const cell = getCell(rowMod.version_id, colMod.version_id);

                  let bgClass = 'bg-muted/40 hover:bg-muted/60';
                  let symbol = '';

                  if (isSelf) {
                    bgClass = 'bg-muted/20 opacity-30 cursor-not-allowed';
                    symbol = '—';
                  } else if (cell) {
                    if (cell.status === 'compatible') {
                      bgClass = 'bg-emerald-600/80 hover:bg-emerald-500 text-white';
                      symbol = '✓';
                    } else if (cell.status === 'incompatible') {
                      bgClass = 'bg-rose-600/80 hover:bg-rose-500 text-white font-bold';
                      symbol = '✕';
                    } else if (cell.status === 'partial') {
                      bgClass = 'bg-amber-500/80 hover:bg-amber-400 text-black font-bold';
                      symbol = '⚠';
                    } else if (cell.status === 'unknown') {
                      bgClass = 'bg-blue-600/80 hover:bg-blue-500 text-white';
                      symbol = '?';
                    }
                  }

                  const tooltip = isSelf
                    ? 'Same mod'
                    : cell
                    ? `${rowMod.mod_name} vs ${colMod.mod_name}: ${cell.status.toUpperCase()} ${
                        cell.conflict_detail?.reason ? `(${cell.conflict_detail.reason})` : ''
                      }`
                    : `${rowMod.mod_name} vs ${colMod.mod_name}: Not checked`;

                  return (
                    <td key={colMod.version_id} className="p-1 text-center">
                      <button
                        type="button"
                        disabled={isSelf || !canEdit}
                        onClick={() => handleCellClick(rowMod, colMod)}
                        title={tooltip}
                        className={`w-8 h-8 rounded text-[11px] font-mono transition-transform flex items-center justify-center ${bgClass} ${
                          !isSelf && canEdit ? 'cursor-pointer hover:scale-110 active:scale-95' : ''
                        }`}
                      >
                        {symbol}
                      </button>
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Curator Modal Dialog for editing compatibility */}
      {selectedPair && (
        <div className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-card border border-border rounded-2xl p-6 max-w-lg w-full space-y-5 shadow-2xl">
            <div className="flex items-center justify-between border-b border-border pb-3">
              <div>
                <h3 className="text-base font-bold">Record Pairwise Compatibility</h3>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Stored via PostgreSQL stored procedure <code className="text-cyan-400 font-mono">pr_upsert_compatibility</code>.
                </p>
              </div>
              <Button
                variant="ghost"
                size="xs"
                onClick={() => setSelectedPair(null)}
              >
                &times;
              </Button>
            </div>

            {state.error && (
              <div className="p-2.5 rounded bg-destructive/15 text-destructive text-xs border border-destructive/30">
                {state.error}
              </div>
            )}

            {state.success && (
              <div className="p-2.5 rounded bg-emerald-500/15 text-emerald-400 text-xs border border-emerald-500/30">
                Compatibility assessment saved successfully!
              </div>
            )}

            <form key={JSON.stringify(existing)} action={formAction} className="space-y-4">
              <input type="hidden" name="domain" value={domain} />
              <input type="hidden" name="version_a" value={selectedPair.verA.version_id} />
              <input type="hidden" name="version_b" value={selectedPair.verB.version_id} />

              <div className="p-3 rounded-xl bg-card/60 border border-border/60 text-xs space-y-1">
                <div className="font-semibold text-foreground">
                  {selectedPair.verA.mod_name} <span className="font-mono text-muted-foreground">(v{selectedPair.verA.semver})</span>
                </div>
                <div className="text-muted-foreground">&times;</div>
                <div className="font-semibold text-foreground">
                  {selectedPair.verB.mod_name} <span className="font-mono text-muted-foreground">(v{selectedPair.verB.semver})</span>
                </div>
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="status">Compatibility Status *</Label>
                <select
                  id="status"
                  name="status"
                  required
                  defaultValue={existing?.status || 'incompatible'}
                  className="w-full h-9 rounded-md border border-border bg-card px-2.5 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
                >
                  <option value="compatible">Compatible (Verified clean)</option>
                  <option value="incompatible">Incompatible (Causes game crash or breakdown)</option>
                  <option value="partial">Partial (Feature conflict or workaround needed)</option>
                  <option value="unknown">Unknown (Community report pending verification)</option>
                </select>
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="reason">Reason / Diagnostic Details</Label>
                <input
                  id="reason"
                  name="reason"
                  defaultValue={existing?.conflict_detail?.reason || ''}
                  placeholder="e.g. Overlapping HUD SWF menus cause interface crash"
                  className="w-full h-9 rounded-md border border-border bg-card px-2.5 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
                />
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="files">Conflicting Files (one per line, optional)</Label>
                <textarea
                  id="files"
                  name="files"
                  rows={2}
                  defaultValue={existing?.conflict_detail?.files?.join('\n') || ''}
                  placeholder="interface/hudmenu.swf"
                  className="w-full rounded-md border border-border bg-card p-2 text-xs font-mono text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-2 border-t border-border">
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => setSelectedPair(null)}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  size="sm"
                  disabled={isPending}
                  className="bg-cyan-600 hover:bg-cyan-500 text-white font-medium text-xs"
                >
                  {isPending ? 'Saving...' : 'Save Assessment'}
                </Button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
