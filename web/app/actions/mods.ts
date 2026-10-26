'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { z } from 'zod';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { embed, toPgVector } from '@/lib/embed';
import { formatErrorMessage } from '@/lib/errors';

const publishModSchema = z.object({
  game_id: z.string().uuid('Invalid game selected'),
  name: z.string().min(1, 'Mod name is required').max(255),
  summary: z.string().max(2000).optional().default(''),
  category: z.string().max(100).optional().default(''),
  semver: z.string().min(1, 'Version semver is required').max(20),
  tags: z.string().optional().default(''),
});

const reviewSchema = z.object({
  mod_id: z.string().uuid(),
  rating: z.coerce.number().int().min(1).max(5),
  body: z.string().max(5000).optional().default(''),
});

const addToLoadoutSchema = z.object({
  loadout_id: z.string().uuid(),
  version_id: z.string().uuid(),
  mod_id: z.string().uuid(),
});

const promoteVersionSchema = z.object({
  version_id: z.string().uuid(),
  mod_id: z.string().uuid(),
});

export type ActionState = {
  success?: boolean;
  error?: string | null;
};

/**
 * Promote a version to primary (Curators and Admins only)
 */
export async function promoteVersionAction(
  prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const session = await getSession();
  if (!session || (session.role !== 'curator' && session.role !== 'admin')) {
    return { error: 'Only curators and administrators can promote versions.' };
  }

  const parseResult = promoteVersionSchema.safeParse({
    version_id: formData.get('version_id'),
    mod_id: formData.get('mod_id'),
  });

  if (!parseResult.success) {
    return { error: parseResult.error.issues[0]?.message ?? 'Invalid parameters' };
  }

  const { version_id, mod_id } = parseResult.data;

  try {
    await withUser(session, async (client) => {
      await client.query('CALL pr_promote_version($1::uuid)', [version_id]);
    });

    revalidatePath(`/mods/${mod_id}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

/**
 * Insert or update user review for a mod
 */
export async function reviewModAction(
  prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const session = await getSession();
  if (!session) {
    return { error: 'Please log in to submit a review.' };
  }

  const parseResult = reviewSchema.safeParse({
    mod_id: formData.get('mod_id'),
    rating: formData.get('rating'),
    body: formData.get('body'),
  });

  if (!parseResult.success) {
    return { error: parseResult.error.issues[0]?.message ?? 'Invalid review data' };
  }

  const { mod_id, rating, body } = parseResult.data;
  const userId = session.sub;

  try {
    await withUser(session, async (client) => {
      await client.query(
        `INSERT INTO reviews (user_id, mod_id, rating, body, created_at)
         VALUES ($1, $2, $3, $4, NOW())
         ON CONFLICT (user_id, mod_id)
         DO UPDATE SET rating = EXCLUDED.rating, body = EXCLUDED.body, created_at = NOW()`,
        [userId, mod_id, rating, body || null]
      );
    });

    revalidatePath(`/mods/${mod_id}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

/**
 * Add a mod version to a user loadout
 */
export async function addToLoadoutAction(
  prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const session = await getSession();
  if (!session) {
    return { error: 'Please log in to manage loadouts.' };
  }

  const parseResult = addToLoadoutSchema.safeParse({
    loadout_id: formData.get('loadout_id'),
    version_id: formData.get('version_id'),
    mod_id: formData.get('mod_id'),
  });

  if (!parseResult.success) {
    return { error: parseResult.error.issues[0]?.message ?? 'Invalid loadout selection' };
  }

  const { loadout_id, version_id, mod_id } = parseResult.data;

  try {
    await withUser(session, async (client) => {
      await client.query('CALL pr_add_mod_to_loadout($1::uuid, $2::uuid)', [
        loadout_id,
        version_id,
      ]);
    });

    revalidatePath(`/mods/${mod_id}`);
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

/**
 * Publish a new mod
 */
export async function publishModAction(
  prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const session = await getSession();
  if (!session) {
    return { error: 'Please log in to publish a mod.' };
  }

  const rawTags = (formData.get('tags') as string) || '';
  const parsed = publishModSchema.safeParse({
    game_id: formData.get('game_id'),
    name: formData.get('name'),
    summary: formData.get('summary'),
    category: formData.get('category'),
    semver: formData.get('semver'),
    tags: rawTags,
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? 'Invalid form submission' };
  }

  const { game_id, name, summary, category, semver } = parsed.data;

  // Split comma or space separated tags into array of slugs
  const tagList = rawTags
    .split(/[,;\s]+/)
    .map((t) => t.trim().toLowerCase().replace(/[^a-z0-9-]/g, '-'))
    .filter((t) => t.length > 0);

  let newModId: string | null = null;

  try {
    // Generate 384-dimension vector embedding for new mod
    const textToEmbed = `${name}. ${category}. ${summary}`;
    const vector = await embed(textToEmbed);
    const pgEmbedding = toPgVector(vector);

    newModId = await withUser(session, async (client) => {
      const res = await client.query<{ p_mod_id: string }>(
        'CALL pr_publish_mod($1, $2, $3, $4, $5, $6::text[], $7::vector, NULL)',
        [game_id, name, summary || null, category || null, semver, tagList, pgEmbedding]
      );
      return res.rows[0]?.p_mod_id ?? null;
    });
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }

  if (newModId) {
    redirect(`/mods/${newModId}`);
  }

  return { error: 'Mod was created but ID could not be retrieved.' };
}


