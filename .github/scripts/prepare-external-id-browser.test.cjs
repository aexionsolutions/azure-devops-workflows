const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { prepare } = require('./prepare-external-id-browser.cjs');

function fixture(web, action) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'external-browser-'));
  try {
    fs.mkdirSync(path.join(root, web), { recursive: true });
    fs.writeFileSync(path.join(root, web, 'package-lock.json'), '{}');
    fs.mkdirSync(path.join(root, 'tools/e2e'), { recursive: true });
    fs.writeFileSync(path.join(root, 'tools/e2e/external-id-browser-token.cjs'), '');
    action(root);
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
}

for (const web of ['rx-web', 'web/tems-portal']) {
  test(`${web}: unavailable apt mirror does not prevent an installed-library browser launch`, () => {
    fixture(web, root => {
      const calls = [];
      prepare(root, (command, args, cwd) => {
        // The three failed promotions had working native libraries, but apt DNS
        // failed while installing optional fonts. Reintroducing --with-deps fails.
        if (args.includes('--with-deps') || args.includes('install-deps')) {
          throw new Error("Temporary failure resolving 'azure.archive.ubuntu.com'");
        }
        calls.push({ command, args, cwd });
      });
      assert.equal(calls.length, 3);
      assert.deepEqual(calls[0].args, ['ci', '--prefix', path.join(root, web), '--ignore-scripts', '--no-audit', '--no-fund']);
      assert.deepEqual(calls[1].args, ['--no-install', 'playwright', 'install', 'chromium']);
      assert.equal(calls[2].command, process.execPath);
      assert.match(calls[2].args[1], /chromium\.launch/);
      assert.match(calls[2].args[1], /await browser\.close/);
      assert.equal(calls[2].cwd, path.join(root, web));
    });
  });
}

for (const failAt of [0, 1, 2]) {
  test(`failure at setup step ${failAt + 1} stops verification`, () => {
    fixture('rx-web', root => {
      let calls = 0;
      assert.throws(() => prepare(root, () => {
        if (calls++ === failAt) throw new Error('setup failed');
      }), /setup failed/);
      assert.equal(calls, failAt + 1);
    });
  });
}

test('missing caller helper fails before downloading or launching anything', () => {
  fixture('rx-web', root => {
    fs.unlinkSync(path.join(root, 'tools/e2e/external-id-browser-token.cjs'));
    assert.throws(() => prepare(root, () => assert.fail('must not run')), /requires the caller/);
  });
});

test('the API deployment uses the tested setup and retains protected smoke authentication', () => {
  const workflow = fs.readFileSync(path.join(__dirname, '../workflows/deploy-template-api.yml'), 'utf8');
  const setup = workflow.split('- name: Prepare External ID browser verification')[1]
    .split('- name: Acquire delegated token for protected smoke')[0];
  assert.match(setup, /prepare-external-id-browser\.cjs/);
  assert.match(workflow, /mint-external-id-smoke\.cjs/);
  assert.match(workflow, /- name: API protected smoke \(auto\)/);
});
