const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { mint, optionsFromEnvironment } = require('./mint-external-id-smoke.cjs');
const base = { EXTERNAL_ID_AUTHORITY: 'https://productdev.ciamlogin.com/827fbdd5-4eda-4949-a365-adb11a0cee2f/v2.0',
  SMOKE_CLIENT_ID: 'smoke-client', SMOKE_CLIENT_SECRET: 'test-client-secret', TEST_USER_EMAIL: 'test@example.invalid',
  TEST_USER_PASSWORD: 'test-password', EXTERNAL_ID_SCOPE: 'api://resource/access_as_user openid' };

test('forwards confidential-client credentials and delegated scope to the browser helper', () => {
  const options = optionsFromEnvironment(base);
  assert.equal(options.clientSecret, base.SMOKE_CLIENT_SECRET);
  assert.equal(options.clientId, base.SMOKE_CLIENT_ID);
  assert.equal(options.scope, base.EXTERNAL_ID_SCOPE);
  assert.equal(options.username, base.TEST_USER_EMAIL);
  assert.equal(options.password, base.TEST_USER_PASSWORD);
});
for (const key of ['SMOKE_CLIENT_SECRET', 'TEST_USER_PASSWORD', 'SMOKE_CLIENT_ID']) {
  test(`missing ${key} fails before browser acquisition`, async () => {
    let called = false;
    await assert.rejects(mint({ ...base, [key]: '' }, async () => { called = true; }), /Missing/);
    assert.equal(called, false);
  });
}
for (const authority of ['https://old.b2clogin.com/tenant/policy/v2.0', 'http://productdev.ciamlogin.com/tenant/v2.0',
  'https://productdev.ciamlogin.com.evil.invalid/827fbdd5-4eda-4949-a365-adb11a0cee2f/v2.0']) {
  test(`rejects invalid authority ${authority}`, () => {
    assert.throws(() => optionsFromEnvironment({ ...base, EXTERNAL_ID_AUTHORITY: authority }), /Invalid External ID authority/);
  });
}
test('masks token before writing it to job environment; no token job output', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'external-id-smoke-'));
  try {
    const output = path.join(directory, 'env');
    const emitted = [];
    const token = 'header.payload.signature';
    await mint({ ...base, GITHUB_ENV: output }, async () => token, line => {
      if (line.startsWith('::add-mask::')) assert.equal(fs.existsSync(output), false);
      emitted.push(line);
    });
    assert.equal(emitted[0], '::add-mask::' + token);
    assert.equal(emitted.filter(x => x.includes(token)).length, 1);
    assert.equal(fs.readFileSync(output, 'utf8'), `B2C_ACCESS_TOKEN=${token}\n`);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
test('failed browser acquisition does not write a token', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'external-id-smoke-'));
  try {
    const output = path.join(directory, 'env');
    await assert.rejects(mint({ ...base, GITHUB_ENV: output }, async () => { throw new Error('sign-in failed'); }));
    assert.equal(fs.existsSync(output), false);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
test('rejects token results that could inject extra environment values', async () => {
  await assert.rejects(mint({ ...base, GITHUB_ENV: path.resolve('unused-env') }, async () => 'token\nUNSAFE=1'), /Invalid token result/);
});
