import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import pg from 'pg';
import { env, pipeline } from '@huggingface/transformers';
// Same cache dir as web/lib/embed.ts, so CI can cache the model outside node_modules.
if (process.env.TRANSFORMERS_CACHE) env.cacheDir = process.env.TRANSFORMERS_CACHE;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');

// Load .env from repo root
dotenv.config({ path: path.join(repoRoot, '.env') });

const { Pool } = pg;

async function main() {
  const dbUrl = process.env.DATABASE_URL;
  if (!dbUrl) {
    console.error('DATABASE_URL is not set in environment or .env');
    process.exit(1);
  }

  const pool = new Pool({ connectionString: dbUrl });
  const client = await pool.connect();

  try {
    const res = await client.query<{
      mod_id: string;
      name: string;
      category: string | null;
      summary: string | null;
    }>(
      'SELECT mod_id, name, category, summary FROM mods WHERE embedding IS NULL ORDER BY name'
    );

    const modsToEmbed = res.rows;
    if (modsToEmbed.length === 0) {
      console.log('Embedded 0 mods (0 pending).');
      return;
    }

    console.log(`Found ${modsToEmbed.length} mods needing embeddings. Loading model...`);
    const extractor = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');

    console.log('Generating embeddings and updating in batches of 16 inside a transaction...');
    await client.query('BEGIN');

    const BATCH_SIZE = 16;
    let count = 0;

    for (let i = 0; i < modsToEmbed.length; i += BATCH_SIZE) {
      const batch = modsToEmbed.slice(i, i + BATCH_SIZE);
      for (const mod of batch) {
        const text = `${mod.name}. ${mod.category ?? ''}. ${mod.summary ?? ''}`;
        const output = await extractor(text, { pooling: 'mean', normalize: true });
        const vectorArray = Array.from(output.data);
        const vectorStr = `[${vectorArray.join(',')}]`;
        await client.query(
          'UPDATE mods SET embedding = $1::vector WHERE mod_id = $2',
          [vectorStr, mod.mod_id]
        );
        count++;
      }
    }

    await client.query('COMMIT');
    console.log(`Successfully embedded ${count} mods.`);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore rollback errors
    }
    console.error('Error during embedding generation:', err);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
