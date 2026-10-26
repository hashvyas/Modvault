import { env, pipeline } from '@huggingface/transformers';
import path from 'path';

// Configure cache directory if specified via environment variable
if (process.env.TRANSFORMERS_CACHE) {
  env.cacheDir = process.env.TRANSFORMERS_CACHE;
} else if (process.env.HF_HOME) {
  env.cacheDir = path.join(process.env.HF_HOME, 'hub');
}

// Module-level singleton pipeline promise
// ASSUMPTION: Pipeline promise is cached at module scope across calls in the server runtime.
let pipelinePromise: Promise<unknown> | null = null;

function getPipeline(): Promise<unknown> {
  if (!pipelinePromise) {
    pipelinePromise = pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
    // Do not cache a failed model load, or every later embed() fails until restart.
    pipelinePromise.catch(() => {
      pipelinePromise = null;
    });
  }
  return pipelinePromise;
}

/**
 * Generate 384-dimensional normalized mean-pooled embedding vector for the given text.
 */
export async function embed(text: string): Promise<number[]> {
  const extractor = (await getPipeline()) as (
    input: string,
    options?: Record<string, unknown>
  ) => Promise<{ data: ArrayLike<number> }>;

  const output = await extractor(text, { pooling: 'mean', normalize: true });
  return Array.from(output.data);
}

/**
 * Format a number array into pgvector literal representation [v1,v2,...]
 */
export function toPgVector(v: number[]): string {
  return `[${v.join(',')}]`;
}
