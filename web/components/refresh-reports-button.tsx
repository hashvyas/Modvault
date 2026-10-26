'use client';

import React, { useState, useTransition } from 'react';
import { refreshReportsAction } from '@/app/actions/admin';
import { Button } from '@/components/ui/button';

export function RefreshReportsButton() {
  const [isPending, startTransition] = useTransition();
  const [result, setResult] = useState<{ success?: boolean; error?: string | null; message?: string | null } | null>(null);

  const handleRefresh = () => {
    setResult(null);
    startTransition(async () => {
      const res = await refreshReportsAction();
      setResult(res);
    });
  };

  return (
    <div className="flex flex-col sm:flex-row items-start sm:items-center gap-3">
      <Button
        type="button"
        size="sm"
        disabled={isPending}
        onClick={handleRefresh}
        className="bg-cyan-600 hover:bg-cyan-500 text-white font-medium text-xs whitespace-nowrap"
      >
        {isPending ? 'Refreshing mv_game_leaderboard...' : 'Refresh Reports (pr_refresh_reports)'}
      </Button>

      {result?.message && (
        <span className="text-xs text-emerald-400 font-medium">
          ✓ {result.message}
        </span>
      )}

      {result?.error && (
        <span className="text-xs text-destructive font-medium">
          ✕ {result.error}
        </span>
      )}
    </div>
  );
}
