'use strict';
// Reuse the caller's tested Microsoft authorization-code + PKCE browser helper.
// Tokens only enter GitHub's masked environment file, never a job output/artifact.
const fs = require('node:fs');
const path = require('node:path');

function optionsFromEnvironment(env) {
  const required = ['EXTERNAL_ID_AUTHORITY', 'SMOKE_CLIENT_ID', 'SMOKE_CLIENT_SECRET', 'TEST_USER_EMAIL', 'TEST_USER_PASSWORD', 'EXTERNAL_ID_SCOPE'];
  for (const key of required) if (!env[key]) throw new Error(`Missing ${key} for External ID browser verification.`);
  const authority = new URL(env.EXTERNAL_ID_AUTHORITY);
  if (authority.protocol !== 'https:' || !authority.hostname.endsWith('.ciamlogin.com') ||
      !/^\/[0-9a-f-]{36}\/v2\.0\/?$/i.test(authority.pathname) || authority.username || authority.password || authority.search || authority.hash) {
    throw new Error('Invalid External ID authority.');
  }
  return { authority: authority.href, clientId: env.SMOKE_CLIENT_ID, clientSecret: env.SMOKE_CLIENT_SECRET,
    username: env.TEST_USER_EMAIL, password: env.TEST_USER_PASSWORD, scope: env.EXTERNAL_ID_SCOPE };
}

async function mint(env, acquire, emit = console.log) {
  const options = optionsFromEnvironment(env);
  if (!env.GITHUB_ENV || !path.isAbsolute(env.GITHUB_ENV)) throw new Error('An absolute GitHub environment file is required.');
  const token = await acquire(options);
  if (typeof token !== 'string' || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token)) throw new Error('Invalid token result.');
  emit('::add-mask::' + token);
  fs.appendFileSync(env.GITHUB_ENV, `B2C_ACCESS_TOKEN=${token}\n`, { mode: 0o600 });
  emit('Microsoft External ID authorization-code/PKCE smoke token acquired and validated.');
}

async function main() {
  try {
    // Reject missing configuration before loading caller code or opening a browser.
    optionsFromEnvironment(process.env);
    const workspace = path.resolve(process.env.GITHUB_WORKSPACE || '.');
    const caller = path.resolve(workspace, process.env.CALLER_WORKDIR || 'caller');
    if (!caller.startsWith(workspace + path.sep)) throw new Error('Invalid caller checkout.');
    const helper = require(path.join(caller, 'tools/e2e/external-id-browser-token.cjs'));
    await mint(process.env, helper.acquireBrowserToken);
  } catch {
    // Playwright errors can contain entered values. Never echo their details.
    console.error('External ID protected smoke sign-in failed. Check smoke client secret, test account, callback and browser setup.');
    process.exitCode = 1;
  }
}
if (require.main === module) main();
module.exports = { optionsFromEnvironment, mint };
