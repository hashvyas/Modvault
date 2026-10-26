import { redirect } from 'next/navigation';
import { getSession } from '@/lib/session';
import { withUser } from '@/lib/db';
import { Badge } from '@/components/ui/badge';
import { RefreshReportsButton } from '@/components/refresh-reports-button';
import { AdminUsersTable, type UserItem } from '@/components/admin-users-table';
import { AuditLogViewer, type AuditLogRow } from '@/components/audit-log-viewer';

export const dynamic = 'force-dynamic';

type Props = {
  searchParams: Promise<{
    table?: string;
    op?: string;
    user?: string;
    from?: string;
    to?: string;
    page?: string;
  }>;
};

export default async function AdminDashboardPage({ searchParams }: Props) {
  const session = await getSession();
  if (!session || session.role !== 'admin') {
    redirect('/login?next=/admin');
  }

  const sParams = await searchParams;
  const currentTable = sParams.table || '';
  const currentOp = sParams.op || '';
  const currentUser = sParams.user || '';
  const currentFrom = sParams.from || '';
  const currentTo = sParams.to || '';
  const currentPage = Math.max(1, parseInt(sParams.page || '1', 10));
  const PAGE_SIZE = 50;
  const offset = (currentPage - 1) * PAGE_SIZE;

  let auditLogs: AuditLogRow[] = [];
  let totalLogs = 0;
  let tables: string[] = [];
  let users: UserItem[] = [];

  try {
    const data = await withUser(session, async (client) => {
      // 1. Fetch distinct audit tables
      const tRes = await client.query<{ table_name: string }>(
        'SELECT DISTINCT table_name FROM audit_log ORDER BY table_name ASC'
      );

      // 2. Build filtered audit log query
      const conditions: string[] = ['1=1'];
      const queryParams: unknown[] = [];

      if (currentTable) {
        queryParams.push(currentTable);
        conditions.push(`a.table_name = $${queryParams.length}`);
      }

      if (currentOp) {
        queryParams.push(currentOp);
        conditions.push(`a.operation = $${queryParams.length}`);
      }

      if (currentUser) {
        queryParams.push(`%${currentUser}%`);
        conditions.push(`(u.username ILIKE $${queryParams.length} OR a.changed_by::text ILIKE $${queryParams.length})`);
      }

      if (currentFrom) {
        queryParams.push(currentFrom);
        conditions.push(`a.changed_at >= $${queryParams.length}::timestamptz`);
      }

      if (currentTo) {
        queryParams.push(currentTo);
        conditions.push(`a.changed_at <= $${queryParams.length}::timestamptz`);
      }

      const whereClause = conditions.join(' AND ');

      // Total count
      const countRes = await client.query<{ count: string }>(
        `SELECT count(*)::text AS count
         FROM audit_log a
         LEFT JOIN users u ON a.changed_by = u.user_id
         WHERE ${whereClause}`,
        queryParams
      );
      const total = parseInt(countRes.rows[0]?.count ?? '0', 10);

      // Paginated logs
      queryParams.push(PAGE_SIZE);
      const limitIdx = queryParams.length;
      queryParams.push(offset);
      const offsetIdx = queryParams.length;

      const logsRes = await client.query<AuditLogRow>(
        `SELECT a.audit_id::text, a.table_name, a.operation, a.row_pk::text,
                a.old_row, a.new_row, a.changed_at::text,
                u.username AS changed_by_username
         FROM audit_log a
         LEFT JOIN users u ON a.changed_by = u.user_id
         WHERE ${whereClause}
         ORDER BY a.changed_at DESC, a.audit_id DESC
         LIMIT $${limitIdx} OFFSET $${offsetIdx}`,
        queryParams
      );

      // 3. Fetch all registered users
      const usersRes = await client.query<UserItem>(
        `SELECT user_id, username, email, role, is_active, created_at::text
         FROM users
         ORDER BY username ASC`
      );

      return {
        tables: tRes.rows.map((r) => r.table_name),
        logs: logsRes.rows,
        totalLogs: total,
        users: usersRes.rows,
      };
    });

    tables = data.tables;
    auditLogs = data.logs;
    totalLogs = data.totalLogs;
    users = data.users;
  } catch (err) {
    console.error('Error fetching admin dashboard data:', err);
  }

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-10">
      {/* Admin Header */}
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4 border-b border-border pb-6">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-extrabold tracking-tight">System Administration</h1>
            <Badge variant="destructive" className="uppercase font-bold text-xs tracking-wider">
              Admin Only
            </Badge>
          </div>
          <p className="text-muted-foreground text-sm mt-1">
            System audit trail, role assignment controls, and cache maintenance.
          </p>
        </div>

        {/* Refresh Reports Action Button */}
        <RefreshReportsButton />
      </div>

      {/* User Role Management Section */}
      <section className="space-y-4">
        <div>
          <h2 className="text-xl font-bold tracking-tight">User Role Management</h2>
          <p className="text-xs text-muted-foreground">
            Promote or demote users using <code className="text-cyan-400 font-mono">pr_set_user_role</code> (modder, curator, admin).
          </p>
        </div>
        <AdminUsersTable users={users} />
      </section>

      {/* Audit Log Table Section */}
      <section className="space-y-4 pt-4 border-t border-border">
        <div>
          <h2 className="text-xl font-bold tracking-tight">Audit Trail Ledger</h2>
          <p className="text-xs text-muted-foreground">
            Append-only record of database mutations captured by PostgreSQL row-level audit triggers.
          </p>
        </div>

        <AuditLogViewer
          logs={auditLogs}
          filters={{
            currentTable,
            currentOp,
            currentUser,
            currentFrom,
            currentTo,
          }}
          tables={tables}
          currentPage={currentPage}
          totalLogs={totalLogs}
        />
      </section>
    </main>
  );
}
