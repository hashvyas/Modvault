import { test, expect, type Page } from '@playwright/test';
import * as path from 'path';

try {
  process.loadEnvFile(path.resolve(process.cwd(), '../.env'));
} catch {
  // Rely on env
}

const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? '';

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

test.describe('Loadout Management: Create, Add to Mod, and Remove', () => {
  const TEST_LOADOUT_NAME = `Test Loadout ${Date.now()}`;
  const SKYUI_ID = 'cc9c9ffc-c0f9-5d62-a337-f99c63cda42a';

  test('New loadout appears during add without refresh, and remove option works', async ({ page }) => {
    // Handle confirmation dialogs automatically
    page.on('dialog', async (dialog) => {
      await dialog.accept();
    });

    // 1. Log in as admin
    await loginAs(page, 'admin', ADMIN_PASSWORD);

    // 2. Visit mod page first (to simulate previous visit and router cache)
    await page.goto(`/mods/${SKYUI_ID}`);
    await expect(page.locator('h1')).toContainText('SkyUI');

    // 3. Navigate to personal loadouts (/loadouts)
    await page.goto('/loadouts');
    await expect(page.locator('h1')).toContainText('Loadout Manager');

    // 4. Create new loadout
    await page.fill('input[name="name"]', TEST_LOADOUT_NAME);
    const gameSelect = page.locator('select[name="game_id"]');
    await gameSelect.selectOption({ label: 'Skyrim Special Edition' });
    await page.click('button:has-text("Create Loadout")');

    // 5. Verify redirection to the newly created loadout detail page
    await page.waitForURL((url) => url.pathname.includes('/loadouts/'));
    const loadoutUrl = page.url();
    await expect(page.locator('h1')).toContainText(TEST_LOADOUT_NAME);

    // Verify "Remove Loadout" button is present on the loadout detail page for the owner
    const detailRemoveBtn = page.locator('button:has-text("Remove Loadout")');
    await expect(detailRemoveBtn).toBeVisible();

    // 6. Navigate directly to the mod page (Add to Loadout)
    await page.goto(`/mods/${SKYUI_ID}`);
    await expect(page.locator('h1')).toContainText('SkyUI');

    // 7. Verify the newly created loadout appears in the "Add to Loadout" dropdown WITHOUT refreshing!
    const loadoutPickerSelect = page.locator('select[name="loadout_id"]');
    await expect(loadoutPickerSelect).toBeVisible();
    await expect(loadoutPickerSelect.locator(`option:has-text("${TEST_LOADOUT_NAME}")`)).toBeAttached();

    // Select the new loadout and add mod
    await loadoutPickerSelect.selectOption({ label: TEST_LOADOUT_NAME });
    await page.click('button:has-text("Add to Loadout")');
    await expect(page.locator('text=Loadout updated!')).toBeVisible();

    // 8. Go back to /loadouts and verify the loadout appears in "My Loadouts"
    await page.goto('/loadouts');
    await expect(page.locator(`text=${TEST_LOADOUT_NAME}`)).toBeVisible();

    // Verify remove button is present on the loadout card in My Loadouts
    const card = page.locator('div.rounded-xl, div.rounded-2xl', {
      has: page.locator(`text=${TEST_LOADOUT_NAME}`),
    }).first();
    const cardRemoveBtn = card.locator('button[title*="Remove"], button:has-text("Remove")').first();
    await expect(cardRemoveBtn).toBeVisible();

    // 9. Click Remove on the loadout card and verify it is removed
    await cardRemoveBtn.click();
    await expect(page.locator(`text=${TEST_LOADOUT_NAME}`)).not.toBeVisible();

    // 10. Also verify that navigating to the deleted loadout URL returns 404
    await page.goto(loadoutUrl);
    await expect(page.getByRole('heading', { name: '404' })).toBeVisible();
  });
});
