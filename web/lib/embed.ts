import { env, pipeline } from '@huggingface/transformers';
import path from 'path';
if (process.env.TRANSFORMERS_CACHE) {
  env.cacheDir = process.env.TRANSFORMERS_CACHE;
} else if (process.env.HF_HOME) {
  env.cacheDir = path.join(process.env.HF_HOME, 'hub');
}
let pipelinePromise: Promise<unknown> | null = null;

function getPipeline(): Promise<unknown> {
  if (!pipelinePromise) {
    pipelinePromise = pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
    pipelinePromise.catch(() => {
      pipelinePromise = null;
    });
  }
  return pipelinePromise;
}

export async function embed(text: string): Promise<number[]> {
  const extractor = (await getPipeline()) as (
    input: string,
    options?: Record<string, unknown>
  ) => Promise<{ data: ArrayLike<number> }>;

  const output = await extractor(text, { pooling: 'mean', normalize: true });
  return Array.from(output.data);
}

export function toPgVector(v: number[]): string {
  return `[${v.join(',')}]`;
}
