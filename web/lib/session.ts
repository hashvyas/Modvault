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
const SESSION_EXPIRY_SECONDS = 7 * 24 * 60 * 60; // 7 days

/**
 * Sign a JWT token with sub, username, and role using HS256 algorithm.
 */
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

/**
 * Verify and decode a session token. Returns null if invalid or expired.
 */
export async function verifySessionToken(token: string): Promise<SessionPayload | null> {
  // Outside the try: a missing secret is a config error, not an invalid token.
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

/**
 * Read the current session from incoming request cookies in Server Components or Actions.
 */
export async function getSession(): Promise<SessionPayload | null> {
  const cookieStore = await cookies();
  const token = cookieStore.get(SESSION_COOKIE_NAME)?.value;
  if (!token) return null;
  return verifySessionToken(token);
}

/**
 * Set the session cookie with httpOnly, lax sameSite, and 7 days expiration.
 */
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

/**
 * Clear the session cookie to log out.
 */
export async function deleteSession(): Promise<void> {
  const cookieStore = await cookies();
  cookieStore.delete(SESSION_COOKIE_NAME);
}
