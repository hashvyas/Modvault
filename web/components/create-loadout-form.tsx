'use client';

import React, { useActionState } from 'react';
import { createLoadoutAction, type ActionState } from '@/app/actions/loadouts';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

interface GameItem {
  game_id: string;
  name: string;
  domain: string;
  current_version: string | null;
}

export function CreateLoadoutForm({ games }: { games: GameItem[] }) {
  const [state, formAction, isPending] = useActionState<ActionState, FormData>(
    createLoadoutAction,
    {}
  );

  return (
    <form action={formAction} className="space-y-4">
      {state.error && (
        <div className="p-3 rounded-lg bg-destructive/15 text-destructive border border-destructive/30 text-xs">
          {state.error}
        </div>
      )}

      <div className="space-y-1.5">
        <Label htmlFor="name">Loadout Name *</Label>
        <Input
          id="name"
          name="name"
          required
          placeholder="e.g. My Stable Skyrim Modpack"
          className="h-9 bg-card text-xs"
        />
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="game_id">Target Game *</Label>
          <select
            id="game_id"
            name="game_id"
            required
            className="w-full h-9 rounded-md border border-border bg-card px-2.5 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
          >
            <option value="">Select a game...</option>
            {games.map((g) => (
              <option key={g.game_id} value={g.game_id}>
                {g.name}
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="game_version">Target Game Version</Label>
          <Input
            id="game_version"
            name="game_version"
            placeholder="e.g. 1.6.1170"
            className="h-9 font-mono bg-card text-xs"
          />
        </div>
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="description">Description (optional)</Label>
        <textarea
          id="description"
          name="description"
          rows={2}
          placeholder="Notes on the theme, performance targets, or ENB requirements..."
          className="w-full rounded-md border border-border bg-card p-2 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
        />
      </div>

      <div className="flex items-center gap-2 pt-1">
        <input
          id="is_public"
          name="is_public"
          type="checkbox"
          className="rounded border-border text-cyan-600 focus:ring-cyan-500"
        />
        <Label htmlFor="is_public" className="cursor-pointer text-xs">
          Make this loadout public for community sharing
        </Label>
      </div>

      <Button
        type="submit"
        disabled={isPending}
        className="w-full bg-cyan-600 hover:bg-cyan-500 text-white font-medium text-xs"
      >
        {isPending ? 'Creating Loadout...' : 'Create Loadout'}
      </Button>
    </form>
  );
}
