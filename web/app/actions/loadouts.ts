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
    revalidatePath('/loadouts');
    revalidatePath('/', 'layout');
    redirect(`/loadouts/${newLoadoutId}`);
  }

  return { error: 'Failed to create loadout' };
}

const uuid = z.string().uuid('Invalid id');

const deleteLoadoutSchema = z.object({ loadout_id: uuid });

const updateOrderSchema = z.object({
  loadoutId: uuid,
  orderedVersionIds: z
    .array(uuid)
    .min(1, 'Load order is empty')
    .max(500, 'Too many mods in one loadout')
    .refine((ids) => new Set(ids).size === ids.length, 'Duplicate mod in load order'),
});

const toggleEnabledSchema = z.object({ loadoutId: uuid, versionId: uuid, enabled: z.boolean() });

const switchVersionSchema = z
  .object({ loadoutId: uuid, oldVersionId: uuid, newVersionId: uuid })
  .refine((v) => v.oldVersionId !== v.newVersionId, 'Pick a different version');

const removeModSchema = z.object({ loadoutId: uuid, versionId: uuid });

const autoSortSchema = z.object({ loadoutId: uuid });

const addDependencySchema = z.object({ loadoutId: uuid, relatedModId: uuid });
const NOT_OWNED = 'MODVAULT:NOT_FOUND: Loadout or mod not found, or you do not own this loadout';

function assertChanged(rowCount: number | null) {
  if (!rowCount) throw new Error(NOT_OWNED);
}

