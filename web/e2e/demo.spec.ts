import { test, expect, type Page } from '@playwright/test';
import * as path from 'path';
import * as fs from 'fs';

// Helper to ensure docs/screenshots directory exists
const screenshotsDir = path.resolve(process.cwd(), '../docs/screenshots');
if (!fs.existsSync(screenshotsDir)) {
  fs.mkdirSync(screenshotsDir, { recursive: true });
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
    await loginAs(page, 'modder1', 'REDACTED');

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

    // 4. Verify score, broken status badge, and diagnostic errors
    const statusBadge = page.getByText('broken', { exact: false }).first();
    await expect(statusBadge).toBeVisible();

    const errorsSection = page.getByRole('heading', { name: /Errors/i }).first();
    await expect(errorsSection).toBeVisible();

    const missingDep = page.locator('text=MISSING_DEPENDENCY').first();
    await expect(missingDep).toBeVisible();

    // Save screenshot
    await page.screenshot({ path: path.join(screenshotsDir, '02-broken-loadout.png') });
  });

  test('Step 3: Add Missing Dependency and Auto-sort Load Order', async ({ page }) => {
    // Log in as modder1 if session is not preserved
    await loginAs(page, 'modder1', 'REDACTED');

    // Open Broken Skyrim UI
    await page.goto('/loadouts/74867771-c761-5ed8-9468-8358f8cad4f8');
    await expect(page.locator('h1')).toContainText('Broken Skyrim UI');

    // Click "Add SkyUI" to resolve missing dependency
    const addDepButton = page.locator('button:has-text("Add SkyUI"), button:has-text("Add")').first();
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

    // Status should have improved: MISSING_DEPENDENCY resolved
    await expect(page.locator('text=MISSING_DEPENDENCY')).not.toBeVisible();

    // Save screenshot
    await page.screenshot({ path: path.join(screenshotsDir, '03-fixed-loadout.png') });
  });

  test('Step 4: Curator Marks Pair Incompatible on Matrix, Flipping Loadout to Broken', async ({ page }) => {
    // 1. Log in as curator
    await loginAs(page, 'curator', 'REDACTED');

    // 2. Navigate to Skyrim SE Compatibility Heatmap
    await page.goto('/games/skyrimspecialedition/compat');
    await expect(page.locator('h1')).toContainText('Compatibility Heatmap');

    // 3. Select a pair of mods that exist in Healthy Skyrim Essentials:
    // "Unofficial Skyrim Special Edition Patch - USSEP" and "SkyUI"
    const cellButton = page.locator(
      'button[title*="Unofficial Skyrim Special Edition Patch"][title*="SkyUI"]'
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

    // 5. Navigate to "Healthy Skyrim Essentials" loadout
    await page.goto('/loadouts/3b88929e-c10b-59de-9758-5f1b7538a451');
    await expect(page.locator('h1')).toContainText('Healthy Skyrim Essentials');

    // 6. Verify loadout status turned broken due to INCOMPATIBLE_PAIR
    await expect(page.getByText('broken', { exact: false }).first()).toBeVisible();
    await expect(page.locator('text=INCOMPATIBLE_PAIR').first()).toBeVisible();

    // Save screenshot
    await page.screenshot({ path: path.join(screenshotsDir, '04-curator-heatmap.png') });
  });

  test('Step 5: Admin Inspects Audit Log and Views Side-by-Side Diff', async ({ page }) => {
    // 1. Log in as admin
    await loginAs(page, 'admin', 'REDACTED');

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
    await loginAs(page, 'modder1', 'REDACTED');

    // Navigate to /loadouts and create private loadout
    await page.goto('/loadouts');
    await page.fill('input[name="name"]', 'Modder1 Private Vault');
    
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
    await loginAs(page, 'modder2', 'REDACTED');

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
    await loginAs(page, 'modder1', 'REDACTED');
    await page.goto('/mods/new');
    await page.screenshot({ path: path.join(screenshotsDir, 'mod-publish.png') });

    // 5. Loadouts dashboard
    await page.goto('/loadouts');
    await page.screenshot({ path: path.join(screenshotsDir, 'loadouts.png') });

    // 6. Admin audit page (as admin)
    await loginAs(page, 'admin', 'REDACTED');
    await page.goto('/admin');
    await page.screenshot({ path: path.join(screenshotsDir, 'admin.png') });
  });
});
