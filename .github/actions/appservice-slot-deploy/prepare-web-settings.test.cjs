const { test } = require('node:test');
const assert = require('node:assert/strict');
const { desired, prepareTarget, waitForReplacement } = require('./prepare-web-settings.cjs');

function fixture(initial = {}, identities = ['old', 'new', 'new', 'new']) {
  const state = { current: { ...initial }, clock: 0, calls: [], ready: false };
  let n = 0;
  const io = {
    read: async () => { state.calls.push('read'); return Object.entries(state.current).map(([name, value]) => ({ name, value })); },
    set: async pairs => { state.calls.push('set'); Object.assign(state.current, Object.fromEntries(pairs)); },
    remove: async keys => { state.calls.push('remove'); keys.forEach(key => delete state.current[key]); },
    identity: async () => { state.calls.push('identity'); const value = identities[Math.min(n++, identities.length - 1)]; if (value instanceof Error) throw value; return value; },
    now: () => state.clock, sleep: async ms => { state.clock += ms; }, ready: () => { state.ready = true; state.calls.push('ready'); },
  };
  return { state, io };
}

test('unchanged settings do not write or trigger a recycle', async () => {
  const { state, io } = fixture({ BUILD_VERSION: '0.0.36' });
  assert.equal(await prepareTarget({ settings: { BUILD_VERSION: '0.0.36' }, remove: ['WEBSITE_RUN_FROM_PACKAGE'] }, io, true), 'unchanged');
  assert.deepEqual(state.calls, ['read', 'identity', 'ready']);
});

test('changed settings are batched and only a replacement SCM process unlocks upload', async () => {
  const { state, io } = fixture({ WEBSITE_RUN_FROM_PACKAGE: '1' }, ['old', 'old', new Error('recycling'), 'new', 'new', 'new']);
  await prepareTarget({ settings: { BUILD_VERSION: 'new', ENV: 'dev' }, remove: ['WEBSITE_RUN_FROM_PACKAGE'] }, io, true);
  assert.equal(state.ready, true);
  assert.equal(state.calls.filter(x => x === 'set').length, 1);
  assert.ok(state.calls.indexOf('identity') < state.calls.indexOf('set'));
  assert.ok(state.clock >= 20000);
  assert.equal(state.current.WEBSITE_RUN_FROM_PACKAGE, undefined);
});

test('a delayed recycle beyond the old 45-second delay is awaited', async () => {
  const { state, io } = fixture({}, [...Array(44).fill('old'), 'new', 'new', 'new']);
  await waitForReplacement('old', io);
  assert.ok(state.clock >= 225000);
});

test('a second restart resets the stability window', async () => {
  const { state, io } = fixture({}, ['new', 'new', 'replacement', 'replacement', 'replacement']);
  await waitForReplacement('old', io);
  assert.equal(state.clock, 20000);
});

test('an old or unavailable SCM process never unlocks deployment', async () => {
  for (const identity of ['old', new Error('unavailable')]) {
    const { state, io } = fixture({}, [identity]);
    await assert.rejects(waitForReplacement('old', io, 60000), /upload is blocked/);
    assert.equal(state.ready, false);
    assert.equal(state.clock, 60000);
  }
});

test('failed settings writes cannot produce a readiness marker', async () => {
  const { state, io } = fixture();
  io.set = async () => { throw new Error('write refused'); };
  await assert.rejects(prepareTarget({ settings: { ENV: 'dev' }, remove: [] }, io, true), /write refused/);
  assert.equal(state.ready, false);
});

test('Windows does not use the Linux SCM command protocol', async () => {
  const { state, io } = fixture();
  await prepareTarget({ settings: { ENV: 'dev' }, remove: [] }, io, false);
  assert.equal(state.ready, true);
  assert.ok(!state.calls.includes('identity'));
});

test('web settings preserve all auth aliases and target-specific callback origins', () => {
  const env = { APP: 'fixture-web', VERSION: '0.0.36', DEPLOY_ENV: 'dev', B2C_AUTHORITY: 'https://identity.invalid',
    B2C_CLIENT_ID: 'fallback-client', B2C_SCOPE: 'api://scope', WEB_BASE_URL: 'https://dev.example.com' };
  const prod = desired(env, '', true, true);
  const staging = desired({ ...env, B2C_WEB_CLIENT_ID: 'web-client' }, 'staging', true, true);
  for (const prefix of ['AAD_', 'NEXT_PUBLIC_AAD_', 'AAD_B2C_', 'NEXT_PUBLIC_AAD_B2C_']) {
    assert.equal(prod.settings[prefix + 'REDIRECT_URI'], 'https://dev.example.com/auth/callback');
    assert.equal(prod.settings[prefix + 'CLIENT_ID'], 'fallback-client');
    assert.equal(staging.settings[prefix + 'REDIRECT_URI'], 'https://fixture-web-staging.azurewebsites.net/auth/callback');
    assert.equal(staging.settings[prefix + 'CLIENT_ID'], 'web-client');
  }
  assert.equal(prod.settings.SCM_DO_BUILD_DURING_DEPLOYMENT, 'false');
  assert.ok(prod.remove.includes('WEBSITE_RUN_FROM_PACKAGE'));
  assert.equal(desired({ ...env, RFP: 'true' }, '', false, true).settings.WEBSITE_RUN_FROM_PACKAGE, '1');
  assert.equal(desired(env, '', true, false).settings.SCM_DO_BUILD_DURING_DEPLOYMENT, undefined);
});

test('partial auth and unsafe callback origins are rejected before planning a write', () => {
  assert.throws(() => desired({ APP: 'fixture', B2C_AUTHORITY: 'partial' }, '', true, true), /Incomplete/);
  assert.throws(() => desired({ APP: 'fixture', B2C_AUTHORITY: 'a', B2C_CLIENT_ID: 'b', B2C_SCOPE: 'c', WEB_BASE_URL: 'https://host/path' }, '', true, true), /HTTPS origin/);
});
