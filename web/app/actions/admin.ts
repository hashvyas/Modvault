'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { formatErrorMessage } from '@/lib/errors';

export type ActionState = {
  success?: boolean;
  error?: string | null;
  message?: string | null;
};

const setUserRoleSchema = z.object({
  user_id: z.string().uuid(),
  role: z.enum(['modder', 'curator', 'admin']),
});

/**
 * Change a user's role (Admin only)
 */
export async function setUserRoleAction(
  prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const session = await getSession();
  if (!session || session.role !== 'admin') {
    return { error: 'Only administrators can update user roles.' };
  }

  const parsed = setUserRoleSchema.safeParse({
    user_id: formData.get('user_id'),
    role: formData.get('role'),
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? 'Invalid input' };
  }

  const { user_id, role } = parsed.data;

  try {
    await withUser(session, async (client) => {
      await client.query('CALL pr_set_user_role($1::uuid, $2::user_role_enum)', [
        user_id,
        role,
      ]);
    });

    revalidatePath('/admin');
    return { success: true, message: `Updated user role to ${role}` };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}

/**
 * Refresh materialized view mv_game_leaderboard concurrently (Admin only)
 */
export async function refreshReportsAction(): Promise<ActionState> {
  const session = await getSession();
  if (!session || session.role !== 'admin') {
    return { error: 'Only administrators can refresh reports.' };
  }

  try {
    await withUser(session, async (client) => {
      await client.query('CALL pr_refresh_reports()');
    });

    revalidatePath('/admin');
    revalidatePath('/');
    return { success: true, message: 'Materialized view mv_game_leaderboard refreshed successfully.' };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}
