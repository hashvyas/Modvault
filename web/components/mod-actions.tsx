'use client';

import React, { useActionState } from 'react';
import Link from 'next/link';
import {
  promoteVersionAction,
  reviewModAction,
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
}

interface ReviewItem {
  review_id: string;
  user_id: string;
  rating: number;
  body: string | null;
  created_at: string;
  username: string;
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

  const primaryVer = versions.find((v) => v.is_primary) ?? versions[0];

  return (
    <div className="p-4 rounded-xl border border-border bg-card/40 space-y-3">
      <div className="flex items-center justify-between">
        <h4 className="text-sm font-semibold">Add to Loadout</h4>
        {state.success && (
          <span className="text-xs text-emerald-400 font-medium">Added to loadout!</span>
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
          className="h-9 flex-1 rounded-md border border-border bg-card px-2.5 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
        >
          {loadouts.map((l) => (
            <option key={l.loadout_id} value={l.loadout_id}>
              {l.name} {l.game_version ? `(${l.game_version})` : ''}
            </option>
          ))}
        </select>

        <select
          name="version_id"
          defaultValue={primaryVer?.version_id}
          className="h-9 w-36 rounded-md border border-border bg-card px-2.5 text-xs font-mono text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
        >
          {versions.map((v) => (
            <option key={v.version_id} value={v.version_id}>
              v{v.semver} {v.is_primary ? '(Primary)' : ''}
            </option>
          ))}
        </select>

        <Button
          type="submit"
          size="sm"
          disabled={isPending}
          className="bg-cyan-600 hover:bg-cyan-500 text-white font-medium whitespace-nowrap"
        >
          {isPending ? 'Adding...' : 'Add to Loadout'}
        </Button>
      </form>
    </div>
  );
}

// ---------------------------------------------------------------------------
// 3. Reviews List and Review Form Component
// ---------------------------------------------------------------------------
export function ReviewSection({
  modId,
  reviews,
  currentUserId,
}: {
  modId: string;
  reviews: ReviewItem[];
  currentUserId: string | null;
}) {
  const [state, formAction, isPending] = useActionState<ActionState, FormData>(
    reviewModAction,
    {}
  );

  const existingReview = reviews.find((r) => r.user_id === currentUserId);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-bold">Community Reviews</h3>
          <p className="text-xs text-muted-foreground">{reviews.length} user reviews submitted</p>
        </div>
      </div>

      {/* Review Submission Form */}
      {currentUserId ? (
        <form action={formAction} className="p-4 rounded-xl border border-border bg-card/40 space-y-3">
          <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            {existingReview ? 'Update Your Review' : 'Write a Review'}
          </h4>

          {state.error && (
            <div className="p-2.5 rounded bg-destructive/15 text-destructive text-xs">
              {state.error}
            </div>
          )}

          {state.success && (
            <div className="p-2.5 rounded bg-emerald-500/15 text-emerald-400 text-xs">
              Review saved successfully!
            </div>
          )}

          <input type="hidden" name="mod_id" value={modId} />

          <div className="flex items-center gap-3">
            <label className="text-xs text-muted-foreground">Rating:</label>
            <select
              name="rating"
              defaultValue={existingReview?.rating ?? 5}
              className="h-8 rounded-md border border-border bg-card px-2 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
            >
              <option value="5">★★★★★ (5 - Excellent)</option>
              <option value="4">★★★★☆ (4 - Great)</option>
              <option value="3">★★★☆☆ (3 - Average)</option>
              <option value="2">★★☆☆☆ (2 - Poor)</option>
              <option value="1">★☆☆☆☆ (1 - Terrible)</option>
            </select>
          </div>

          <textarea
            name="body"
            defaultValue={existingReview?.body ?? ''}
            rows={3}
            placeholder="Share your experience with compatibility, performance, or bugs..."
            className="w-full rounded-md border border-border bg-card p-2.5 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-cyan-500"
          />

          <Button
            type="submit"
            size="sm"
            disabled={isPending}
            className="bg-cyan-600 hover:bg-cyan-500 text-white font-medium"
          >
            {isPending ? 'Saving...' : existingReview ? 'Update Review' : 'Submit Review'}
          </Button>
        </form>
      ) : (
        <div className="p-4 rounded-xl border border-dashed border-border text-center text-xs text-muted-foreground">
          <Link href="/login" className="text-cyan-400 hover:underline font-semibold">
            Sign in
          </Link>{' '}
          to submit or update your review for this mod.
        </div>
      )}

      {/* Review List */}
      <div className="space-y-3">
        {reviews.length === 0 ? (
          <p className="text-xs text-muted-foreground italic">No reviews yet for this mod.</p>
        ) : (
          reviews.map((r) => (
            <div
              key={r.review_id}
              className="p-3.5 rounded-lg border border-border/60 bg-card/25 space-y-1.5"
            >
              <div className="flex items-center justify-between text-xs">
                <span className="font-semibold text-foreground">{r.username}</span>
                <span className="text-amber-400 font-mono">
                  {'★'.repeat(r.rating)}
                  {'☆'.repeat(5 - r.rating)}
                </span>
              </div>
              {r.body && <p className="text-xs text-muted-foreground leading-relaxed">{r.body}</p>}
              <div className="text-[10px] text-muted-foreground/60">
                {new Date(r.created_at).toLocaleDateString()}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
