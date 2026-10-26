import { test, expect, type Page } from '@playwright/test';
import * as path from 'path';
import * as fs from 'fs';
import { Client } from 'pg';

// Helper to ensure docs/screenshots directory exists
const screenshotsDir = path.resolve(process.cwd(), '../docs/screenshots');
if (!fs.existsSync(screenshotsDir)) {
  fs.mkdirSync(screenshotsDir, { recursive: true });
}

// Owner connection for cleanup. CI exports DATABASE_URL; locally it comes from the repo-root .env.
try {
  process.loadEnvFile(path.resolve(process.cwd(), '../.env'));
} catch {
  // No .env file (CI): rely on the environment.
}
const OWNER_URL =
  process.env.DATABASE_URL ?? 'postgresql://modvault_owner:modvault_owner_dev@localhost:5432/modvault';

const BROKEN_SKYRIM_UI = '74867771-c761-5ed8-9468-8358f8cad4f8';
const PRIVATE_LOADOUT_NAME = 'Modder1 Private Vault';
// Step 4 marks this pair incompatible. MCM Helper is only in Broken Skyrim UI, so no other seeded loadout changes.
const PAIR_MODS = ['MCM Helper', 'Better Dialogue Controls'];

// The health panel card, so status and score checks do not match the "Broken Skyrim UI" heading.
function healthPanel(page: Page) {
  return page.locator('div.rounded-2xl', {
    has: page.getByRole('heading', { name: 'Loadout Health Diagnostic' }),
  });
}

