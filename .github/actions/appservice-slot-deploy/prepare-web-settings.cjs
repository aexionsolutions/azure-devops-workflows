const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const kudu = require('./kudu-command.cjs');

function desired(env, slot, linux, deployTarget) {
  const settings = {};
  if (env.VERSION) Object.assign(settings, { BUILD_VERSION: env.VERSION, ENV: env.DEPLOY_ENV });
  const authority = env.B2C_AUTHORITY || '';
  const client = env.B2C_WEB_CLIENT_ID || env.B2C_CLIENT_ID || '';
  const scope = env.B2C_SCOPE || '';
  if (authority || client || scope) {
    if (!authority || !client || !scope) throw new Error('Incomplete B2C web auth configuration');
    const origin = !slot && env.WEB_BASE_URL ? env.WEB_BASE_URL : `https://${env.APP}${slot ? '-staging' : ''}.azurewebsites.net`;
    if (!/^https:\/\/[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]+)?$/.test(origin)) throw new Error('web_base_url must be an HTTPS origin');
    for (const prefix of ['AAD_', 'NEXT_PUBLIC_AAD_', 'AAD_B2C_', 'NEXT_PUBLIC_AAD_B2C_']) {
      Object.assign(settings, { [prefix + 'AUTHORITY']: authority, [prefix + 'CLIENT_ID']: client,
        [prefix + 'API_SCOPE']: scope, [prefix + 'REDIRECT_URI']: origin + '/auth/callback' });
    }
  }
  const remove = [];
  if (deployTarget) {
    // The Linux deployment path extracts the standalone zip, as before.
    if (linux) Object.assign(settings, { SCM_DO_BUILD_DURING_DEPLOYMENT: 'false', SCM_ZIPDEPLOY_DONOT_PRESERVE_FILETIME: '1' });
    if (!linux && env.RFP === 'true') settings.WEBSITE_RUN_FROM_PACKAGE = '1';
    else remove.push('WEBSITE_RUN_FROM_PACKAGE');
  }
  return { settings, remove };
}

function changes(current, plan) {
  if (!Array.isArray(current) || current.some(x => typeof x.name !== 'string')) throw new Error('Invalid App Service settings response');
  const values = new Map(current.map(x => [x.name, x.value]));
  return { set: Object.entries(plan.settings).filter(([key, value]) => values.get(key) !== value),
    remove: plan.remove.filter(key => values.has(key)) };
}

async function waitForReplacement(before, io, timeoutMs = 600000) {
  const deadline = io.now() + timeoutMs;
  let observed = null;
  let stableSince = 0;
  while (io.now() < deadline) {
    let identity;
    try { identity = await io.identity(Math.min(30000, deadline - io.now())); } catch { identity = null; }
    if (identity && identity !== before) {
      if (identity !== observed) { observed = identity; stableSince = io.now(); }
      if (io.now() - stableSince >= 10000) return identity;
    } else { observed = null; stableSince = 0; }
    await io.sleep(Math.min(5000, Math.max(0, deadline - io.now())));
  }
  throw new Error('SCM did not confirm a stable replacement after settings changed; package upload is blocked');
}

async function prepareTarget(plan, io, linux) {
  if (!Object.keys(plan.settings).length && !plan.remove.length) { io.ready(); return 'unchanged'; }
  const delta = changes(await io.read(Object.keys(plan.settings).concat(plan.remove)), plan);
  // Capture before the first mutation; an HTTP 200 from the old SCM process is
  // not proof that its queued settings recycle has completed.
  let before = null;
  if (linux) {
    const deadline = io.now() + 600000;
    while (io.now() < deadline) {
      try { before = await io.identity(Math.min(30000, deadline - io.now())); break; } catch { /* SCM may still be starting. */ }
      await io.sleep(Math.min(5000, Math.max(0, deadline - io.now())));
    }
    if (!before) throw new Error('SCM is unavailable before settings preparation; package upload is blocked');
  }
  if (!delta.set.length && !delta.remove.length) { io.ready(); return 'unchanged'; }
  if (delta.set.length) {
    await io.set(delta.set);
    if (linux) before = await waitForReplacement(before, io);
  }
  // Removing run-from-package is a separate ARM mutation. Observe its own
  // recycle, rather than accepting an earlier set operation's replacement
  // while this second recycle is still queued.
  if (delta.remove.length) {
    await io.remove(delta.remove);
    if (linux) await waitForReplacement(before, io);
  }
  const remaining = changes(await io.read(Object.keys(plan.settings).concat(plan.remove)), plan);
  if (remaining.set.length || remaining.remove.length) throw new Error('App Service settings did not match after preparation');
  io.ready();
  return 'changed';
}

