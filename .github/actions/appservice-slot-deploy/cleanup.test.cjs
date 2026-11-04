const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
const unix = value => value.replaceAll('\\', '/').replace(/^([A-Za-z]):/, (_, drive) => '/' + drive.toLowerCase());

function fixture(check, options = {}) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'appservice-cleanup-test-'));
  const root = path.join(temp, 'site', 'wwwroot');
  try {
    for (const folder of ['.next/cache', '.next/server/app', 'uploads', 'node_modules']) {
      fs.mkdirSync(path.join(root, folder), { recursive: true });
    }
    for (const file of ['.next/cache/generated', '.next/server/app/page.html',
      'uploads/keep.txt', 'node_modules/current.js', 'oryx-manifest.toml', 'node_modules.tar.zst']) {
      fs.writeFileSync(path.join(root, file), 'fixture');
    }
    options.setup?.(root, temp);
    const script = path.join(temp, 'run.sh');
    // Git Bash exposes Windows' temp directory through both /c/... and /tmp.
    // Use this shell's physical cwd for the positive fixture, as Kudu does.
    const parameter = options.wrongDirectory || options.wrongRoot ? '"$RUNTIME_TEST_ROOT"' : '"$(pwd -P)"';
    fs.writeFileSync(script, `source "${unix(path.join(__dirname, 'clean-node-runtime.sh'))}"\nclean_node_runtime ${parameter}\n`);
    const result = spawnSync(bash, [unix(script)], {
      cwd: options.wrongDirectory ? temp : root,
      env: { ...process.env, RUNTIME_TEST_ROOT: unix(options.wrongRoot ? temp : root) },
      encoding: 'utf8', windowsHide: true, timeout: 15000,
    });
    check(result, root, temp);
  } finally {
    assert.ok(path.resolve(temp).startsWith(path.resolve(os.tmpdir()) + path.sep));
    assert.ok(path.basename(temp).startsWith('appservice-cleanup-test-'));
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

test('clears generated cache and Oryx archives while preserving pages, modules and uploads', () => {
  fixture((result, root) => {
    assert.equal(result.status, 0, result.stderr + result.stdout);
    for (const file of ['.next/cache', 'oryx-manifest.toml', 'node_modules.tar.zst']) {
      assert.equal(fs.existsSync(path.join(root, file)), false, file);
    }
    for (const file of ['.next/server/app/page.html', 'uploads/keep.txt', 'node_modules/current.js']) {
      assert.equal(fs.readFileSync(path.join(root, file), 'utf8'), 'fixture', file);
    }
  });
});

for (const option of ['wrongDirectory', 'wrongRoot']) test(`refuses ${option} before deleting anything`, () => {
  fixture((result, root) => {
    assert.equal(result.status, 1);
    assert.equal(fs.existsSync(path.join(root, 'oryx-manifest.toml')), true);
    assert.equal(fs.existsSync(path.join(root, '.next/cache/generated')), true);
  }, { [option]: true });
});

test('refuses a cache symlink before deleting any artifacts', { skip: process.platform === 'win32' }, () => {
  fixture((result, root, temp) => {
    assert.equal(result.status, 1);
    assert.equal(fs.existsSync(path.join(root, 'oryx-manifest.toml')), true);
    assert.equal(fs.readFileSync(path.join(temp, 'outside/keep'), 'utf8'), 'keep');
  }, { setup(root, temp) {
    fs.mkdirSync(path.join(temp, 'outside'));
    fs.writeFileSync(path.join(temp, 'outside/keep'), 'keep');
    fs.unlinkSync(path.join(root, '.next/cache/generated'));
    fs.rmdirSync(path.join(root, '.next/cache'));
    fs.symlinkSync(path.join(temp, 'outside'), path.join(root, '.next/cache'));
  } });
});

test('removes the old modules symlink without following it', { skip: process.platform === 'win32' }, () => {
  fixture((result, root, temp) => {
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.existsSync(path.join(root, 'node_modules')), false);
    assert.equal(fs.readFileSync(path.join(temp, 'outside/keep'), 'utf8'), 'keep');
  }, { setup(root, temp) {
    fs.mkdirSync(path.join(temp, 'outside'));
    fs.writeFileSync(path.join(temp, 'outside/keep'), 'keep');
    fs.unlinkSync(path.join(root, 'node_modules/current.js'));
    fs.rmdirSync(path.join(root, 'node_modules'));
    fs.symlinkSync(path.join(temp, 'outside'), path.join(root, 'node_modules'));
  } });
});
