import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function CuratePage() {
  const session = await getSession();
  return (
    <main className="p-8 space-y-4">
      <h1 className="text-2xl font-bold">Curator Dashboard</h1>
      <p className="text-muted-foreground">
        Access granted for: <strong>{session?.username}</strong> (role: <strong>{session?.role}</strong>)
      </p>
    </main>
  );
}
