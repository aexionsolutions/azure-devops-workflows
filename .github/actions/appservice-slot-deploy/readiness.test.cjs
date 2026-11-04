const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
const unix = value => value.replaceAll('\\', '/').replace(/^([A-Za-z]):/, (_, drive) => '/' + drive.toLowerCase());
const action = fs.readFileSync(path.join(__dirname, 'action.yml'), 'utf8');
const curl = `#!/usr/bin/env bash
echo "curl $*" >> "$CALLS"
out=""; headers=""; url=""; limit=15
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -D) headers="$2"; shift ;;
    --max-time) limit="$2"; shift ;;
    https://*) url="$1" ;;
  esac
  shift
done
if [ "$MODE" = deploy ] || [ "$MODE" = windows ]; then
  case "$url" in
    */api/command) body='{"ExitCode":0,"Output":""}'; [ "$CLEANUP_FAIL" != true ] || body='{"ExitCode":1,"Error":"fixture refusal"}' ;;
    */api/zipdeploy*) touch "$POSTED"; [ -z "$headers" ] || echo 'HTTP/1.1 202 Accepted' > "$headers"; exit 0 ;;
    */api/deployments/latest/log) body='[]' ;;
    */api/deployments/latest)
      id=old; [ ! -f "$POSTED" ] || id=new
      body="{\\"id\\":\\"$id\\",\\"status\\":4,\\"complete\\":true}" ;;
    *) exit 2 ;;
  esac
  [ -z "$out" ] || printf '%s' "$body" > "$out"
  exit 0
fi
[ "$url" = 'https://health.invalid/healthz?deep=true' ] || exit 2
n=$(cat "$COUNTER"); n=$((n+1)); echo "$n" > "$COUNTER"
seconds="$CURL_SECONDS"; [ -n "$seconds" ] || seconds=0
[ "$seconds" -le "$limit" ] || seconds="$limit"
clock=$(cat "$CLOCK"); echo $((clock + seconds)) > "$CLOCK"
code=200; body=healthy; status=0
case "$MODE" in
  late) [ "$n" -gt 25 ] || { code=503; body=warming; } ;;
  refused) code=503; body=api-timeout ;;
  transport) [ "$n" -gt 1 ] || { code=000; body=''; status=7; } ;;
  partial) [ "$n" -gt 1 ] || { status=28; } ;;
  iisnode) [ "$n" -gt 1 ] || body='iisnode encountered an error' ;;
esac
printf '%s' "$body" > "$out"
printf '%s' "$code"
exit "$status"
`;
const az = `#!/usr/bin/env bash
echo "az $*" >> "$CALLS"
case "$*" in
  *publishingUserName*) echo fake-user ;;
  *publishingPassword*) echo fake-password ;;
  'webapp config show '*) [ "$MODE" = windows ] || echo 'NODE|20-lts' ;;
  'webapp deploy '*) touch "$POSTED"; echo '{}' ;;
esac
exit 0
`;

