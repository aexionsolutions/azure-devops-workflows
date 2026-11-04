const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { request, result, identityScript } = require('./kudu-command.cjs');
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
const unix = value => value.replaceAll('\\', '/').replace(/^([A-Za-z]):/, (_, drive) => '/' + drive.toLowerCase());

function execute(script, options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'kudu-command-contract-'));
  try {
    const starter = path.join(root, 'starter.sh');
    // Exact Linux Kudu starter behaviour: it does not eval the command string.
    fs.writeFileSync(starter, '#!/usr/bin/env bash\nexec "$@"\n');
    const command = request(script).command;
    const match = command.match(/^bash -c "([^"\\]*)"$/);
    assert.ok(match, 'The shell must be explicitly requested as one -c argument');
    return spawnSync(bash, [unix(starter), 'bash', '-c', match[1]], {
      cwd: options.cwd, encoding: 'utf8', windowsHide: true, timeout: 15000,
    });
  } finally {
    assert.ok(path.resolve(root).startsWith(path.resolve(os.tmpdir()) + path.sep));
    assert.ok(path.basename(root).startsWith('kudu-command-contract-'));
    fs.rmSync(root, { recursive: true, force: true });
  }
}

test('Kudu direct-exec actually runs the decoded script, including its pipeline', () => {
  const r = execute('printf "%s\\n" "APP_SERVICE_NODE_CLEANUP_COMPLETE"');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim(), 'APP_SERVICE_NODE_CLEANUP_COMPLETE');
  assert.equal(result({ ExitCode: r.status, Output: r.stdout, Error: r.stderr }, 'cleanup'), 'APP_SERVICE_NODE_CLEANUP_COMPLETE');
});

test('the production cleanup entry point executes through Kudu stdin and preserves application files', () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'kudu-cleanup-stdin-'));
  const root = path.join(temp, 'site', 'wwwroot');
  try {
    for (const folder of ['.next/cache', '.next/server/app', 'uploads', 'node_modules']) {
      fs.mkdirSync(path.join(root, folder), { recursive: true });
    }
    const generated = ['.next/cache/generated', 'oryx-manifest.toml', 'node_modules.tar.zst'];
    const preserved = ['.next/server/app/page.html', 'uploads/keep.txt', 'node_modules/current.js'];
    for (const file of [...generated, ...preserved]) fs.writeFileSync(path.join(root, file), 'fixture');
    const source = fs.readFileSync(path.join(__dirname, 'clean-node-runtime.sh'), 'utf8');
    const entry = 'clean_node_runtime /home/site/wwwroot';
    assert.equal(source.split(entry).length, 2, 'Only substitute the fixed deployment root for this isolated fixture');
    // Keep the complete production script and its stdin entry-point detection.
    // The fixture's physical cwd handles Git Bash /tmp aliases; root guards stay enabled.
    const script = source.replace(entry, 'clean_node_runtime "$(pwd -P)"');
    const r = execute(script, { cwd: root });
    assert.equal(r.status, 0, r.stderr + r.stdout);
    assert.equal(result({ ExitCode: r.status, Output: r.stdout, Error: r.stderr }, 'cleanup'), 'APP_SERVICE_NODE_CLEANUP_COMPLETE');
    for (const file of generated) assert.equal(fs.existsSync(path.join(root, file)), false, file);
    for (const file of preserved) assert.equal(fs.readFileSync(path.join(root, file), 'utf8'), 'fixture', file);

    const refused = execute(script, { cwd: temp });
    assert.notEqual(refused.status, 0, 'A cwd outside site/wwwroot must still be refused');
    assert.match(refused.stderr, /Unexpected application root/);
    assert.throws(() => result({ ExitCode: refused.status, Output: refused.stdout, Error: refused.stderr }, 'cleanup'));
  } finally {
    assert.ok(path.resolve(temp).startsWith(path.resolve(os.tmpdir()) + path.sep));
    assert.ok(path.basename(temp).startsWith('kudu-cleanup-stdin-'));
    fs.rmSync(temp, { recursive: true, force: true });
  }
});

test('a failing decoded script retains its nonzero status', () => {
  const r = execute('exit 17');
  assert.equal(r.status, 17);
  assert.throws(() => result({ ExitCode: r.status, Output: r.stdout, Error: r.stderr }, 'cleanup'));
});

test('the observed zero-exit base64 echo is not successful cleanup', () => {
  assert.throws(() => result({ ExitCode: 0, Output: 'IyEvdXNyL2Jpbi9lbnYgYmFzaA==|base64-d|bash\n', Error: '' }, 'cleanup'));
});

test('missing, malformed or contradictory cleanup results fail closed', () => {
  for (const raw of ['not JSON', '{}', JSON.stringify({ ExitCode: '0', Output: 'APP_SERVICE_NODE_CLEANUP_COMPLETE', Error: '' }),
    JSON.stringify({ ExitCode: 0, Output: 'APP_SERVICE_NODE_CLEANUP_COMPLETE', Error: 'execution error' })]) assert.throws(() => result(raw, 'cleanup'));
});

test('SCM identity refers to the same executor across separate commands', { skip: process.platform === 'win32' }, () => {
  const first = execute(identityScript);
  const second = execute(identityScript);
  assert.equal(first.status, 0, first.stderr);
  assert.equal(second.status, 0, second.stderr);
  // This Node process stands in for the long-lived Kudu executor, not one of
  // the new Bash/pipeline processes spawned for each request.
  const hostFields = fs.readFileSync(`/proc/${process.pid}/stat`, 'utf8').replace(/^.*\) /, '').trim().split(/\s+/);
  assert.equal(first.stdout.trim(), `SCM_PROCESS:${process.pid}:${hostFields[19]}`);
  assert.equal(result({ ExitCode: 0, Output: first.stdout, Error: first.stderr }, 'identity'),
    result({ ExitCode: 0, Output: second.stdout, Error: second.stderr }, 'identity'));
});
