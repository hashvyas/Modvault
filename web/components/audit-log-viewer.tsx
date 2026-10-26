'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';

export interface AuditLogRow {
  audit_id: string;
  table_name: string;
  operation: 'I' | 'U' | 'D';
  row_pk: string | null;
  old_row: Record<string, unknown> | null;
  new_row: Record<string, unknown> | null;
  changed_by_username: string | null;
  changed_at: string;
}

interface FilterProps {
  currentTable: string;
  currentOp: string;
  currentUser: string;
  currentFrom: string;
  currentTo: string;
}

interface Props {
  logs: AuditLogRow[];
  filters: FilterProps;
  tables: string[];
  currentPage: number;
  totalLogs: number;
}

export function AuditLogViewer({
  logs,
  filters,
  tables,
  currentPage,
  totalLogs,
}: Props) {
  const [activeDiff, setActiveDiff] = useState<AuditLogRow | null>(null);

  const PAGE_SIZE = 50;
  const totalPages = Math.ceil(totalLogs / PAGE_SIZE);

  // Compute keys changed between old_row and new_row
  const getChangedKeys = (oldRow: Record<string, unknown> | null, newRow: Record<string, unknown> | null) => {
    const keys = new Set<string>([
      ...Object.keys(oldRow || {}),
      ...Object.keys(newRow || {}),
    ]);
    const changed = new Set<string>();
    keys.forEach((key) => {
      const vOld = oldRow ? JSON.stringify(oldRow[key]) : undefined;
      const vNew = newRow ? JSON.stringify(newRow[key]) : undefined;
      if (vOld !== vNew) {
        changed.add(key);
      }
    });
    return { allKeys: Array.from(keys), changedKeys: changed };
  };

  return (
    <div className="space-y-6">
      {/* Filters Bar */}
      <form
        method="GET"
        className="grid gap-3 sm:grid-cols-2 md:grid-cols-5 p-4 rounded-xl border border-border bg-card/40 text-xs"
      >
        <div className="space-y-1">
          <label className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">
            Table
          </label>
          <select
            name="table"
            defaultValue={filters.currentTable}
            className="w-full h-8 rounded border border-border bg-card px-2 text-xs text-foreground focus:outline-none focus:ring-1 focus:ring-cyan-500"
          >
            <option value="">All Tables</option>
            {tables.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1">
          <label className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">
            Operation
          </label>
          <select
            name="op"
            defaultValue={filters.currentOp}
            className="w-full h-8 rounded border border-border bg-card px-2 text-xs text-foreground focus:outline-none focus:ring-1 focus:ring-cyan-500"
          >
            <option value="">All Operations</option>
            <option value="I">Insert (I)</option>
            <option value="U">Update (U)</option>
            <option value="D">Delete (D)</option>
          </select>
        </div>

        <div className="space-y-1">
          <label className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">
            User
          </label>
          <input
            name="user"
            defaultValue={filters.currentUser}
            placeholder="Username..."
            className="w-full h-8 rounded border border-border bg-card px-2 text-xs text-foreground focus:outline-none focus:ring-1 focus:ring-cyan-500"
          />
        </div>

        <div className="space-y-1">
          <label className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">
            Date From
          </label>
          <input
            name="from"
            type="date"
            defaultValue={filters.currentFrom}
            className="w-full h-8 rounded border border-border bg-card px-2 text-xs text-foreground focus:outline-none focus:ring-1 focus:ring-cyan-500"
          />
        </div>

        <div className="flex items-end gap-2">
          <Button
            type="submit"
            size="sm"
            className="flex-1 bg-cyan-600 hover:bg-cyan-500 text-white font-medium text-xs h-8"
          >
            Filter
          </Button>
          {(filters.currentTable || filters.currentOp || filters.currentUser || filters.currentFrom) && (
            <Link href="/admin">
              <Button type="button" variant="ghost" size="sm" className="text-xs h-8">
                Reset
              </Button>
            </Link>
          )}
        </div>
      </form>

      {/* Audit Log Results Table */}
      <div className="rounded-xl border border-border overflow-hidden bg-card/25">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="bg-card/70 border-b border-border text-muted-foreground uppercase tracking-wider text-[11px]">
              <tr>
                <th className="px-4 py-3">Audit ID</th>
                <th className="px-4 py-3">Table</th>
                <th className="px-4 py-3">Op</th>
                <th className="px-4 py-3">Target PK</th>
                <th className="px-4 py-3">User</th>
                <th className="px-4 py-3">Timestamp</th>
                <th className="px-4 py-3 text-right">Row Diff</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border/40 font-mono text-[11px]">
              {logs.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-8 text-center text-muted-foreground font-sans text-xs">
                    No audit records match the selected filter criteria.
                  </td>
                </tr>
              ) : (
                logs.map((log) => {
                  let opBadgeVariant: 'success' | 'warning' | 'destructive' = 'success';
                  if (log.operation === 'U') opBadgeVariant = 'warning';
                  else if (log.operation === 'D') opBadgeVariant = 'destructive';

                  return (
                    <tr key={log.audit_id} className="hover:bg-card/40 transition-colors">
                      <td className="px-4 py-2.5 text-muted-foreground font-semibold">
                        #{log.audit_id}
                      </td>
                      <td className="px-4 py-2.5 font-bold font-sans text-foreground">
                        {log.table_name}
                      </td>
                      <td className="px-4 py-2.5">
                        <Badge variant={opBadgeVariant} className="text-[10px] uppercase font-bold">
                          {log.operation}
                        </Badge>
                      </td>
                      <td className="px-4 py-2.5 text-muted-foreground truncate max-w-[140px]" title={log.row_pk ?? ''}>
                        {log.row_pk ? log.row_pk.substring(0, 8) + '...' : '—'}
                      </td>
                      <td className="px-4 py-2.5 font-sans">
                        {log.changed_by_username ? (
                          <span className="font-semibold text-cyan-300">{log.changed_by_username}</span>
                        ) : (
                          <span className="text-muted-foreground italic">System / Seeder</span>
                        )}
                      </td>
                      <td className="px-4 py-2.5 text-muted-foreground">
                        {new Date(log.changed_at).toLocaleString()}
                      </td>
                      <td className="px-4 py-2.5 text-right font-sans">
                        <Button
                          type="button"
                          size="xs"
                          variant="outline"
                          onClick={() => setActiveDiff(log)}
                          className="text-[11px]"
                        >
                          View Diff
                        </Button>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Pagination Controls */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between text-xs pt-2">
          <span className="text-muted-foreground">
            Showing page <strong className="text-foreground">{currentPage}</strong> of <strong>{totalPages}</strong> ({totalLogs} audit records)
          </span>

          <div className="flex items-center gap-2">
            {currentPage > 1 && (
              <Link
                href={`/admin?page=${currentPage - 1}&table=${filters.currentTable}&op=${filters.currentOp}&user=${filters.currentUser}&from=${filters.currentFrom}`}
              >
                <Button size="xs" variant="outline">&larr; Previous</Button>
              </Link>
            )}

            {currentPage < totalPages && (
              <Link
                href={`/admin?page=${currentPage + 1}&table=${filters.currentTable}&op=${filters.currentOp}&user=${filters.currentUser}&from=${filters.currentFrom}`}
              >
                <Button size="xs" variant="outline">Next &rarr;</Button>
              </Link>
            )}
          </div>
        </div>
      )}

      {/* Side-by-Side Diff Modal Dialog */}
      {activeDiff && (
        <div className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-card border border-border rounded-2xl p-6 max-w-4xl w-full max-h-[90vh] flex flex-col space-y-4 shadow-2xl">
            <div className="flex items-center justify-between border-b border-border pb-3">
              <div>
                <h3 className="text-base font-bold flex items-center gap-2">
                  <span>Audit Entry #{activeDiff.audit_id}</span>
                  <Badge variant="outline" className="text-xs">{activeDiff.table_name}</Badge>
                  <Badge variant={activeDiff.operation === 'I' ? 'success' : activeDiff.operation === 'U' ? 'warning' : 'destructive'} className="text-xs">
                    Operation: {activeDiff.operation}
                  </Badge>
                </h3>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Changed by <strong className="text-foreground">{activeDiff.changed_by_username ?? 'System'}</strong> on {new Date(activeDiff.changed_at).toLocaleString()}
                </p>
              </div>
              <Button
                variant="ghost"
                size="xs"
                onClick={() => setActiveDiff(null)}
              >
                &times;
              </Button>
            </div>

            {/* Side-by-Side Comparison */}
            <div className="overflow-y-auto flex-1 space-y-3">
              {(() => {
                const { allKeys, changedKeys } = getChangedKeys(activeDiff.old_row, activeDiff.new_row);

                if (allKeys.length === 0) {
                  return <div className="text-xs text-muted-foreground p-4">No row data recorded.</div>;
                }

                return (
                  <div className="border border-border rounded-xl overflow-hidden font-mono text-xs">
                    <div className="grid grid-cols-12 bg-card/70 border-b border-border font-sans font-semibold p-2.5 text-[11px] text-muted-foreground">
                      <div className="col-span-3">Field</div>
                      <div className="col-span-4">Old Row Value</div>
                      <div className="col-span-5">New Row Value</div>
                    </div>

                    <div className="divide-y divide-border/40">
                      {allKeys.sort().map((key) => {
                        const isChanged = changedKeys.has(key);
                        const oldVal = activeDiff.old_row ? JSON.stringify(activeDiff.old_row[key]) : '—';
                        const newVal = activeDiff.new_row ? JSON.stringify(activeDiff.new_row[key]) : '—';

                        return (
                          <div
                            key={key}
                            className={`grid grid-cols-12 p-2.5 items-center transition-colors ${
                              isChanged
                                ? 'bg-amber-500/10 border-l-2 border-l-amber-500'
                                : 'hover:bg-muted/10'
                            }`}
                          >
                            <div className="col-span-3 font-semibold text-foreground truncate pr-2" title={key}>
                              {key}
                              {isChanged && (
                                <span className="ml-1.5 text-[9px] font-sans px-1 py-0.2 rounded bg-amber-500/20 text-amber-300">
                                  MODIFIED
                                </span>
                              )}
                            </div>
                            <div className="col-span-4 text-muted-foreground break-all pr-2 font-mono text-[11px]">
                              {oldVal}
                            </div>
                            <div className="col-span-5 text-foreground break-all font-mono text-[11px]">
                              {newVal}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                );
              })()}
            </div>

            <div className="flex justify-end pt-2 border-t border-border">
              <Button size="sm" variant="outline" onClick={() => setActiveDiff(null)}>
                Close Diff
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
