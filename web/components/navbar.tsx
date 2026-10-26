import Link from 'next/link';
import { getSession } from '@/lib/session';
import { logoutAction } from '@/app/actions/auth';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';

export async function Navbar() {
  const session = await getSession();

  return (
    <nav className="border-b border-border bg-card/60 backdrop-blur-md sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        <div className="flex items-center space-x-8">
          <Link href="/" className="flex items-center space-x-2">
            <span className="text-xl font-bold tracking-tight bg-gradient-to-r from-cyan-400 to-indigo-400 bg-clip-text text-transparent">
              ModVault
            </span>
          </Link>
          <div className="hidden md:flex items-center space-x-5 text-sm font-medium">
            <Link
              href="/search"
              className="text-muted-foreground hover:text-foreground transition-colors"
            >
              Search
            </Link>
            <div className="flex items-center space-x-3 text-xs text-muted-foreground">
              <span className="text-border">|</span>
              <Link
                href="/games/skyrimspecialedition"
                className="hover:text-foreground transition-colors"
              >
                Skyrim SE
              </Link>
              <Link
                href="/games/fallout4"
                className="hover:text-foreground transition-colors"
              >
                Fallout 4
              </Link>
              <Link
                href="/games/stardewvalley"
                className="hover:text-foreground transition-colors"
              >
                Stardew Valley
              </Link>
            </div>
            {session && (
              <>
                <Link
                  href="/loadouts"
                  className="text-muted-foreground hover:text-foreground transition-colors"
                >
                  Loadouts
                </Link>
                <Link
                  href="/mods/new"
                  className="text-muted-foreground hover:text-foreground transition-colors"
                >
                  Publish Mod
                </Link>
              </>
            )}
            {(session?.role === 'curator' || session?.role === 'admin') && (
              <Link
                href="/curate"
                className="text-muted-foreground hover:text-foreground transition-colors"
              >
                Curation
              </Link>
            )}
            {session?.role === 'admin' && (
              <Link
                href="/admin"
                className="text-muted-foreground hover:text-foreground transition-colors"
              >
                Admin
              </Link>
            )}
          </div>
        </div>

        <div className="flex items-center space-x-3">
          {session ? (
            <div className="flex items-center space-x-3">
              <span className="text-xs text-muted-foreground hidden sm:inline">
                Signed in as
              </span>
              <span className="text-sm font-semibold text-foreground">
                {session.username}
              </span>
              <Badge variant="secondary" className="text-xs capitalize">
                {session.role}
              </Badge>
              <form action={logoutAction}>
                <Button variant="outline" size="xs" type="submit">
                  Sign Out
                </Button>
              </form>
            </div>
          ) : (
            <div className="flex items-center space-x-2">
              <Link href="/login">
                <Button variant="ghost" size="sm">
                  Sign In
                </Button>
              </Link>
              <Link href="/register">
                <Button size="sm">Register</Button>
              </Link>
            </div>
          )}
        </div>
      </div>
    </nav>
  );
}
