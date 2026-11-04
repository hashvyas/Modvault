import { test, expect, type Page } from '@playwright/test';
import * as path from 'path';
import * as fs from 'fs';
import { Client } from 'pg';
const screenshotsDir = path.resolve(process.cwd(), '../docs/screenshots');
if (!fs.existsSync(screenshotsDir)) {
  fs.mkdirSync(screenshotsDir, { recursive: true });
}
try {
  process.loadEnvFile(path.resolve(process.cwd(), '../.env'));
} catch {
}
const OWNER_URL =
  process.env.DATABASE_URL ?? 'postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? '';
const CURATOR_PASSWORD = process.env.CURATOR_PASSWORD ?? '';
const VIEWER = { username: 'e2e_viewer', password: `e2e-${Date.now()}-${Math.random().toString(36).slice(2)}` };

const BROKEN_SKYRIM_UI = '91e9a578-4e52-5004-b8f0-1bbb92fb39c7';
const PRIVATE_LOADOUT_NAME = 'Curator Private Vault';
const PAIR_MODS = ['MCM Helper', 'Better Dialogue Controls'];
function healthPanel(page: Page) {
  return page.locator('div.rounded-2xl', {
    has: page.getByRole('heading', { name: 'Loadout Health Diagnostic' }),
  });
}
async function loginAs(page: Page, username: string, password: string) {
  await page.goto('/login');
  const signOutBtn = page.locator('button:has-text("Sign Out")');
  if (await signOutBtn.isVisible()) {
    await signOutBtn.click();
    await page.waitForURL((url) => url.pathname.includes('/login'));
  }
  await page.fill('input[name="username"]', username);
  await page.fill('input[name="password"]', password);
  await page.locator('form').filter({ hasText: 'Sign In' }).locator('button[type="submit"]').click();
  await page.waitForURL((url) => !url.pathname.includes('/login'));
}

