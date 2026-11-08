const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
const unix = value => value.replaceAll('\\', '/').replace(/^([A-Za-z]):/, (_, drive) => '/' + drive.toLowerCase());

function deploy(mode, runtime = 'DOTNETCORE|10.0', failSettings = false) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'immutable-package-contract-'));
  try {
    const bin = path.join(root, 'bin');
    fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin, 'az'), `#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FIXTURE_ROOT/az.calls"
case "$*" in
  *publishingUserName*) echo fixture-user;;
  *publishingPassword*) echo fixture-password;;
  *linuxFxVersion*) echo "$FIXTURE_RUNTIME";;
  *'appsettings set'*) if [ "$FAIL_SETTINGS" = true ]; then exit 13; fi;;
esac
`, { mode: 0o755 });
    fs.writeFileSync(path.join(bin, 'curl'), `#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FIXTURE_ROOT/curl.calls"
destination=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = '-o' ]; then destination="$2"; shift; fi
  shift
done
if [ -n "$destination" ]; then
  id=new
  case "$destination" in *before.json) id=old;; esac
  printf '{"id":"%s","status":4,"provisioningState":"Succeeded","complete":true}' "$id" > "$destination"
fi
`, { mode: 0o755 });
    fs.writeFileSync(path.join(root, 'package.zip'), 'fixture package; upload is intercepted');
    const runner = path.join(root, 'run.sh');
    fs.writeFileSync(runner, `#!/usr/bin/env bash
export PATH="${unix(bin)}:$PATH"
exec bash "${unix(path.join(__dirname, 'deploy-package.sh'))}"
`);
    const result = spawnSync(bash, [unix(runner)], {
      cwd: root, encoding: 'utf8', timeout: 20000, windowsHide: true,
      env: { ...process.env, RG: 'qa-rg', APP: 'qa-app', PACKAGE: unix(path.join(root, 'package.zip')),
        RUNNER_TEMP: unix(root), FIXTURE_ROOT: unix(root), FIXTURE_RUNTIME: runtime,
        RUN_FROM_PACKAGE: mode, CLEAN_NODE_RUNTIME: 'false', SCM_SETTLE_SECONDS: '0',
        DEPLOY_TIMEOUT_MINUTES: '1', FAIL_SETTINGS: String(failSettings) },
    });
    assert.equal(result.status, 0, result.stderr + result.stdout);
    const read = file => fs.existsSync(path.join(root, file)) ? fs.readFileSync(path.join(root, file), 'utf8') : '';
    return { az: read('az.calls'), curl: read('curl.calls'), failure: read('deploy_fail.txt'), output: result.stdout };
  } finally {
    assert.ok(path.resolve(root).startsWith(path.resolve(os.tmpdir()) + path.sep));
    assert.ok(path.basename(root).startsWith('immutable-package-contract-'));
    fs.rmSync(root, { recursive: true, force: true });
  }
}

test('Linux .NET opt-in keeps run-from-package mounted through successful upload', () => {
  const result = deploy('true');
  assert.equal(result.failure, '');
  assert.match(result.az, /appsettings set .*WEBSITE_RUN_FROM_PACKAGE=1/);
  assert.doesNotMatch(result.az, /appsettings delete/);
  assert.match(result.curl, /api\/zipdeploy\?isAsync=true/);
  assert.doesNotMatch(result.az, /webapp restart/);
});

test('existing extracted Node deployment retains its original behaviour', () => {
  const result = deploy('false', 'NODE|24-lts');
  assert.equal(result.failure, '');
  assert.match(result.az, /appsettings delete .*WEBSITE_RUN_FROM_PACKAGE/);
  assert.match(result.az, /SCM_ZIPDEPLOY_DONOT_PRESERVE_FILETIME=1/);
  assert.match(result.curl, /api\/zipdeploy/);
});

test('a failed package configuration cannot proceed to upload', () => {
  const result = deploy('true', 'DOTNETCORE|10.0', true);
  assert.match(result.failure, /deploy failed/);
  assert.doesNotMatch(result.curl, /api\/zipdeploy/);
});

for (const runtime of ['NODE|24-lts', 'PYTHON|3.12']) {
  test(`immutable opt-in refuses unsupported or unconfirmed runtime ${runtime}`, () => {
    const result = deploy('true', runtime);
    assert.match(result.failure, /invalid-immutable-runtime/);
    assert.doesNotMatch(result.curl, /api\/zipdeploy/);
  });
}

test('existing Windows OneDeploy remains supported when package mode is requested', () => {
  const result = deploy('true', '');
  assert.equal(result.failure, '');
  assert.match(result.az, /webapp deploy/);
  assert.doesNotMatch(result.az, /appsettings delete/);
});

test('malformed mode fails closed instead of silently extracting DLLs', () => {
  assert.match(deploy('yes').failure, /invalid-package-mode/);
});
