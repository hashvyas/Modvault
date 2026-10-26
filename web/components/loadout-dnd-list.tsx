'use client';

import React, { useState, useTransition } from 'react';
import Link from 'next/link';
import {
  DndContext,
  closestCenter,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from '@dnd-kit/core';
import {
  arrayMove,
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import {
  updateLoadoutOrderAction,
  toggleModEnabledAction,
  switchModVersionAction,
  removeModFromLoadoutAction,
} from '@/app/actions/loadouts';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';

export interface ModVersionOption {
  version_id: string;
  semver: string;
  is_primary: boolean;
}

export interface LoadoutModItem {
  id: string;
  version_id: string;
  mod_id: string;
  mod_name: string;
  current_semver: string;
  position: number;
  enabled: boolean;
  available_versions: ModVersionOption[];
}

interface Props {
  loadoutId: string;
  initialMods: LoadoutModItem[];
  isOwner: boolean;
}

function SortableModRow({
  item,
  index,
  isOwner,
  onToggleEnabled,
  onSwitchVersion,
  onRemove,
}: {
  item: LoadoutModItem;
  index: number;
  isOwner: boolean;
  onToggleEnabled: (versionId: string, enabled: boolean) => void;
  onSwitchVersion: (oldVersionId: string, newVersionId: string) => void;
  onRemove: (versionId: string) => void;
}) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: item.version_id, disabled: !isOwner });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`p-3.5 rounded-xl border transition-all flex items-center justify-between gap-3 ${
        item.enabled
          ? 'bg-card/60 border-border hover:border-border/80'
          : 'bg-card/20 border-border/40 opacity-60'
      } ${isDragging ? 'border-cyan-500 shadow-xl z-10' : ''}`}
    >
      <div className="flex items-center gap-3 overflow-hidden flex-1">
        {/* Drag handle */}
        {isOwner && (
          <button
            type="button"
            {...attributes}
            {...listeners}
            className="cursor-grab active:cursor-grabbing p-1 text-muted-foreground hover:text-foreground touch-none select-none"
            title="Drag to reorder"
          >
            <span className="text-sm font-mono font-bold select-none">⋮⋮</span>
          </button>
        )}

        {/* Position badge */}
        <span className="w-6 text-center text-xs font-mono font-bold text-muted-foreground shrink-0">
          #{index + 1}
        </span>

        {/* Mod Info */}
        <div className="flex flex-col min-w-0">
          <Link
            href={`/mods/${item.mod_id}`}
            className="text-sm font-semibold text-foreground hover:text-cyan-400 transition-colors truncate"
          >
            {item.mod_name}
          </Link>
          <div className="flex items-center gap-2 mt-0.5">
            {!item.enabled && (
              <Badge variant="secondary" className="text-[10px] py-0 px-1.5">
                Disabled
              </Badge>
            )}
          </div>
        </div>
      </div>

      {/* Version selector, Enabled toggle, and Remove button */}
      <div className="flex items-center gap-2 shrink-0">
        {isOwner && item.available_versions.length > 1 ? (
          <select
            value={item.version_id}
            onChange={(e) => onSwitchVersion(item.version_id, e.target.value)}
            className="h-8 rounded border border-border bg-card px-2 text-xs font-mono text-foreground focus:outline-none focus:ring-1 focus:ring-cyan-500"
          >
            {item.available_versions.map((v) => (
              <option key={v.version_id} value={v.version_id}>
                v{v.semver} {v.is_primary ? '(primary)' : ''}
              </option>
            ))}
          </select>
        ) : (
          <span className="text-xs font-mono text-muted-foreground px-2">
            v{item.current_semver}
          </span>
        )}

        {isOwner && (
          <>
            <Button
              type="button"
              size="xs"
              variant={item.enabled ? 'outline' : 'secondary'}
              onClick={() => onToggleEnabled(item.version_id, !item.enabled)}
              className="text-[11px]"
            >
              {item.enabled ? 'Disable' : 'Enable'}
            </Button>

            <Button
              type="button"
              size="xs"
              variant="destructive"
              onClick={() => onRemove(item.version_id)}
              className="text-[11px]"
            >
              &times;
            </Button>
          </>
        )}
      </div>
    </div>
  );
}

export function LoadoutModList({ loadoutId, initialMods, isOwner }: Props) {
  const [mods, setMods] = useState<LoadoutModItem[]>(initialMods);
  const [isPending, startTransition] = useTransition();

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates })
  );

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    const oldIndex = mods.findIndex((m) => m.version_id === active.id);
    const newIndex = mods.findIndex((m) => m.version_id === over.id);

    if (oldIndex !== -1 && newIndex !== -1) {
      const newItems = arrayMove(mods, oldIndex, newIndex);
      setMods(newItems);

      startTransition(async () => {
        const orderedVersionIds = newItems.map((m) => m.version_id);
        await updateLoadoutOrderAction(loadoutId, orderedVersionIds);
      });
    }
  };

  const handleToggleEnabled = (versionId: string, enabled: boolean) => {
    setMods((prev) =>
      prev.map((m) => (m.version_id === versionId ? { ...m, enabled } : m))
    );
    startTransition(async () => {
      await toggleModEnabledAction(loadoutId, versionId, enabled);
    });
  };

  const handleSwitchVersion = (oldVersionId: string, newVersionId: string) => {
    setMods((prev) =>
      prev.map((m) => {
        if (m.version_id === oldVersionId) {
          const newVer = m.available_versions.find((v) => v.version_id === newVersionId);
          return {
            ...m,
            version_id: newVersionId,
            current_semver: newVer?.semver ?? m.current_semver,
          };
        }
        return m;
      })
    );
    startTransition(async () => {
      await switchModVersionAction(loadoutId, oldVersionId, newVersionId);
    });
  };

  const handleRemove = (versionId: string) => {
    setMods((prev) => prev.filter((m) => m.version_id !== versionId));
    startTransition(async () => {
      await removeModFromLoadoutAction(loadoutId, versionId);
    });
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-bold tracking-tight">Active Load Order</h2>
          <p className="text-xs text-muted-foreground">
            {isOwner
              ? 'Drag handle to reorder mods. Changes are saved automatically.'
              : 'Read-only view of load order.'}
          </p>
        </div>
        {isPending && (
          <span className="text-xs text-cyan-400 animate-pulse">Saving...</span>
        )}
      </div>

      {mods.length === 0 ? (
        <div className="p-8 rounded-xl border border-dashed border-border text-center text-muted-foreground text-sm">
          No mods added to this loadout yet.
        </div>
      ) : (
        <DndContext
          sensors={sensors}
          collisionDetection={closestCenter}
          onDragEnd={handleDragEnd}
        >
          <SortableContext
            items={mods.map((m) => m.version_id)}
            strategy={verticalListSortingStrategy}
          >
            <div className="space-y-2">
              {mods.map((item, index) => (
                <SortableModRow
                  key={item.id}
                  item={item}
                  index={index}
                  isOwner={isOwner}
                  onToggleEnabled={handleToggleEnabled}
                  onSwitchVersion={handleSwitchVersion}
                  onRemove={handleRemove}
                />
              ))}
            </div>
          </SortableContext>
        </DndContext>
      )}
    </div>
  );
}
