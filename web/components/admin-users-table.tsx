'use client';

import React, { useActionState } from 'react';
import { setUserRoleAction, type ActionState } from '@/app/actions/admin';
import { Badge } from '@/components/ui/badge';

export interface UserItem {
  user_id: string;
  username: string;
  email: string;
  role: 'modder' | 'curator' | 'admin';
  is_active: boolean;
  created_at: string;
}

export function AdminUsersTable({ users }: { users: UserItem[] }) {
  const [state, formAction, isPending] = useActionState<ActionState, FormData>(
    setUserRoleAction,
    {}
  );

  return (
    <div className="space-y-4">
      {state.message && (
        <div className="p-3 rounded-lg bg-emerald-500/15 text-emerald-400 border border-emerald-500/30 text-xs">
          {state.message}
        </div>
      )}

      {state.error && (
        <div className="p-3 rounded-lg bg-destructive/15 text-destructive border border-destructive/30 text-xs">
          {state.error}
        </div>
      )}

      <div className="rounded-xl border border-border overflow-x-auto bg-card/25">
        <table className="w-full text-left text-xs">
          <thead className="bg-card/70 border-b border-border text-muted-foreground uppercase tracking-wider text-[11px]">
            <tr>
              <th className="px-4 py-3">Username</th>
              <th className="px-4 py-3">Email</th>
              <th className="px-4 py-3">Status</th>
              <th className="px-4 py-3">Current Role</th>
              <th className="px-4 py-3 text-right">Assign Role (pr_set_user_role)</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border/40">
            {users.map((u) => (
              <tr key={u.user_id} className="hover:bg-card/40 transition-colors">
                <td className="px-4 py-3 font-semibold text-foreground">
                  {u.username}
                </td>
                <td className="px-4 py-3 text-muted-foreground font-mono">
                  {u.email}
                </td>
                <td className="px-4 py-3">
                  <Badge variant={u.is_active ? 'success' : 'outline'} className="text-[10px]">
                    {u.is_active ? 'Active' : 'Disabled'}
                  </Badge>
                </td>
                <td className="px-4 py-3">
                  <Badge variant="secondary" className="capitalize text-xs">
                    {u.role}
                  </Badge>
                </td>
                <td className="px-4 py-3 text-right">
                  <form action={formAction} className="inline-flex items-center gap-2">
                    <input type="hidden" name="user_id" value={u.user_id} />
                    <select
                      name="role"
                      defaultValue={u.role}
                      disabled={isPending}
                      onChange={(e) => e.target.form?.requestSubmit()}
                      className="h-7 rounded border border-border bg-card px-2 text-xs font-medium text-foreground focus:outline-none focus:ring-1 focus:ring-cyan-500"
                    >
                      <option value="modder">modder</option>
                      <option value="curator">curator</option>
                      <option value="admin">admin</option>
                    </select>
                  </form>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
