'use client';

import React, { useActionState, useState } from 'react';
import { importLoadoutAction, type ActionState } from '@/app/actions/loadouts';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';

export function LoadoutImportForm() {
  const [state, formAction, isPending] = useActionState<ActionState, FormData>(
    importLoadoutAction,
    {}
  );
  const [manifestText, setManifestText] = useState('');

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (event) => {
      const content = event.target?.result as string;
      setManifestText(content || '');
    };
    reader.readAsText(file);
  };

  return (
    <form action={formAction} className="space-y-4">
      {state.error && (
        <div className="p-3 rounded-lg bg-destructive/15 text-destructive border border-destructive/30 text-xs">
          {state.error}
        </div>
      )}

      <div className="space-y-2">
        <Label htmlFor="file_upload">Upload Manifest JSON File</Label>
        <input
          id="file_upload"
          type="file"
          accept=".json,application/json"
          onChange={handleFileUpload}
          className="block w-full text-xs text-muted-foreground file:mr-3 file:py-1.5 file:px-3 file:rounded-md file:border-0 file:text-xs file:font-semibold file:bg-cyan-600/20 file:text-cyan-300 hover:file:bg-cyan-600/30"
        />
      </div>

      <div className="space-y-2">
        <Label htmlFor="manifest">Or Paste Manifest JSON</Label>
        <textarea
          id="manifest"
          name="manifest"
          value={manifestText}
          onChange={(e) => setManifestText(e.target.value)}
          required
          rows={6}
          placeholder='{"format": "modvault-loadout/1", "name": "My Loadout", ...}'
          className="w-full rounded-md border border-border bg-card p-3 font-mono text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
        />
      </div>

      <Button
        type="submit"
        disabled={isPending || !manifestText.trim()}
        className="w-full bg-cyan-600 hover:bg-cyan-500 text-white font-medium text-xs"
      >
        {isPending ? 'Importing Loadout...' : 'Import Loadout'}
      </Button>
    </form>
  );
}