// Reusable login helper that handles existing sessions cleanly
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

  // ASSUMPTION: "delete what it creates" also means putting back what it changes (the Broken Skyrim UI
  // rows from step 3 and the matrix pair from step 4), so the seed stays intact and the suite can rerun
  // without a reset. Audit rows stay: audit_log is append-only.
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
    // Navigate to homepage
    await page.goto('/');
    await expect(page).toHaveTitle(/ModVault/i);

    // Search for "make the menus look better"
    const searchInput = page.locator('input[name="q"]');
    await searchInput.fill('make the menus look better');
    await searchInput.press('Enter');

    // Wait for the search results page to load
    await page.waitForURL((url) => url.pathname.includes('/search'));
    await expect(page.locator('h1')).toContainText('Hybrid Mod Discovery');

    // Verify search results header renders
    await expect(page.locator('text=Found').first()).toBeVisible();

    // Verify semantic meaning badge appears on top matching mod (e.g. RaceMenu)
    const meaningBadge = page.locator('text=Meaning #').first();
    await expect(meaningBadge).toBeVisible();

    // Save screenshot
    await page.screenshot({ path: path.join(screenshotsDir, '01-search-meaning.png') });
  });

  test('Step 2: Open Broken Skyrim Loadout and Verify Diagnostics', async ({ page }) => {
    // 1. Log in as modder1
    await loginAs(page, 'modder1', 'modder1-demo-123');

    // 2. Navigate to loadouts manager
    await page.goto('/loadouts');
    await expect(page.locator('h1')).toContainText('Loadout Manager');

    // 3. Find and open "Broken Skyrim UI"
    const brokenLoadoutLink = page.locator('a:has-text("Broken Skyrim UI")').first();
    await expect(brokenLoadoutLink).toBeVisible();
    await brokenLoadoutLink.click();

    // Wait for loadout builder page
    await page.waitForURL((url) => url.pathname.includes('/loadouts/'));
    await expect(page.locator('h1')).toContainText('Broken Skyrim UI');

    // 4. Verify score, broken status badge, and diagnostic errors.
    // Seed: MISSING_DEPENDENCY (SkyUI) + LOAD_ORDER = 100 - 25 - 10 = 65.
    const panel = healthPanel(page);
    await expect(panel.getByText('broken', { exact: true })).toBeVisible();
    await expect(panel.getByText('65', { exact: true })).toBeVisible();

    const errorsSection = page.getByRole('heading', { name: /Errors/i }).first();
    await expect(errorsSection).toBeVisible();

    const missingDep = page.locator('text=MISSING_DEPENDENCY').first();
    await expect(missingDep).toBeVisible();

    // Save screenshot
    await page.screenshot({ path: path.join(screenshotsDir, '02-broken-loadout.png') });
  });

  test('Step 3: Add Missing Dependency and Auto-sort Load Order', async ({ page }) => {
    // Log in as modder1 if session is not preserved
    await loginAs(page, 'modder1', 'modder1-demo-123');

    // Open Broken Skyrim UI
    await page.goto('/loadouts/74867771-c761-5ed8-9468-8358f8cad4f8');
    await expect(page.locator('h1')).toContainText('Broken Skyrim UI');

    // Click "Add SkyUI" to resolve missing dependency
    const addDepButton = page.getByRole('button', { name: 'Add SkyUI' });
    await expect(addDepButton).toBeVisible();
    await addDepButton.click();

    // Wait for update transition or status message
    await page.waitForTimeout(2000);

    // Click "Auto-sort Load Order"
    const autoSortButton = page.locator('button:has-text("Auto-sort Load Order"), button:has-text("Auto-sort")').first();
    await expect(autoSortButton).toBeVisible();
    await autoSortButton.click();

    // Wait for sorting to apply
    await page.waitForTimeout(2000);
    await page.reload();

    // Both fixable issues are gone: healthy, score 100
    await expect(page.locator('text=MISSING_DEPENDENCY')).not.toBeVisible();
    await expect(page.locator('text=LOAD_ORDER')).not.toBeVisible();
    const panel = healthPanel(page);
    await expect(panel.getByText('healthy', { exact: true })).toBeVisible();
    await expect(panel.getByText('100', { exact: true })).toBeVisible();

    // Save screenshot
    await page.screenshot({ path: path.join(screenshotsDir, '03-fixed-loadout.png') });
  });

  test('Step 4: Curator Marks Pair Incompatible on Matrix, Flipping Loadout to Broken', async ({ page }) => {
    // 1. Log in as curator
    await loginAs(page, 'curator', 'curator-demo-123');

    // 2. Navigate to Skyrim SE Compatibility Heatmap
    await page.goto('/games/skyrimspecialedition/compat');
    await expect(page.locator('h1')).toContainText('Compatibility Heatmap');

    // 3. Select a pair inside Broken Skyrim UI: MCM Helper and Better Dialogue Controls
    const cellButton = page.locator(
      'button[title*="MCM Helper"][title*="Better Dialogue Controls"]'
    ).first();
    await expect(cellButton).toBeVisible();
    await cellButton.click();

    // 4. In the modal, select status "incompatible" and fill reason
    const modal = page.locator('text=Record Pairwise Compatibility');
    await expect(modal).toBeVisible();

    await page.selectOption('select[name="status"]', 'incompatible');
    await page.fill('input[name="reason"]', 'E2E test: Curator verified mesh conflict');

    await page.click('button[type="submit"]:has-text("Save Assessment")');

    // Wait for save feedback
    await expect(page.locator('text=Compatibility assessment saved successfully!')).toBeVisible();

    // Close modal
    await page.click('button:has-text("Cancel")');

    // 5. Back to the loadout fixed in step 3
    await page.goto(`/loadouts/${BROKEN_SKYRIM_UI}`);
    await expect(page.locator('h1')).toContainText('Broken Skyrim UI');

    // 6. Verify loadout status turned broken due to INCOMPATIBLE_PAIR
    await expect(healthPanel(page).getByText('broken', { exact: true })).toBeVisible();
    await expect(page.locator('text=INCOMPATIBLE_PAIR').first()).toBeVisible();

    // Save screenshot
    await page.screenshot({ path: path.join(screenshotsDir, '04-curator-heatmap.png') });
  });

  test('Step 5: Admin Inspects Audit Log and Views Side-by-Side Diff', async ({ page }) => {
    // 1. Log in as admin
    await loginAs(page, 'admin', 'admin-demo-123');

    // 2. Navigate to /admin
    await page.goto('/admin');
    await expect(page.locator('h1')).toContainText('System Administration');

    // 3. Find curator change in audit log table
    const curatorEntry = page.locator('tr:has-text("compatibility_matrix"):has-text("curator")').first();
    await expect(curatorEntry).toBeVisible();

    // 4. Click "View Diff" button
    const viewDiffButton = curatorEntry.locator('button:has-text("View Diff")');
    await viewDiffButton.click();

    // 5. Modal shows side-by-side comparison
    const diffModal = page.locator('text=Audit Entry #').first();
    await expect(diffModal).toBeVisible();
    await expect(page.locator('text=Changed by curator').first()).toBeVisible();

    // Status field should show MODIFIED tag
    await expect(page.locator('text=MODIFIED').first()).toBeVisible();

    // Save screenshot
    await page.screenshot({ path: path.join(screenshotsDir, '05-admin-audit-diff.png') });

    // Close diff
    await page.click('button:has-text("Close Diff")');
  });

  test('Step 6: Modder2 Cannot View Modder1 Private Loadout (RLS Enforcement)', async ({ page }) => {
    // 1. Log in as modder1 to create a private loadout
    await loginAs(page, 'modder1', 'modder1-demo-123');

    // Navigate to /loadouts and create private loadout
    await page.goto('/loadouts');
    await page.fill('input[name="name"]', PRIVATE_LOADOUT_NAME);
    
    // Select Skyrim Special Edition
    const gameSelect = page.locator('select[name="game_id"]');
    await gameSelect.selectOption({ label: 'Skyrim Special Edition' });

    await page.fill('input[name="game_version"]', '1.6.1170');
    await page.fill('textarea[name="description"]', 'Private loadout owned exclusively by modder1');

    // Uncheck is_public to make it private
    const isPublicCheckbox = page.locator('input[name="is_public"]');
    if (await isPublicCheckbox.isChecked()) {
      await isPublicCheckbox.uncheck();
    }

    await page.click('button:has-text("Create Loadout")');

    // Wait for redirect to the new loadout page
    await page.waitForURL((url) => url.pathname.includes('/loadouts/'));
    createdPrivateLoadoutUrl = page.url();
    expect(createdPrivateLoadoutUrl).toContain('/loadouts/');
    await expect(page.locator('h1')).toContainText('Modder1 Private Vault');

    // 2. Log in as modder2
    await loginAs(page, 'modder2', 'modder2-demo-123');

    // 3. Confirm private loadout is NOT visible in loadouts dashboard
    await page.goto('/loadouts');
    await expect(page.locator('text=Modder1 Private Vault')).not.toBeVisible();

    // 4. Confirm direct navigation to modder1 private loadout is denied (404 Not Found)
    await page.goto(createdPrivateLoadoutUrl);
    await expect(page.getByRole('heading', { name: '404' })).toBeVisible();

    // Save screenshot
    await page.screenshot({ path: path.join(screenshotsDir, '06-private-loadout-hidden.png') });
  });

  test('Capture Additional UI Screenshots for Deploy Documentation', async ({ page }) => {
    // 1. Home page
    await page.goto('/');
    await page.screenshot({ path: path.join(screenshotsDir, 'home.png') });

    // 2. Game Browse page
    await page.goto('/games/skyrimspecialedition');
    await page.screenshot({ path: path.join(screenshotsDir, 'game-skyrim.png') });

    // 3. Mod detail page (SkyUI)
    await page.goto('/mods/cc9c9ffc-c0f9-5d62-a337-f99c63cda42a');
    await expect(page.locator('h1')).toBeVisible();
    await page.screenshot({ path: path.join(screenshotsDir, 'mod-detail.png') });

    // 4. Mod publish page (as modder1)
    await loginAs(page, 'modder1', 'modder1-demo-123');
    await page.goto('/mods/new');
    await page.screenshot({ path: path.join(screenshotsDir, 'mod-publish.png') });

    // 5. Loadouts dashboard
    await page.goto('/loadouts');
    await page.screenshot({ path: path.join(screenshotsDir, 'loadouts.png') });

    // 6. Admin audit page (as admin)
    await loginAs(page, 'admin', 'admin-demo-123');
    await page.goto('/admin');
    await page.screenshot({ path: path.join(screenshotsDir, 'admin.png') });
  });
});
