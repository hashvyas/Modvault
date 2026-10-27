'use client';

import React, { useState, useTransition } from 'react';
import {
  autoSortLoadoutAction,
  addMissingDependencyAction,
} from '@/app/actions/loadouts';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { ScoreMeter } from '@/components/score-meter';

export interface HealthIssueItem {
  issue_type: string;
  severity: 'error' | 'warning' | 'info';
  version_id: string | null;
  other_version_id: string | null;
  related_mod_id: string | null;
  related_mod_name?: string | null;
  message: string;
}

export interface HealthSummary {
  score: number;
  status: 'healthy' | 'warnings' | 'broken';
  error_count: number;
  warning_count: number;
  info_count: number;
}

interface Props {
  loadoutId: string;
  health: HealthSummary;
  issues: HealthIssueItem[];
  isOwner: boolean;
  manifestJson: string;
  loadoutName: string;
}

export function LoadoutHealthPanel({
  loadoutId,
  health,
  issues,
  isOwner,
  manifestJson,
  loadoutName,
}: Props) {
  const [isPending, startTransition] = useTransition();
  const [infoOpen, setInfoOpen] = useState(false);
  const [statusMessage, setStatusMessage] = useState<string | null>(null);

  const errors = issues.filter((i) => i.severity === 'error');
  const warnings = issues.filter((i) => i.severity === 'warning');
  const infos = issues.filter((i) => i.severity === 'info');

  const handleAutoSort = () => {
    setStatusMessage('Sorting load order...');
    startTransition(async () => {
      const res = await autoSortLoadoutAction(loadoutId);
      if (res.error) setStatusMessage(`Error: ${res.error}`);
      else setStatusMessage('Load order applied!');
    });
  };

  const handleAddDependency = (relatedModId: string, modName?: string) => {
    setStatusMessage(`Adding ${modName ?? 'dependency'}...`);
    startTransition(async () => {
      const res = await addMissingDependencyAction(loadoutId, relatedModId);
      if (res.error) setStatusMessage(`Error: ${res.error}`);
      else setStatusMessage(`Added ${modName ?? 'dependency'} to loadout!`);
    });
  };

  const handleExport = () => {
    const blob = new Blob([manifestJson], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${loadoutName.toLowerCase().replace(/[^a-z0-9]+/g, '-')}-manifest.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  let statusBadgeVariant: 'success' | 'warning' | 'destructive' = 'success';
  if (health.status === 'broken' || health.score < 50) {
    statusBadgeVariant = 'destructive';
  } else if (health.status === 'warnings' || health.score < 80) {
    statusBadgeVariant = 'warning';
  }

  return (
    <div className="space-y-6">
      {/* Health Score Card */}
      <div className="p-5 rounded-2xl border border-border bg-card/50 space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-base font-bold tracking-tight">Loadout Health Diagnostic</h3>
            <p className="text-xs text-muted-foreground">Pre-flight rule engine verification</p>
          </div>
          <Badge variant={statusBadgeVariant} className="text-xs uppercase font-bold tracking-wider">
            {health.status}
          </Badge>
        </div>

        {/* Score Ring Display */}
        <div className="flex items-center gap-4 pt-1">
          <ScoreMeter score={health.score} status={health.status} size={72} />
          <div className="space-y-1 text-xs">
            <div className="text-foreground font-semibold">
              {health.status === 'healthy'
                ? 'Healthy & Ready to Launch'
                : health.status === 'warnings'
                ? 'Warnings Detected - Review Order & Versions'
                : 'Broken Loadout - Critical Conflicts Present'}
            </div>
            <div className="text-muted-foreground">
              {errors.length} {errors.length === 1 ? 'error' : 'errors'}, {warnings.length}{' '}
              {warnings.length === 1 ? 'warning' : 'warnings'}, {infos.length} info items
            </div>
          </div>
        </div>

        {statusMessage && (
          <div className="p-2 rounded bg-cyan-950/40 border border-cyan-500/30 text-cyan-300 text-xs">
            {statusMessage}
          </div>
        )}

        {/* Global Action Buttons */}
        <div className="flex flex-wrap gap-2 pt-2 border-t border-border/50">
          {isOwner && (
            <Button
              type="button"
              size="sm"
              disabled={isPending}
              onClick={handleAutoSort}
              className="bg-cyan-600 hover:bg-cyan-500 text-white font-medium text-xs"
            >
              Auto-sort Load Order
            </Button>
          )}

          <Button
            type="button"
            size="sm"
            variant="outline"
            onClick={handleExport}
            className="text-xs"
          >
            Export Manifest JSON &darr;
          </Button>
        </div>
      </div>

      {/* Issues Diagnostic List */}
      <div className="space-y-4">
        {/* 1. Errors */}
        {errors.length > 0 && (
          <div className="space-y-2">
            <h4 className="text-xs font-bold uppercase tracking-wider text-destructive flex items-center gap-1.5">
              <span>●</span> Errors ({errors.length})
            </h4>
            <div className="space-y-2">
              {errors.map((err, idx) => (
                <div
                  key={idx}
                  className="p-3 rounded-xl border border-destructive/30 bg-destructive/10 space-y-2"
                >
                  <div className="flex items-center justify-between gap-2">
                    <Badge variant="destructive" className="text-[10px]">
                      {err.issue_type}
                    </Badge>
                    {isOwner && err.issue_type === 'MISSING_DEPENDENCY' && err.related_mod_id && (
                      <Button
                        type="button"
                        size="xs"
                        disabled={isPending}
                        onClick={() => handleAddDependency(err.related_mod_id!, err.related_mod_name ?? undefined)}
                        className="bg-destructive hover:bg-destructive/80 text-white font-medium text-[10px]"
                      >
                        Add {err.related_mod_name ?? 'Mod'}
                      </Button>
                    )}
                  </div>
                  <p className="text-xs text-foreground/90 leading-snug">{err.message}</p>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* 2. Warnings */}
        {warnings.length > 0 && (
          <div className="space-y-2">
            <h4 className="text-xs font-bold uppercase tracking-wider text-amber-400 flex items-center gap-1.5">
              <span>▲</span> Warnings ({warnings.length})
            </h4>
            <div className="space-y-2">
              {warnings.map((warn, idx) => (
                <div
                  key={idx}
                  className="p-3 rounded-xl border border-amber-500/30 bg-amber-500/10 space-y-2"
                >
                  <div className="flex items-center justify-between gap-2">
                    <Badge variant="warning" className="text-[10px]">
                      {warn.issue_type}
                    </Badge>
                    {isOwner && warn.issue_type === 'LOAD_ORDER' && (
                      <Button
                        type="button"
                        size="xs"
                        disabled={isPending}
                        onClick={handleAutoSort}
                        className="bg-amber-600 hover:bg-amber-500 text-white font-medium text-[10px]"
                      >
                        Auto-sort
                      </Button>
                    )}
                  </div>
                  <p className="text-xs text-foreground/90 leading-snug">{warn.message}</p>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* 3. Info (Collapsed by default per spec) */}
        {infos.length > 0 && (
          <div className="border border-border/60 rounded-xl overflow-hidden bg-card/25">
            <button
              type="button"
              onClick={() => setInfoOpen(!infoOpen)}
              className="w-full px-4 py-3 text-left text-xs font-semibold text-muted-foreground flex items-center justify-between hover:bg-card/40 transition-colors"
            >
              <span>Info & Recommendations ({infos.length})</span>
              <span className="text-xs font-mono">{infoOpen ? '▲' : '▼'}</span>
            </button>

            {infoOpen && (
              <div className="p-3 pt-0 space-y-2 border-t border-border/40">
                {infos.map((info, idx) => (
                  <div
                    key={idx}
                    className="p-2.5 rounded-lg border border-border/40 bg-card/30 space-y-1"
                  >
                    <Badge variant="outline" className="text-[9px] text-muted-foreground">
                      {info.issue_type}
                    </Badge>
                    <p className="text-xs text-muted-foreground leading-snug">{info.message}</p>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {issues.length === 0 && (
          <div className="p-6 rounded-xl border border-emerald-500/20 bg-emerald-500/5 text-center space-y-1">
            <div className="text-emerald-400 font-bold text-sm">Perfect Compatibility</div>
            <p className="text-xs text-muted-foreground">
              No missing dependencies, load order conflicts, or incompatible versions detected.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
