'use server';

import { z } from 'zod';
import { withUser } from '@/lib/db';
import { createSessionToken, setSessionCookie, deleteSession } from '@/lib/session';
import { formatErrorMessage } from '@/lib/errors';
import { redirect } from 'next/navigation';

const loginSchema = z.object({
  username: z.string().min(1, 'Username is required'),
  password: z.string().min(1, 'Password is required'),
});

const registerSchema = z.object({
  username: z.string().min(3, 'Username must be at least 3 characters').max(50),
  email: z.string().email('Please enter a valid email address'),
  password: z.string().min(6, 'Password must be at least 6 characters'),
});

export type AuthState = {
  error?: string;
};

export async function loginAction(
  prevState: AuthState | null,
  formData: FormData
): Promise<AuthState> {
  const parsed = loginSchema.safeParse({
    username: formData.get('username'),
    password: formData.get('password'),
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0].message };
  }

  const { username, password } = parsed.data;

  try {
    const user = await withUser(null, async (client) => {
      const res = await client.query<{
        user_id: string;
        username: string;
        role: string;
      }>('SELECT user_id, username, role FROM fn_authenticate($1, $2)', [
        username,
        password,
      ]);
      return res.rows[0] || null;
    });

    if (!user) {
      return { error: 'Invalid username or password' };
    }

    const token = await createSessionToken({
      sub: user.user_id,
      username: user.username,
      role: user.role,
    });

    await setSessionCookie(token);
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }

  const next = formData.get('next')?.toString() || '/';
  // Only same-site paths: "//host" and absolute URLs would redirect off-site.
  redirect(next.startsWith('/') && !next.startsWith('//') && !next.startsWith('/\\') ? next : '/');
}

export async function registerAction(
  prevState: AuthState | null,
  formData: FormData
): Promise<AuthState> {
  const parsed = registerSchema.safeParse({
    username: formData.get('username'),
    email: formData.get('email'),
    password: formData.get('password'),
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0].message };
  }

  const { username, email, password } = parsed.data;

  try {
    await withUser(null, async (client) => {
      await client.query('SELECT fn_register_user($1, $2, $3)', [
        username,
        email,
        password,
      ]);
    });

    // Auto-login per spec
    const user = await withUser(null, async (client) => {
      const res = await client.query<{
        user_id: string;
        username: string;
        role: string;
      }>('SELECT user_id, username, role FROM fn_authenticate($1, $2)', [
        username,
        password,
      ]);
      return res.rows[0] || null;
    });

    if (!user) {
      return { error: 'Registration succeeded, but auto-login failed. Please sign in.' };
    }

    const token = await createSessionToken({
      sub: user.user_id,
      username: user.username,
      role: user.role,
    });

    await setSessionCookie(token);
  } catch (err) {
    return { error: formatErrorMessage(err) };
  }

  redirect('/');
}

export async function logoutAction() {
  await deleteSession();
  redirect('/login');
}
