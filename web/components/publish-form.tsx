'use client';

import React, { useActionState } from 'react';
import { publishModAction, type ActionState } from '@/app/actions/mods';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

interface GameItem {
  game_id: string;
  name: string;
  domain: string;
}

interface Props {
  games: GameItem[];
}

export function PublishForm({ games }: Props) {
  const [state, formAction, isPending] = useActionState<ActionState, FormData>(
    publishModAction,
    {}
  );

  return (
    <form action={formAction} className="space-y-6">
      {state.error && (
        <div className="p-3.5 rounded-lg bg-destructive/15 border border-destructive/30 text-destructive text-sm">
          {state.error}
        </div>
      )}

      {/* Game Selection */}
      <div className="space-y-2">
        <Label htmlFor="game_id">Target Game *</Label>
        <select
          id="game_id"
          name="game_id"
          required
          className="w-full h-10 rounded-md border border-border bg-card px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
        >
          <option value="">Select a game...</option>
          {games.map((g) => (
            <option key={g.game_id} value={g.game_id}>
              {g.name} ({g.domain})
            </option>
          ))}
        </select>
      </div>

      {/* Mod Name & Semver */}
      <div className="grid gap-4 sm:grid-cols-3">
        <div className="sm:col-span-2 space-y-2">
          <Label htmlFor="name">Mod Name *</Label>
          <Input
            id="name"
            name="name"
            required
            placeholder="e.g. Modern UI Framework"
            className="h-10 bg-card"
          />
        </div>

        <div className="space-y-2">
          <Label htmlFor="semver">Initial Version *</Label>
          <Input
            id="semver"
            name="semver"
            required
            defaultValue="1.0.0"
            placeholder="1.0.0"
            className="h-10 font-mono bg-card"
          />
        </div>
      </div>

      {/* Category and Tags */}
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor="category">Category</Label>
          <Input
            id="category"
            name="category"
            placeholder="e.g. User Interface, Utilities, Gameplay"
            className="h-10 bg-card"
          />
        </div>

        <div className="space-y-2">
          <Label htmlFor="tags">Tags (comma or space separated)</Label>
          <Input
            id="tags"
            name="tags"
            placeholder="e.g. user-interface, frameworks, utilities"
            className="h-10 bg-card"
          />
        </div>
      </div>

      {/* Summary */}
      <div className="space-y-2">
        <Label htmlFor="summary">Mod Summary & Description</Label>
        <textarea
          id="summary"
          name="summary"
          rows={4}
          placeholder="Brief description of what this mod does. This text will be embedded into pgvector for semantic search..."
          className="w-full rounded-md border border-border bg-card p-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
        />
        <p className="text-xs text-muted-foreground">
          ModVault will automatically generate a 384-dimensional semantic embedding and full-text search vector on submission.
        </p>
      </div>

      <div className="flex items-center justify-end gap-3 pt-4 border-t border-border">
        <Button
          type="submit"
          disabled={isPending}
          className="px-6 bg-cyan-600 hover:bg-cyan-500 text-white font-medium"
        >
          {isPending ? 'Publishing & Embedding...' : 'Publish Mod'}
        </Button>
      </div>
    </form>
  );
}
