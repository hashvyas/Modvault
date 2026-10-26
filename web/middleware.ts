import { NextRequest, NextResponse } from 'next/server';
import { jwtVerify } from 'jose';

const SESSION_COOKIE_NAME = 'modvault_session';

function getSecretKey(): Uint8Array {
  const secret = process.env.JWT_SECRET || 'fallback-secret-for-development-must-be-at-least-32-chars';
  return new TextEncoder().encode(secret);
}

export async function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;

  // Static files and internal Next.js assets are skipped via config.matcher
  const token = req.cookies.get(SESSION_COOKIE_NAME)?.value;

  let session: { sub: string; username: string; role: string } | null = null;
  if (token) {
    try {
      const { payload } = await jwtVerify(token, getSecretKey(), {
        algorithms: ['HS256'],
      });
      session = payload as unknown as { sub: string; username: string; role: string };
    } catch {
      session = null;
    }
  }

  const role = session?.role || 'anonymous';
  const isAuthenticated = !!session;

  // 1. Admin only paths: /admin and /admin/**
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

  // 2. Curator and Admin paths: /curate and /curate/**
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

  // 3. Modder, Curator, Admin paths: /loadouts, /loadouts/new, /mods/new
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

  // 4. Public paths: /, /search, /games/**, /mods/** (except /mods/new), /loadouts/:id (checked in page component)
  return NextResponse.next();
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
};
