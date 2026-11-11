const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { installBrowser } = require('./install-browser.cjs');

test('an unavailable apt mirror does not prevent browser readiness', () => {
  const calls = [];
  installBrowser('caller/rx-web', (command, args, cwd) => {
    if (args.includes('--with-deps')) throw new Error("Temporary failure resolving 'azure.archive.ubuntu.com'");
    calls.push({ command, args, cwd });
  });
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[0].args, ['--no-install', 'playwright', 'install', 'chromium']);
  assert.match(calls[1].args[1], /chromium\.launch/);
  assert.match(calls[1].args[1], /await browser\.close/);
  assert.equal(calls[1].cwd, 'caller/rx-web');
});
for (const failAt of [0, 1]) {
  test(`failed ${failAt === 0 ? 'install' : 'launch'} blocks test execution`, () => {
    let calls = 0;
    assert.throws(() => installBrowser('caller/rx-web', () => {
      if (calls++ === failAt) throw new Error('failed setup');
    }), /failed setup/);
    assert.equal(calls, failAt + 1);
  });
}
test('the composite executes the installer before the actual suite', () => {
  const action = fs.readFileSync(path.join(__dirname, 'action.yml'), 'utf8');
  assert.match(action, /node "\$GITHUB_ACTION_PATH\/install-browser\.cjs"/);
  assert.ok(action.indexOf('install-browser.cjs') < action.indexOf('- name: Run Playwright tests'));
  assert.doesNotMatch(action, /install --with-deps/);
});
