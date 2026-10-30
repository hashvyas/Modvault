'use client';

import React, { useState, useTransition } from 'react';
import { directImportLoadoutAction } from '@/app/actions/loadouts';
import { Button } from '@/components/ui/button';

interface DirectImportButtonProps {
  loadoutId: string;
  size?: 'default' | 'sm' | 'lg' | 'xs' | 'icon';
  variant?: 'default' | 'outline' | 'secondary' | 'ghost';
  className?: string;
  label?: string;
}

export function DirectImportButton({
  loadoutId,
  size = 'sm',
  variant = 'default',
  className,
  label = 'Import to My Loadouts',
}: DirectImportButtonProps) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const handleImport = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setError(null);

    startTransition(async () => {
      const res = await directImportLoadoutAction(loadoutId);
      if (res?.error) {
        setError(res.error);
      }
    });
  };

  return (
    <div className="inline-flex flex-col items-start gap-1">
      <Button
        type="button"
        size={size}
        variant={variant}
        disabled={isPending}
        onClick={handleImport}
        className={className}
      >
        {isPending ? (
          <span className="flex items-center gap-1.5">
            <span className="inline-block animate-spin size-3 border-2 border-current border-t-transparent rounded-full" />
            Importing...
          </span>
        ) : (
          <span className="flex items-center gap-1.5">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="13"
              height="13"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="shrink-0"
            >
              <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
              <polyline points="7 10 12 15 17 10" />
              <line x1="12" x2="12" y1="15" y2="3" />
            </svg>
            {label}
          </span>
        )}
      </Button>
      {error && (
        <span className="text-[10px] text-destructive bg-destructive/10 px-2 py-0.5 rounded border border-destructive/20 max-w-xs">
          {error}
        </span>
      )}
    </div>
  );
}
