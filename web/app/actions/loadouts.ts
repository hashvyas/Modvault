'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { z } from 'zod';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { formatErrorMessage } from '@/lib/errors';

export type ActionState = {
  success?: boolean;
  error?: string | null;
  loadoutId?: string;
  skipped?: number;
};

const createLoadoutSchema = z.object({
  game_id: z.string().uuid('Invalid game selected'),
  name: z.string().min(1, 'Loadout name is required').max(255),
  description: z.string().max(2000).optional().default(''),
  game_version: z.string().max(50).optional().default(''),
  is_public: z.preprocess((val) => val === 'true' || val === 'on' || val === true, z.boolean()),
});

/**
 * Create a new loadout
 */
export async function createLoadoutAction(
  prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const session = await getSession();
  if (!session) {
    return { error: 'Please log in to create a loadout.' };
  }

  const parsed = createLoadoutSchema.safeParse({
    game_id: formData.get('game_id'),
    name: formData.get('name'),
    description: formData.get('description'),
    game_version: formData.get('game_version'),
    is_public: formData.get('is_public'),
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? 'Invalid input' };
  }

  const { game_id, name, description, game_version, is_public } = parsed.data;
  const userId = session.sub;
  let newLoadoutId: string | null = null;

  try {
    newLoadoutId = await withUser(session, async (client) => {
      const res = await client.query<{ loadout_id: string }>(
        `INSERT INTO loadouts (user_id, game_id, name, description, game_version, is_public)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING loadout_id`,
        [userId, game_id, name, description || null, game_version || null, is_public]
      );
      return res.rows[0]?.loadout_id;
    });
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }

  if (newLoadoutId) {
    redirect(`/loadouts/${newLoadoutId}`);
  }

  return { error: 'Failed to create loadout' };
}

/**
 * Delete a loadout
 */
export async function deleteLoadoutAction(
  prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  const loadoutId = formData.get('loadout_id') as string;
  if (!loadoutId) return { error: 'Missing loadout ID' };

  try {
    await withUser(session, async (client) => {
      await client.query('DELETE FROM loadouts WHERE loadout_id = $1', [loadoutId]);
    });
    revalidatePath('/loadouts');
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

/**
 * Update drag-and-drop order of mods in a loadout in a single transaction
 */
export async function updateLoadoutOrderAction(
  loadoutId: string,
  orderedVersionIds: string[]
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  try {
    await withUser(session, async (client) => {
      for (let i = 0; i < orderedVersionIds.length; i++) {
        await client.query(
          `UPDATE loadout_mods
           SET position = $1
           WHERE loadout_id = $2 AND version_id = $3`,
          [i, loadoutId, orderedVersionIds[i]]
        );
      }
    });

    revalidatePath(`/loadouts/${loadoutId}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

/**
 * Toggle enable/disable status for a mod in a loadout
 */
export async function toggleModEnabledAction(
  loadoutId: string,
  versionId: string,
  enabled: boolean
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  try {
    await withUser(session, async (client) => {
      await client.query(
        `UPDATE loadout_mods
         SET enabled = $1
         WHERE loadout_id = $2 AND version_id = $3`,
        [enabled, loadoutId, versionId]
      );
    });

    revalidatePath(`/loadouts/${loadoutId}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

/**
 * Switch the active version of a mod in a loadout
 */
export async function switchModVersionAction(
  loadoutId: string,
  oldVersionId: string,
  newVersionId: string
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  try {
    await withUser(session, async (client) => {
      await client.query(
        `UPDATE loadout_mods
         SET version_id = $1
         WHERE loadout_id = $2 AND version_id = $3`,
        [newVersionId, loadoutId, oldVersionId]
      );
    });

    revalidatePath(`/loadouts/${loadoutId}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

/**
 * Remove a mod from a loadout
 */
export async function removeModFromLoadoutAction(
  loadoutId: string,
  versionId: string
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  try {
    await withUser(session, async (client) => {
      await client.query(
        `DELETE FROM loadout_mods
         WHERE loadout_id = $1 AND version_id = $2`,
        [loadoutId, versionId]
      );
    });

    revalidatePath(`/loadouts/${loadoutId}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

/**
 * Apply auto-sorted load order to a loadout (pr_apply_load_order)
 */
export async function autoSortLoadoutAction(loadoutId: string): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  try {
    await withUser(session, async (client) => {
      await client.query('CALL pr_apply_load_order($1::uuid)', [loadoutId]);
    });

    revalidatePath(`/loadouts/${loadoutId}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

/**
 * Add a missing dependency's primary version to a loadout
 */
export async function addMissingDependencyAction(
  loadoutId: string,
  relatedModId: string
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  try {
    await withUser(session, async (client) => {
      // Find primary version of the related mod
      const verRes = await client.query<{ version_id: string }>(
        `SELECT version_id FROM mod_versions
         WHERE mod_id = $1
         ORDER BY is_primary DESC, uploaded_at DESC
         LIMIT 1`,
        [relatedModId]
      );

      if (verRes.rows.length === 0) {
        throw new Error('MODVAULT:NOT_FOUND: No version found for required mod');
      }

      const primaryVersionId = verRes.rows[0].version_id;
      await client.query('CALL pr_add_mod_to_loadout($1::uuid, $2::uuid)', [
        loadoutId,
        primaryVersionId,
      ]);
    });

    revalidatePath(`/loadouts/${loadoutId}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

/**
 * Import a loadout from JSON manifest
 */
export async function importLoadoutAction(
  prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Please log in to import a loadout.' };

  const rawManifest = formData.get('manifest') as string;
  if (!rawManifest || !rawManifest.trim()) {
    return { error: 'Please provide manifest JSON data' };
  }

  let manifestObj: unknown;
  try {
    manifestObj = JSON.parse(rawManifest.trim());
  } catch {
    return { error: 'Invalid JSON format in manifest.' };
  }

  let importedLoadoutId: string | null = null;
  let skippedCount = 0;

  try {
    const res = await withUser(session, async (client) => {
      const qRes = await client.query<{ p_loadout_id: string; p_skipped: number }>(
        'CALL pr_import_loadout($1::jsonb, NULL, NULL)',
        [JSON.stringify(manifestObj)]
      );
      return qRes.rows[0];
    });

    importedLoadoutId = res?.p_loadout_id ?? null;
    skippedCount = res?.p_skipped ?? 0;
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }

  if (importedLoadoutId) {
    redirect(`/loadouts/${importedLoadoutId}?imported=true&skipped=${skippedCount}`);
  }

  return { error: 'Failed to retrieve imported loadout.' };
}
