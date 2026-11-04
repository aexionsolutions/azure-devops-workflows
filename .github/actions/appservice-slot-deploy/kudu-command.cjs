const fs = require('node:fs');

// Kudu's Linux starter executes argv directly (exec "$@"). A bare pipe is
// therefore an argument to printf, not a shell pipeline. Request Bash explicitly.
function request(script) {
  const encoded = Buffer.from(script).toString('base64');
  return { command: `bash -c "export KUDU_COMMAND_PARENT=$PPID; printf %s ${encoded} | base64 -d | bash"`, dir: '/home/site/wwwroot' };
}

function result(raw, kind) {
  const response = typeof raw === 'string' ? JSON.parse(raw) : raw;
  if (response?.ExitCode !== 0 || typeof response.Output !== 'string' ||
      typeof response.Error !== 'string' || response.Error.trim()) throw new Error('Kudu command failed or returned an invalid result');
  const lines = response.Output.trim().split(/\r?\n/);
  const last = lines.at(-1);
  if (kind === 'cleanup' && last === 'APP_SERVICE_NODE_CLEANUP_COMPLETE') return last;
  if (kind === 'identity' && /^SCM_PROCESS:[1-9][0-9]*:[0-9]+$/.test(last)) return last;
  throw new Error('Kudu command did not confirm completion');
}

const identityScript = `#!/usr/bin/env bash
set -euo pipefail
# The outer Bash captures its parent (Kudu), before starting this pipeline. Include
# process start ticks as well as PID, since a replacement can reuse a PID.
parent="\${KUDU_COMMAND_PARENT:?Missing command executor identity}"
stat=$(cat "/proc/$parent/stat")
fields="\${stat##*) }"
read -ra values <<< "$fields"
printf 'SCM_PROCESS:%s:%s\\n' "$parent" "\${values[19]}"
`;

module.exports = { request, result, identityScript };
if (require.main === module) {
  try {
    if (process.argv[2] === 'request') process.stdout.write(JSON.stringify(request(fs.readFileSync(process.argv[3]))));
    else if (process.argv[2] === 'result') console.log(result(fs.readFileSync(process.argv[3], 'utf8'), process.argv[4]));
    else throw new Error('Unknown Kudu command operation');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