function run(script, overrides = {}, setup = () => {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'appservice-health-test-'));
  try {
    fs.mkdirSync(path.join(root, 'bin'));
    for (const [name, text] of Object.entries({ curl, az,
      jq: `#!/usr/bin/env bash
node -e 'const fs=require("node:fs"); const field=process.argv[1].match(/\\.(\\w+)/)[1]; const data=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); console.log(data[field] ?? (field==="id" || field==="status_text" ? "" : "<unknown>"));' "$2" "$3"
`,
      unzip: '#!/usr/bin/env bash\necho server.js\nif [ "$PARTIAL_PACKAGE" != true ]; then printf ".next/BUILD_ID\\nnode_modules/fixture/index.js\\n"; fi\n',
      date: '#!/usr/bin/env bash\ncat "$CLOCK"\n',
      sleep: '#!/usr/bin/env bash\necho "sleep $*" >> "$CALLS"\nn=$(cat "$CLOCK"); echo $((n + $1)) > "$CLOCK"\n',
    })) fs.writeFileSync(path.join(root, 'bin', name), text, { mode: 0o755 });
    for (const name of ['clock', 'counter']) fs.writeFileSync(path.join(root, name), '0');
    fs.writeFileSync(path.join(root, 'calls'), '');
    fs.writeFileSync(path.join(root, 'package.zip'), 'synthetic package');
    fs.copyFileSync(path.join(__dirname, 'clean-node-runtime.sh'), path.join(root, 'clean-node-runtime.sh'));
    setup(root);
    fs.writeFileSync(path.join(root, 'run.sh'), `export PATH="${unix(root)}/bin:$PATH"\n${script}`);
    const result = spawnSync(bash, [unix(path.join(root, 'run.sh'))], {
      cwd: root, encoding: 'utf8', windowsHide: true, timeout: 60000,
      env: { ...process.env, MODE: 'ready', RUNNER_TEMP: unix(root), CALLS: unix(path.join(root, 'calls')),
        CLOCK: unix(path.join(root, 'clock')), COUNTER: unix(path.join(root, 'counter')),
        POSTED: unix(path.join(root, 'posted')), WARMUP_LABEL: 'production',
        WARMUP_URL: 'https://health.invalid/healthz?deep=true', WARMUP_TIMEOUT_MINUTES: '1',
        RG: 'fixture-rg', APP: 'fixture-app', PACKAGE: unix(path.join(root, 'package.zip')),
        DEPLOY_TIMEOUT_MINUTES: '1', SCM_SETTLE_SECONDS: '0', ...overrides },
    });
    return { ...result, calls: fs.readFileSync(path.join(root, 'calls'), 'utf8'),
      attempts: Number(fs.readFileSync(path.join(root, 'counter'), 'utf8')),
      clock: Number(fs.readFileSync(path.join(root, 'clock'), 'utf8')),
      failed: fs.existsSync(path.join(root, 'warmup_fail.txt')),
      deployFailed: fs.existsSync(path.join(root, 'deploy_fail.txt')),
      cleanupRequest: fs.existsSync(path.join(root, '_logs/production-cleanup-request.json'))
        ? JSON.parse(fs.readFileSync(path.join(root, '_logs/production-cleanup-request.json'), 'utf8')) : null,
      body: fs.existsSync(path.join(root, '_logs/warmup-production-body.txt'))
        ? fs.readFileSync(path.join(root, '_logs/warmup-production-body.txt'), 'utf8') : null };
  } finally {
    assert.ok(path.resolve(root).startsWith(path.resolve(os.tmpdir()) + path.sep));
    assert.ok(path.basename(root).startsWith('appservice-health-test-'));
    fs.rmSync(root, { recursive: true, force: true });
  }
}
const health = fs.readFileSync(path.join(__dirname, 'wait-for-health.sh'), 'utf8');
const deploy = fs.readFileSync(path.join(__dirname, 'deploy-package.sh'), 'utf8');

test('accepts a complete 200 with exactly one request and no restart', () => {
  const result = run(health);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.failed, false);
  assert.equal(result.attempts, 1);
  assert.equal(result.body, 'healthy');
  assert.doesNotMatch(result.calls, /az /);
});

test('allows a cold start beyond the old twenty-attempt limit', () => {
  const result = run(health, { MODE: 'late', WARMUP_TIMEOUT_MINUTES: '20', CURL_SECONDS: '1' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.failed, false);
  assert.equal(result.attempts, 26);
  assert.doesNotMatch(result.calls, /az /);
});

for (const mode of ['transport', 'partial', 'iisnode']) test(`does not accept ${mode} as readiness`, () => {
  const result = run(health, { MODE: mode });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.failed, false);
  assert.equal(result.attempts, 2);
  assert.match(result.stdout, /attempt 1/);
  assert.doesNotMatch(result.stdout, /000000/);
});

test('stops at the wall-clock budget and retains the failing response for diagnostics', () => {
  const result = run(health, { MODE: 'refused', CURL_SECONDS: '10' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.failed, true);
  assert.equal(result.clock, 60);
  assert.equal(result.attempts, 4);
  assert.equal(result.body, 'api-timeout');
  assert.doesNotMatch(result.calls, /az /);
});

for (const marker of ['deploy_fail.txt', 'warmup_fail.txt']) test(`does not probe after ${marker}`, () => {
  const result = run(health, {}, root => fs.writeFileSync(path.join(root, marker), 'earlier failure'));
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.attempts, 0);
});

