'use client';

import React, { useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Trash2 } from 'lucide-react';
import { deleteLoadoutAction } from '@/app/actions/loadouts';
import { Button } from '@/components/ui/button';

interface DeleteLoadoutButtonProps {
  loadoutId: string;
  loadoutName?: string;
  redirectTo?: string;
  label?: string;
  size?: 'default' | 'xs' | 'sm' | 'lg' | 'icon' | 'icon-xs' | 'icon-sm';
  variant?: 'destructive' | 'outline' | 'ghost' | 'secondary';
  className?: string;
  showIcon?: boolean;
}

export function DeleteLoadoutButton({
  loadoutId,
  loadoutName,
  redirectTo,
  label,
  size = 'xs',
  variant = 'ghost',
  className,
  showIcon = true,
}: DeleteLoadoutButtonProps) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();

  const handleDelete = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();

    const title = loadoutName ? ` "${loadoutName}"` : '';
    if (!window.confirm(`Are you sure you want to remove loadout${title}? This cannot be undone.`)) {
      return;
    }

    startTransition(async () => {
      const res = await deleteLoadoutAction(loadoutId);
      if (res.error) {
        alert(`Error removing loadout: ${res.error}`);
        return;
      }

      if (redirectTo) {
        router.push(redirectTo);
      } else {
        router.refresh();
      }
    });
  };

  return (
    <Button
      type="button"
      size={size}
      variant={variant}
      disabled={isPending}
      onClick={handleDelete}
      className={className}
      title={label ?? 'Remove loadout'}
      aria-label={label ?? 'Remove loadout'}
    >
      {showIcon && <Trash2 className={label ? 'mr-1' : ''} />}
      {isPending ? 'Removing...' : label}
    </Button>
  );
}
