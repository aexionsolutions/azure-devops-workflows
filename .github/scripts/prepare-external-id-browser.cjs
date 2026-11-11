'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// This runs before credentials are used. A real launch still fails the job if the
// hosted runner lacks a required library; an install alone is not readiness.
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
  if (result.error || result.status !== 0) {
    throw new Error(`External ID browser preparation failed at ${command} (exit ${result.status ?? 'unavailable'}).`);
  }
}

function prepare(caller, run = execute) {
  caller = path.resolve(caller);
  const web = ['rx-web', 'web/tems-portal']
    .map(relative => path.join(caller, relative))
    .find(directory => fs.existsSync(path.join(directory, 'package-lock.json')));
  if (!web || !fs.existsSync(path.join(caller, 'tools/e2e/external-id-browser-token.cjs'))) {
    throw new Error('External ID smoke requires the caller browser helper and a locked Playwright web package.');
  }
  run('npm', ['ci', '--prefix', web, '--ignore-scripts', '--no-audit', '--no-fund'], caller);
  // Ubuntu hosted images already contain the Chromium runtime libraries. Avoid
  // refreshing apt/installing optional fonts on every promotion: mirror DNS can
  // fail even when the browser is runnable. Never ignore a failed install/launch.
  run('npx', ['--no-install', 'playwright', 'install', 'chromium'], web);
  run(process.execPath, ['-e', launchProbe], web);
}

if (require.main === module) {
  try { prepare(process.argv[2] || path.join(process.env.GITHUB_WORKSPACE || '.', 'caller')); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
module.exports = { prepare, launchProbe };