for (const value of ['0', '61', 'invalid']) test(`refuses invalid timeout ${value}`, () => {
  const result = run(health, { WARMUP_TIMEOUT_MINUTES: value });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.failed, true);
  assert.equal(result.attempts, 0);
});

test('Linux zipdeploy refreshes artifact files and leaves its automatic restart alone', () => {
  const result = run(deploy, { MODE: 'deploy' });
  assert.equal(result.status, 0, result.stderr + result.stdout + result.calls);
  assert.equal(result.deployFailed, false);
  assert.match(result.stdout, /Package deployment completed/);
  assert.match(result.calls, /SCM_ZIPDEPLOY_DONOT_PRESERVE_FILETIME=1/);
  assert.doesNotMatch(result.calls, /az webapp restart/);
});

test('the Windows OneDeploy path retains its single requested restart', () => {
  const result = run(deploy, { MODE: 'windows' });
  assert.equal(result.status, 0, result.stderr + result.stdout + result.calls);
  assert.equal(result.deployFailed, false);
  assert.match(result.calls, /az webapp deploy .*--restart true/);
  assert.doesNotMatch(result.calls, /SCM_ZIPDEPLOY_DONOT_PRESERVE_FILETIME|az webapp restart/);
});

test('opt-in cleanup precedes upload and is scoped to the application root', () => {
  const result = run(deploy, { MODE: 'deploy', CLEAN_NODE_RUNTIME: 'true' });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  assert.equal(result.deployFailed, false);
  assert.equal(result.cleanupRequest.dir, '/home/site/wwwroot');
  const encoded = result.cleanupRequest.command.match(/printf %s ([A-Za-z0-9+/=]+)/)[1];
  assert.match(Buffer.from(encoded, 'base64').toString(), /clean_node_runtime \/home\/site\/wwwroot/);
  assert.ok(result.calls.indexOf('/api/command') < result.calls.indexOf('/api/zipdeploy'));
  assert.doesNotMatch(result.calls, /az webapp restart/);
});

test('a cleanup refusal stops upload and retains the deployment failure marker', () => {
  const result = run(deploy, { MODE: 'deploy', CLEAN_NODE_RUNTIME: 'true', CLEANUP_FAIL: 'true' });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  assert.equal(result.deployFailed, true);
  assert.match(result.calls, /\/api\/command/);
  assert.doesNotMatch(result.calls, /\/api\/zipdeploy/);
});

test('incomplete packages cannot trigger remote cleanup or upload', () => {
  const result = run(deploy, { MODE: 'deploy', CLEAN_NODE_RUNTIME: 'true', PARTIAL_PACKAGE: 'true' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.deployFailed, true);
  assert.doesNotMatch(result.calls, /az |curl /);
});

test('opt-in cleanup refuses a Windows or unidentified app', () => {
  const result = run(deploy, { MODE: 'windows', CLEAN_NODE_RUNTIME: 'true' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.deployFailed, true);
  assert.doesNotMatch(result.calls, /\/api\/command|\/api\/zipdeploy|az webapp deploy /);
});

const swapBlock = action.split('    - name: Swap slots (staging -> production)')[1].split('    - name: ')[0];
const swap = swapBlock.split('      run: |')[1].split(/\r?\n/)
  .map(line => line.replace(/^        /, '')).join('\n').replace(/\$\{\{[^}]+\}\}/g, 'fixture');
test('failed staging health cannot swap traffic', () => {
  const result = run(swap, {}, root => fs.writeFileSync(path.join(root, 'warmup_fail.txt'), 'staging timeout'));
  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.calls, /az /);
});
test('healthy staging can still swap once', () => {
  const result = run(swap);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.trim().split('\n').length, 1);
  assert.match(result.calls, /az webapp deployment slot swap/);
});

test('phase wiring uses the helper and only warms production again after an actual swap', () => {
  assert.equal((action.match(/run: bash "\$\{\{ github.action_path \}\}\/wait-for-health.sh"/g) || []).length, 3);
  for (const label of ['staging', 'production', 'final']) assert.match(action, new RegExp(`WARMUP_LABEL: ${label}`));
  assert.match(action.split('    - name: Final warm up production')[1],
    /if: inputs.use-slot == 'true' && inputs.skip-swap != 'true' && inputs.warmup-url-prod != ''/);
});
