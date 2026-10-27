const tone = {
  healthy: 'text-emerald-400',
  warnings: 'text-amber-400',
  broken: 'text-rose-400',
} as const;

// Thin arc gauge: the arc carries the value, the number stays quiet.
export function ScoreMeter({
  score,
  status,
  size = 72,
}: {
  score: number;
  status: string;
  size?: number;
}) {
  const stroke = Math.max(2, size / 24);
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const pct = Math.min(100, Math.max(0, score));
  const color = tone[status as keyof typeof tone] ?? tone.healthy;

  return (
    <div
      className={`relative shrink-0 ${color}`}
      style={{ width: size, height: size }}
      role="img"
      aria-label={`Health score ${pct} out of 100`}
    >
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="currentColor" strokeOpacity={0.12} strokeWidth={stroke} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke="currentColor"
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={c * (1 - pct / 100)}
        />
      </svg>
      <span
        className="absolute inset-0 flex items-center justify-center font-light tabular-nums text-foreground"
        style={{ fontSize: size * 0.34 }}
      >
        {pct}
      </span>
    </div>
  );
}
