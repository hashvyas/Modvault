import { env, pipeline } from '@huggingface/transformers';

const cacheDir = process.env.TRANSFORMERS_CACHE || '/app/.cache';
env.cacheDir = cacheDir;

console.log(`Pre-downloading Xenova/all-MiniLM-L6-v2 embedding model into ${cacheDir}...`);
await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
console.log('Model pre-download complete.');
