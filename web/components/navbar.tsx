import Link from 'next/link';
import { Search } from 'lucide-react';
import { getSession } from '@/lib/session';
import { logoutAction } from '@/app/actions/auth';
import { Button, buttonVariants } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';

// Every nav item shares this height and text size so they sit on one baseline.
const navLink =
  'inline-flex h-8 items-center text-sm font-medium text-muted-foreground hover:text-foreground transition-colors';

export async function Navbar() {
  const session = await getSession();

  return (
    <nav className="border-b border-border bg-card sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        <div className="flex items-center gap-8">
          <Link href="/" className="flex items-center">
            <span className="text-xl font-bold tracking-tight bg-gradient-to-r from-cyan-400 to-indigo-400 bg-clip-text text-transparent">
              ModVault
            </span>
          </Link>
          <div className="hidden md:flex items-center gap-5">
            <Link
              href="/search"
              aria-label="Search"
              title="Search"
              className={buttonVariants({ variant: 'ghost', size: 'icon' })}
            >
              <Search />
            </Link>
            <span className="text-border">|</span>
            <Link href="/games/skyrimspecialedition" className={navLink}>
              Skyrim SE
            </Link>
            <Link href="/games/fallout4" className={navLink}>
              Fallout 4
            </Link>
            <Link href="/games/stardewvalley" className={navLink}>
              Stardew Valley
            </Link>
            {session && (
              <>
                <Link href="/loadouts" className={navLink}>
                  Loadouts
                </Link>
                <Link href="/mods/new" className={navLink}>
                  Publish Mod
                </Link>
              </>
            )}
            {(session?.role === 'curator' || session?.role === 'admin') && (
              <Link href="/curate" className={navLink}>
                Curation
              </Link>
            )}
            {session?.role === 'admin' && (
              <Link href="/admin" className={navLink}>
                Admin
              </Link>
            )}
          </div>
        </div>

        <div className="flex items-center gap-3">
          {session ? (
            <>
              <span className="text-sm text-muted-foreground hidden sm:inline">
                Signed in as
              </span>
              <span className="text-sm font-semibold text-foreground">
                {session.username}
              </span>
              <Badge variant="secondary" className="h-8 text-sm capitalize">
                {session.role}
              </Badge>
              <form action={logoutAction} className="flex">
                <Button type="submit">Sign Out</Button>
              </form>
            </>
          ) : (
            <>
              <Link href="/login" className={buttonVariants({ variant: 'ghost' })}>
                Sign In
              </Link>
              <Link href="/register" className={buttonVariants()}>
                Register
              </Link>
            </>
          )}
        </div>
      </div>
    </nav>
  );
}
