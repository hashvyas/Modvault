import { cookies } from 'next/headers';
import { SignJWT, jwtVerify } from 'jose';
import { getJwtSecretKey } from '@/lib/jwt-secret';

export interface SessionPayload {
  sub: string;
  username: string;
  role: 'modder' | 'curator' | 'admin' | string;
  iat?: number;
  exp?: number;
}

export const SESSION_COOKIE_NAME = 'modvault_session';
const SESSION_EXPIRY_SECONDS = 7 * 24 * 60 * 60;

export async function createSessionToken(payload: {
  sub: string;
  username: string;
  role: string;
}): Promise<string> {
  return new SignJWT({
    sub: payload.sub,
    username: payload.username,
    role: payload.role,
  })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('7d')
    .sign(getJwtSecretKey());
}

export async function verifySessionToken(token: string): Promise<SessionPayload | null> {
  const key = getJwtSecretKey();
  try {
    const { payload } = await jwtVerify(token, key, {
      algorithms: ['HS256'],
    });
    return payload as unknown as SessionPayload;
  } catch {
    return null;
  }
}

export async function getSession(): Promise<SessionPayload | null> {
  const cookieStore = await cookies();
  const token = cookieStore.get(SESSION_COOKIE_NAME)?.value;
  if (!token) return null;
  return verifySessionToken(token);
}

export async function setSessionCookie(token: string): Promise<void> {
  const cookieStore = await cookies();
  cookieStore.set(SESSION_COOKIE_NAME, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: SESSION_EXPIRY_SECONDS,
    path: '/',
  });
}

export async function deleteSession(): Promise<void> {
  const cookieStore = await cookies();
  cookieStore.delete(SESSION_COOKIE_NAME);
}
