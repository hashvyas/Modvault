'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { formatErrorMessage } from '@/lib/errors';

export type ActionState = {
  success?: boolean;
  error?: string | null;
};

const upsertCompatSchema = z.object({
  version_a: z.string().uuid(),
  version_b: z.string().uuid(),
  status: z.enum(['compatible', 'incompatible', 'partial', 'unknown']),
  reason: z.string().max(1000).optional().default(''),
  files: z.string().optional().default(''),
});

export async function upsertCompatibilityAction(
  prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const session = await getSession();
  if (!session || (session.role !== 'curator' && session.role !== 'admin')) {
    return { error: 'Only curators and administrators can record compatibility.' };
  }

  const parsed = upsertCompatSchema.safeParse({
    version_a: formData.get('version_a'),
    version_b: formData.get('version_b'),
    status: formData.get('status'),
    reason: formData.get('reason'),
    files: formData.get('files'),
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? 'Invalid input data' };
  }

  const { version_a, version_b, status, reason, files } = parsed.data;

  const fileList = files
    .split(/[\n,;]+/)
    .map((f) => f.trim())
    .filter((f) => f.length > 0);

  const detailObj: Record<string, unknown> = {};
  if (reason.trim()) detailObj.reason = reason.trim();
  if (fileList.length > 0) detailObj.files = fileList;

  try {
    await withUser(session, async (client) => {
      let detail: unknown = detailObj;
      // Empty reason and files keep the stored detail, so a re-save never wipes it to {}.
      if (Object.keys(detailObj).length === 0) {
        const existing = await client.query<{ conflict_detail: unknown }>(
          `SELECT conflict_detail FROM compatibility_matrix
           WHERE version_a_id = least($1::uuid, $2::uuid) AND version_b_id = greatest($1::uuid, $2::uuid)`,
          [version_a, version_b]
        );
        detail = existing.rows[0]?.conflict_detail ?? detailObj;
      }
      await client.query(
        'CALL pr_upsert_compatibility($1::uuid, $2::uuid, $3::compat_status_enum, $4::jsonb)',
        [version_a, version_b, status, JSON.stringify(detail)]
      );
    });

    const domain = (formData.get('domain') as string) || '';
    if (domain) {
      revalidatePath(`/games/${domain}/compat`);
    }
    revalidatePath('/loadouts');
    return { success: true };
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }
}
