'use strict';
const { spawnSync } = require('node:child_process');

const launchProbe = `
const { chromium } = require('@playwright/test');
(async () => {
  const browser = await chromium.launch({ headless: true,
    channel: process.env.E2E_OIDC_BROWSER_CHANNEL || undefined });
  try {
    const page = await browser.newPage();
    await page.setContent('<title>Browser readiness</title><p>ready</p>');
    if (await page.locator('p').textContent() !== 'ready') throw new Error('Browser readiness failed');
  } finally { await browser.close(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
`;

function execute(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, stdio: 'inherit', timeout: 240000 });
  if (result.error || result.status !== 0) throw new Error(`Browser preparation failed at ${command} (exit ${result.status ?? 'unavailable'}).`);
}

function installBrowser(web, run = execute) {
  // Hosted Ubuntu already has the runtime libraries. A real launch is required
  // so a future image missing a library still fails, without unconditional apt.
  run('npx', ['--no-install', 'playwright', 'install', 'chromium'], web);
  run(process.execPath, ['-e', launchProbe], web);
}
if (require.main === module) {
  try { installBrowser(process.argv[2] || process.cwd()); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
module.exports = { installBrowser, launchProbe };
