const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { request, result, identityScript } = require('./kudu-command.cjs');
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
const unix = value => value.replaceAll('\\', '/').replace(/^([A-Za-z]):/, (_, drive) => '/' + drive.toLowerCase());

function execute(script) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'kudu-command-contract-'));
  try {
    const starter = path.join(root, 'starter.sh');
    // Exact Linux Kudu starter behaviour: it does not eval the command string.
    fs.writeFileSync(starter, '#!/usr/bin/env bash\nexec "$@"\n');
    const command = request(script).command;
    const match = command.match(/^bash -c "([^"\\]*)"$/);
    assert.ok(match, 'The shell must be explicitly requested as one -c argument');
    return spawnSync(bash, [unix(starter), 'bash', '-c', match[1]], { encoding: 'utf8', windowsHide: true });
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
  assert.equal(result({ ExitCode: 0, Output: first.stdout, Error: first.stderr }, 'identity'),
    result({ ExitCode: 0, Output: second.stdout, Error: second.stderr }, 'identity'));
});
