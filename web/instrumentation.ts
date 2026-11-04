
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    const { embed } = await import('@/lib/embed');
    embed('warmup').catch((e) => console.error('Embedding warmup failed:', e));
  }
}