function mainIo(env, slot, marker, linux) {
  const slotArgs = slot ? ['--slot', slot] : [];
  const base = ['-g', env.RG, '-n', env.APP, ...slotArgs];
  const execute = (program, args, input, timeout = 60000) => {
    const r = spawnSync(program, args, { encoding: 'utf8', input, timeout, windowsHide: true, maxBuffer: 4 * 1024 * 1024 });
    // Do not echo stdout, stderr, command arguments or configuration values.
    if (r.error || r.status !== 0) throw new Error(`${program} failed during settings preparation (exit ${r.status ?? 'unavailable'})`);
    return r.stdout;
  };
  let credentials;
  function identity(timeout) {
    if (!credentials) {
      credentials = JSON.parse(execute('az', ['webapp', 'deployment', 'list-publishing-credentials', ...base, '-o', 'json']));
      if (!credentials.publishingUserName || !credentials.publishingPassword) throw new Error('SCM credentials unavailable');
      console.log(`::add-mask::${credentials.publishingUserName}`);
      console.log(`::add-mask::${credentials.publishingPassword}`);
    }
    const host = `https://${env.APP}${slot ? '-' + slot : ''}.scm.azurewebsites.net`;
    const raw = execute('curl', ['-fsS', '--connect-timeout', '5', '--max-time', String(Math.max(1, Math.floor(timeout / 1000))),
      '-u', `${credentials.publishingUserName}:${credentials.publishingPassword}`, '-H', 'Content-Type: application/json',
      '--data-binary', '@-', host + '/api/command'], JSON.stringify(kudu.request(kudu.identityScript)), timeout + 1000);
    return kudu.result(raw, 'identity');
  }
  return {
    ensureStarted: () => {
      const state = execute('az', ['webapp', 'show', ...base, '--query', 'state', '-o', 'tsv']).trim();
      if (state === 'Stopped') execute('az', ['webapp', 'start', ...base, '--output', 'none']);
      else if (state !== 'Running') throw new Error('Target is not in a known Running or Stopped state');
    },
    read: keys => {
      if (keys.some(key => !/^[A-Z0-9_]+$/.test(key))) throw new Error('Invalid settings key');
      const query = `[?${keys.map(key => `name=='${key}'`).join(' || ')}].{name:name,value:value}`;
      return JSON.parse(execute('az', ['webapp', 'config', 'appsettings', 'list', ...base, '--query', query, '-o', 'json']));
    },
    set: pairs => execute('az', ['webapp', 'config', 'appsettings', 'set', ...base, '--settings', ...pairs.map(([key, value]) => key + '=' + value), '--output', 'none']),
    remove: keys => execute('az', ['webapp', 'config', 'appsettings', 'delete', ...base, '--setting-names', ...keys, '--output', 'none']),
    identity, now: Date.now, sleep: ms => new Promise(resolve => setTimeout(resolve, ms)),
    ready: () => { if (linux) fs.writeFileSync(marker, 'settings prepared and SCM ready\n'); },
  };
}

async function main(env) {
  if (!env.RG || !/^[A-Za-z0-9-]+$/.test(env.APP || '') || !env.RUNNER_TEMP) throw new Error('Missing or invalid deployment environment');
  const targets = env.USE_SLOT === 'true' ? ['staging', ''] : [''];
  const plans = [];
  for (const slot of targets) {
    const marker = path.join(env.RUNNER_TEMP, `appservice-${env.APP}-${slot || 'production'}-settings-ready`);
    fs.rmSync(marker, { force: true });
    const args = ['webapp', 'config', 'show', '-g', env.RG, '-n', env.APP, ...(slot ? ['--slot', slot] : []), '--query', 'linuxFxVersion', '-o', 'tsv'];
    const runtime = spawnSync('az', args, { encoding: 'utf8', timeout: 60000, windowsHide: true });
    if (runtime.error || runtime.status !== 0) throw new Error('Cannot determine target runtime');
    const linux = Boolean(runtime.stdout.trim());
    const deployTarget = slot === 'staging' || targets.length === 1;
    // Validate before any target mutation, including partial auth configuration.
    const plan = desired(env, slot, linux, deployTarget);
    plans.push({ slot, marker, linux, deployTarget, plan });
  }
  for (const { slot, marker, linux, deployTarget, plan } of plans) {
    const io = mainIo(env, slot, marker, linux && deployTarget);
    // All start/config operations finish before the identity gate and upload.
    io.ensureStarted();
    const outcome = await prepareTarget(plan, io, linux);
    console.log(`Web settings prepared for ${slot || 'production'} (${outcome}); no values logged.`);
  }
}

module.exports = { desired, changes, waitForReplacement, prepareTarget };
if (require.main === module) main(process.env).catch(error => { console.error(error.message); process.exitCode = 1; });
