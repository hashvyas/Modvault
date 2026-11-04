import { test, expect, type Page } from '@playwright/test';
import * as path from 'path';

try {
  process.loadEnvFile(path.resolve(process.cwd(), '../.env'));
} catch {
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
    page.on('dialog', async (dialog) => {
      await dialog.accept();
    });
    await loginAs(page, 'admin', ADMIN_PASSWORD);
    await page.goto(`/mods/${SKYUI_ID}`);
    await expect(page.locator('h1')).toContainText('SkyUI');
    await page.goto('/loadouts');
    await expect(page.locator('h1')).toContainText('Loadout Manager');
    await page.fill('input[name="name"]', TEST_LOADOUT_NAME);
    const gameSelect = page.locator('select[name="game_id"]');
    await gameSelect.selectOption({ label: 'Skyrim Special Edition' });
    await page.click('button:has-text("Create Loadout")');
    await page.waitForURL((url) => url.pathname.includes('/loadouts/'));
    const loadoutUrl = page.url();
    await expect(page.locator('h1')).toContainText(TEST_LOADOUT_NAME);
    const detailRemoveBtn = page.locator('button:has-text("Remove Loadout")');
    await expect(detailRemoveBtn).toBeVisible();
    await page.goto(`/mods/${SKYUI_ID}`);
    await expect(page.locator('h1')).toContainText('SkyUI');
    const loadoutPickerSelect = page.locator('select[name="loadout_id"]');
    await expect(loadoutPickerSelect).toBeVisible();
    await expect(loadoutPickerSelect.locator(`option:has-text("${TEST_LOADOUT_NAME}")`)).toBeAttached();
    await loadoutPickerSelect.selectOption({ label: TEST_LOADOUT_NAME });
    await page.click('button:has-text("Add to Loadout")');
    await expect(page.locator('text=Loadout updated!')).toBeVisible();
    await page.goto('/loadouts');
    await expect(page.locator(`text=${TEST_LOADOUT_NAME}`)).toBeVisible();
    const card = page.locator('div.rounded-xl, div.rounded-2xl', {
      has: page.locator(`text=${TEST_LOADOUT_NAME}`),
    }).first();
    const cardRemoveBtn = card.locator('button[title*="Remove"], button:has-text("Remove")').first();
    await expect(cardRemoveBtn).toBeVisible();
    await cardRemoveBtn.click();
    await expect(page.locator(`text=${TEST_LOADOUT_NAME}`)).not.toBeVisible();
    await page.goto(loadoutUrl);
    await expect(page.getByRole('heading', { name: '404' })).toBeVisible();
  });
});
