import { NextRequest, NextResponse } from 'next/server';
import { jwtVerify } from 'jose';
import { getJwtSecretKey } from '@/lib/jwt-secret';

const SESSION_COOKIE_NAME = 'modvault_session';

export async function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;

  let secretKey: Uint8Array;
  try {
    secretKey = getJwtSecretKey();
  } catch (err) {
    console.error(err);
    if (pathname === '/login') return NextResponse.next();
    return NextResponse.redirect(new URL('/login', req.url));
  }
  const token = req.cookies.get(SESSION_COOKIE_NAME)?.value;

  let session: { sub: string; username: string; role: string } | null = null;
  if (token) {
    try {
      const { payload } = await jwtVerify(token, secretKey, {
        algorithms: ['HS256'],
      });
      session = payload as unknown as { sub: string; username: string; role: string };
    } catch {
      session = null;
    }
  }

  const role = session?.role || 'anonymous';
  const isAuthenticated = !!session;
  if (pathname.startsWith('/admin')) {
    if (!isAuthenticated) {
      const loginUrl = new URL('/login', req.url);
      loginUrl.searchParams.set('next', pathname);
      return NextResponse.redirect(loginUrl);
    }
    if (role !== 'admin') {
      return NextResponse.redirect(new URL('/', req.url));
    }
    return NextResponse.next();
  }
  if (pathname.startsWith('/curate')) {
    if (!isAuthenticated) {
      const loginUrl = new URL('/login', req.url);
      loginUrl.searchParams.set('next', pathname);
      return NextResponse.redirect(loginUrl);
    }
    if (role !== 'admin' && role !== 'curator') {
      return NextResponse.redirect(new URL('/', req.url));
    }
    return NextResponse.next();
  }
  const isProtectedModderPath =
    pathname === '/loadouts' ||
    pathname === '/loadouts/new' ||
    pathname === '/mods/new';

  if (isProtectedModderPath) {
    if (!isAuthenticated) {
      const loginUrl = new URL('/login', req.url);
      loginUrl.searchParams.set('next', pathname);
      return NextResponse.redirect(loginUrl);
    }
    if (!['modder', 'curator', 'admin'].includes(role)) {
      return NextResponse.redirect(new URL('/', req.url));
    }
    return NextResponse.next();
  }
  return NextResponse.next();
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
};