test.describe.serial('ModVault Demo Script (E2E Steps 1 to 6)', () => {
  let createdPrivateLoadoutUrl = '';
  type Snapshot = {
    rows: { version_id: string; position: number; enabled: boolean }[];
    pair: {
      a: string;
      b: string;
      row: { status: string; conflict_detail: unknown; verified_by: string | null } | null;
    };
  };
  let snapshot: Snapshot | null = null;

  test.beforeAll(async () => {
    const db = new Client({ connectionString: OWNER_URL });
    await db.connect();
    try {
      const rows = await db.query(
        'SELECT version_id, position, enabled FROM loadout_mods WHERE loadout_id = $1',
        [BROKEN_SKYRIM_UI]
      );
      const ids = await db.query<{ version_id: string }>(
        `SELECT v.version_id FROM mod_versions v JOIN mods m ON m.mod_id = v.mod_id
         WHERE v.is_primary AND m.name = ANY($1::text[]) ORDER BY v.version_id`,
        [PAIR_MODS]
      );
      const [a, b] = ids.rows.map((r) => r.version_id);
      const pair = await db.query(
        'SELECT status, conflict_detail, verified_by FROM compatibility_matrix WHERE version_a_id = $1 AND version_b_id = $2',
        [a, b]
      );
      snapshot = { rows: rows.rows, pair: { a, b, row: pair.rows[0] ?? null } };
      await db.query('DELETE FROM users WHERE username = $1', [VIEWER.username]);
      await db.query('SELECT fn_register_user($1, $2, $3)', [
        VIEWER.username,
        `${VIEWER.username}@example.com`,
        VIEWER.password,
      ]);
    } finally {
      await db.end();
    }
  });

  test.afterAll(async () => {
    const db = new Client({ connectionString: OWNER_URL });
    await db.connect();
    try {
      await db.query('BEGIN');
      await db.query('DELETE FROM loadouts WHERE name = $1', [PRIVATE_LOADOUT_NAME]);
      await db.query('DELETE FROM users WHERE username = $1', [VIEWER.username]);
      if (snapshot) {
        await db.query(
          'DELETE FROM loadout_mods WHERE loadout_id = $1 AND NOT (version_id = ANY($2::uuid[]))',
          [BROKEN_SKYRIM_UI, snapshot.rows.map((r) => r.version_id)]
        );
        await db.query(
          `UPDATE loadout_mods x SET position = s.position, enabled = s.enabled
           FROM jsonb_to_recordset($2::jsonb) AS s(version_id uuid, position int, enabled boolean)
           WHERE x.loadout_id = $1 AND x.version_id = s.version_id`,
          [BROKEN_SKYRIM_UI, JSON.stringify(snapshot.rows)]
        );
        const { a, b, row } = snapshot.pair;
        if (row) {
          await db.query(
            `UPDATE compatibility_matrix SET status = $3, conflict_detail = $4::jsonb, verified_by = $5
             WHERE version_a_id = $1 AND version_b_id = $2`,
            [a, b, row.status, row.conflict_detail === null ? null : JSON.stringify(row.conflict_detail), row.verified_by]
          );
        } else {
          await db.query('DELETE FROM compatibility_matrix WHERE version_a_id = $1 AND version_b_id = $2', [a, b]);
        }
      }
      await db.query('COMMIT');
    } catch (err) {
      await db.query('ROLLBACK');
      throw err;
    } finally {
      await db.end();
    }
  });

  test('Step 1: Hybrid Search with Semantic Meaning Badge', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveTitle(/ModVault/i);
    const searchInput = page.locator('input[name="q"]');
    await searchInput.fill('make the menus look better');
    await searchInput.press('Enter');
    await page.waitForURL((url) => url.pathname.includes('/search'));
    await expect(page.locator('h1')).toContainText('Hybrid Mod Discovery');
    await expect(page.locator('text=Found').first()).toBeVisible();
    const meaningBadge = page.locator('text=Meaning #').first();
    await expect(meaningBadge).toBeVisible();
    await page.screenshot({ path: path.join(screenshotsDir, '01-search-meaning.png') });
  });

  test('Step 2: Open Broken Skyrim Loadout and Verify Diagnostics', async ({ page }) => {
    await loginAs(page, 'curator', CURATOR_PASSWORD);
    await page.goto('/loadouts');
    await expect(page.locator('h1')).toContainText('Loadout Manager');
    const brokenLoadoutLink = page.locator('a:has-text("Broken Skyrim UI")').first();
    await expect(brokenLoadoutLink).toBeVisible();
    await brokenLoadoutLink.click();
    await page.waitForURL((url) => url.pathname.includes('/loadouts/'));
    await expect(page.locator('h1')).toContainText('Broken Skyrim UI');
    const panel = healthPanel(page);
    await expect(panel.getByText('broken', { exact: true })).toBeVisible();
    await expect(panel.getByText('65', { exact: true })).toBeVisible();

    const errorsSection = page.getByRole('heading', { name: /Errors/i }).first();
    await expect(errorsSection).toBeVisible();

    const missingDep = page.locator('text=MISSING_DEPENDENCY').first();
    await expect(missingDep).toBeVisible();
    await page.screenshot({ path: path.join(screenshotsDir, '02-broken-loadout.png') });
  });

  test('Step 3: Add Missing Dependency and Auto-sort Load Order', async ({ page }) => {
    await loginAs(page, 'curator', CURATOR_PASSWORD);
    await page.goto(`/loadouts/${BROKEN_SKYRIM_UI}`);
    await expect(page.locator('h1')).toContainText('Broken Skyrim UI');
    const addDepButton = page.getByRole('button', { name: 'Add SkyUI' });
    await expect(addDepButton).toBeVisible();
    await addDepButton.click();
    await page.waitForTimeout(2000);
    const autoSortButton = page.locator('button:has-text("Auto-sort Load Order"), button:has-text("Auto-sort")').first();
    await expect(autoSortButton).toBeVisible();
    await autoSortButton.click();
    await page.waitForTimeout(2000);
    await page.reload();
    await expect(page.locator('text=MISSING_DEPENDENCY')).not.toBeVisible();
    await expect(page.locator('text=LOAD_ORDER')).not.toBeVisible();
    const panel = healthPanel(page);
    await expect(panel.getByText('healthy', { exact: true })).toBeVisible();
    await expect(panel.getByText('100', { exact: true })).toBeVisible();
    await page.screenshot({ path: path.join(screenshotsDir, '03-fixed-loadout.png') });
  });

  test('Step 4: Curator Marks Pair Incompatible on Matrix, Flipping Loadout to Broken', async ({ page }) => {
    await loginAs(page, 'curator', CURATOR_PASSWORD);
    await page.goto('/games/skyrimspecialedition/compat');
    await expect(page.locator('h1')).toContainText('Compatibility Heatmap');
    const cellButton = page.locator(
      'button[title*="MCM Helper"][title*="Better Dialogue Controls"]'
    ).first();
    await expect(cellButton).toBeVisible();
    await cellButton.click();
    const modal = page.locator('text=Record Pairwise Compatibility');
    await expect(modal).toBeVisible();

    await page.selectOption('select[name="status"]', 'incompatible');
    await page.fill('input[name="reason"]', 'E2E test: Curator verified mesh conflict');

    await page.click('button[type="submit"]:has-text("Save Assessment")');
    await expect(page.locator('text=Compatibility assessment saved successfully!')).toBeVisible();
    await page.click('button:has-text("Cancel")');
    await page.goto(`/loadouts/${BROKEN_SKYRIM_UI}`);
    await expect(page.locator('h1')).toContainText('Broken Skyrim UI');
    await expect(healthPanel(page).getByText('broken', { exact: true })).toBeVisible();
    await expect(page.locator('text=INCOMPATIBLE_PAIR').first()).toBeVisible();
    await page.screenshot({ path: path.join(screenshotsDir, '04-curator-heatmap.png') });
  });

  test('Step 5: Admin Inspects Audit Log and Views Side-by-Side Diff', async ({ page }) => {
    await loginAs(page, 'admin', ADMIN_PASSWORD);
    await page.goto('/admin');
    await expect(page.locator('h1')).toContainText('System Administration');
    const curatorEntry = page.locator('tr:has-text("compatibility_matrix"):has-text("curator")').first();
    await expect(curatorEntry).toBeVisible();
    const viewDiffButton = curatorEntry.locator('button:has-text("View Diff")');
    await viewDiffButton.click();
    const diffModal = page.locator('text=Audit Entry #').first();
    await expect(diffModal).toBeVisible();
    await expect(page.locator('text=Changed by curator').first()).toBeVisible();
    await expect(page.locator('text=MODIFIED').first()).toBeVisible();
    await page.screenshot({ path: path.join(screenshotsDir, '05-admin-audit-diff.png') });
    await page.click('button:has-text("Close Diff")');
  });

  test('Step 6: Another User Cannot View Curator Private Loadout (RLS Enforcement)', async ({ page }) => {
    await loginAs(page, 'curator', CURATOR_PASSWORD);
    await page.goto('/loadouts');
    await page.fill('input[name="name"]', PRIVATE_LOADOUT_NAME);
    const gameSelect = page.locator('select[name="game_id"]');
    await gameSelect.selectOption({ label: 'Skyrim Special Edition' });

    await page.fill('input[name="game_version"]', '1.6.1170');
    await page.fill('textarea[name="description"]', 'Private loadout owned exclusively by curator');
    const isPublicCheckbox = page.locator('input[name="is_public"]');
    if (await isPublicCheckbox.isChecked()) {
      await isPublicCheckbox.uncheck();
    }

    await page.click('button:has-text("Create Loadout")');
    await page.waitForURL((url) => url.pathname.includes('/loadouts/'));
    createdPrivateLoadoutUrl = page.url();
    expect(createdPrivateLoadoutUrl).toContain('/loadouts/');
    await expect(page.locator('h1')).toContainText(PRIVATE_LOADOUT_NAME);
    await loginAs(page, VIEWER.username, VIEWER.password);
    await page.goto('/loadouts');
    await expect(page.locator(`text=${PRIVATE_LOADOUT_NAME}`)).not.toBeVisible();
    await page.goto(createdPrivateLoadoutUrl);
    await expect(page.getByRole('heading', { name: '404' })).toBeVisible();
    await page.screenshot({ path: path.join(screenshotsDir, '06-private-loadout-hidden.png') });
  });

  test('Capture Additional UI Screenshots for Deploy Documentation', async ({ page }) => {
    await page.goto('/');
    await page.screenshot({ path: path.join(screenshotsDir, 'home.png') });
    await page.goto('/games/skyrimspecialedition');
    await page.screenshot({ path: path.join(screenshotsDir, 'game-skyrim.png') });
    await page.goto('/mods/cc9c9ffc-c0f9-5d62-a337-f99c63cda42a');
    await expect(page.locator('h1')).toBeVisible();
    await page.screenshot({ path: path.join(screenshotsDir, 'mod-detail.png') });
    await loginAs(page, 'curator', CURATOR_PASSWORD);
    await page.goto('/mods/new');
    await page.screenshot({ path: path.join(screenshotsDir, 'mod-publish.png') });
    await page.goto('/loadouts');
    await page.screenshot({ path: path.join(screenshotsDir, 'loadouts.png') });
    await loginAs(page, 'admin', ADMIN_PASSWORD);
    await page.goto('/admin');
    await page.screenshot({ path: path.join(screenshotsDir, 'admin.png') });
  });
});