export async function deleteLoadoutAction(
  loadoutIdOrPrevState: string | ActionState,
  maybeFormData?: FormData
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  let rawId: unknown;
  if (typeof loadoutIdOrPrevState === 'string') {
    rawId = loadoutIdOrPrevState;
  } else if (maybeFormData instanceof FormData) {
    rawId = maybeFormData.get('loadout_id');
  }

  const parsed = deleteLoadoutSchema.safeParse({ loadout_id: rawId });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? 'Invalid input' };
  const { loadout_id } = parsed.data;

  try {
    await withUser(session, async (client) => {
      const res = await client.query('DELETE FROM loadouts WHERE loadout_id = $1', [loadout_id]);
      assertChanged(res.rowCount);
    });
    revalidatePath('/loadouts');
    revalidatePath('/', 'layout');
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

export async function updateLoadoutOrderAction(
  loadoutId: string,
  orderedVersionIds: string[]
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  const parsed = updateOrderSchema.safeParse({ loadoutId, orderedVersionIds });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? 'Invalid input' };
  const data = parsed.data;

  try {
    await withUser(session, async (client) => {
      for (let i = 0; i < data.orderedVersionIds.length; i++) {
        const res = await client.query(
          `UPDATE loadout_mods
           SET position = $1
           WHERE loadout_id = $2 AND version_id = $3`,
          [i, data.loadoutId, data.orderedVersionIds[i]]
        );
        assertChanged(res.rowCount);
      }
    });

    revalidatePath(`/loadouts/${data.loadoutId}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

export async function toggleModEnabledAction(
  loadoutId: string,
  versionId: string,
  enabled: boolean
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  const parsed = toggleEnabledSchema.safeParse({ loadoutId, versionId, enabled });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? 'Invalid input' };
  const data = parsed.data;

  try {
    await withUser(session, async (client) => {
      const res = await client.query(
        `UPDATE loadout_mods
         SET enabled = $1
         WHERE loadout_id = $2 AND version_id = $3`,
        [data.enabled, data.loadoutId, data.versionId]
      );
      assertChanged(res.rowCount);
    });

    revalidatePath(`/loadouts/${data.loadoutId}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

export async function switchModVersionAction(
  loadoutId: string,
  oldVersionId: string,
  newVersionId: string
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  const parsed = switchVersionSchema.safeParse({ loadoutId, oldVersionId, newVersionId });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? 'Invalid input' };
  const data = parsed.data;

  try {
    await withUser(session, async (client) => {
      const res = await client.query(
        `UPDATE loadout_mods x
         SET version_id = $1
         FROM mod_versions cur, mod_versions nxt
         WHERE x.loadout_id = $2 AND x.version_id = $3
           AND cur.version_id = $3 AND nxt.version_id = $1 AND cur.mod_id = nxt.mod_id`,
        [data.newVersionId, data.loadoutId, data.oldVersionId]
      );
      assertChanged(res.rowCount);
    });

    revalidatePath(`/loadouts/${data.loadoutId}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

export async function removeModFromLoadoutAction(
  loadoutId: string,
  versionId: string
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  const parsed = removeModSchema.safeParse({ loadoutId, versionId });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? 'Invalid input' };
  const data = parsed.data;

  try {
    await withUser(session, async (client) => {
      const res = await client.query(
        `DELETE FROM loadout_mods
         WHERE loadout_id = $1 AND version_id = $2`,
        [data.loadoutId, data.versionId]
      );
      assertChanged(res.rowCount);
    });

    revalidatePath(`/loadouts/${data.loadoutId}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

export async function autoSortLoadoutAction(loadoutId: string): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  const parsed = autoSortSchema.safeParse({ loadoutId });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? 'Invalid input' };
  const data = parsed.data;

  try {
    await withUser(session, async (client) => {
      const owned = await client.query(
        'SELECT 1 FROM loadouts WHERE loadout_id = $1 AND user_id = fn_current_user_id()',
        [data.loadoutId]
      );
      assertChanged(owned.rowCount);
      await client.query('CALL pr_apply_load_order($1::uuid)', [data.loadoutId]);
    });

    revalidatePath(`/loadouts/${data.loadoutId}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

export async function addMissingDependencyAction(
  loadoutId: string,
  relatedModId: string
): Promise<ActionState> {
  const session = await getSession();
  if (!session) return { error: 'Unauthorized' };

  const parsed = addDependencySchema.safeParse({ loadoutId, relatedModId });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? 'Invalid input' };
  const data = parsed.data;

  try {
    await withUser(session, async (client) => {
      const verRes = await client.query<{ version_id: string }>(
        `SELECT version_id FROM mod_versions
         WHERE mod_id = $1
         ORDER BY is_primary DESC, uploaded_at DESC
         LIMIT 1`,
        [data.relatedModId]
      );

      if (verRes.rows.length === 0) {
        throw new Error('MODVAULT:NOT_FOUND: No version found for required mod');
      }
      const primaryVersionId = verRes.rows[0].version_id;
      await client.query('CALL pr_add_mod_to_loadout($1::uuid, $2::uuid)', [
        data.loadoutId,
        primaryVersionId,
      ]);
    });

    revalidatePath(`/loadouts/${data.loadoutId}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

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
    revalidatePath('/loadouts');
    revalidatePath('/', 'layout');
    redirect(`/loadouts/${importedLoadoutId}?imported=true&skipped=${skippedCount}`);
  }

  return { error: 'Failed to retrieve imported loadout.' };
}

const directImportSchema = z.object({
  sourceLoadoutId: uuid,
});

export async function directImportLoadoutAction(
  sourceLoadoutId: string
): Promise<ActionState> {
  const session = await getSession();
  if (!session) {
    redirect(`/login?next=/loadouts/${sourceLoadoutId}`);
  }

  const parsed = directImportSchema.safeParse({ sourceLoadoutId });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? 'Invalid loadout ID' };
  }

  let newLoadoutId: string | null = null;

  try {
    newLoadoutId = await withUser(session, async (client) => {
      const sourceRes = await client.query<{
        game_id: string;
        name: string;
        description: string | null;
        game_version: string | null;
      }>(
        `SELECT game_id, name, description, game_version
         FROM loadouts
         WHERE loadout_id = $1 AND (is_public = TRUE OR user_id = fn_current_user_id() OR fn_current_role() = 'admin')`,
        [parsed.data.sourceLoadoutId]
      );

      if (sourceRes.rows.length === 0) {
        throw new Error('MODVAULT:NOT_FOUND: Community loadout not found or not public');
      }

      const source = sourceRes.rows[0];
      const newLoadoutRes = await client.query<{ loadout_id: string }>(
        `INSERT INTO loadouts (user_id, game_id, name, description, game_version, is_public)
         VALUES (fn_current_user_id(), $1, $2, $3, $4, FALSE)
         RETURNING loadout_id`,
        [source.game_id, source.name, source.description, source.game_version]
      );

      const createdId = newLoadoutRes.rows[0]?.loadout_id;
      if (!createdId) throw new Error('Failed to create imported loadout');
      await client.query(
        `INSERT INTO loadout_mods (loadout_id, version_id, position, enabled)
         SELECT $1, version_id, (row_number() over (ORDER BY position ASC, id ASC) - 1)::int, enabled
         FROM loadout_mods
         WHERE loadout_id = $2
         ORDER BY position ASC, id ASC`,
        [createdId, parsed.data.sourceLoadoutId]
      );

      return createdId;
    });
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }

  if (newLoadoutId) {
    revalidatePath('/loadouts');
    revalidatePath('/', 'layout');
    redirect(`/loadouts/${newLoadoutId}?imported=true`);
  }

  return { error: 'Failed to import loadout' };
}
