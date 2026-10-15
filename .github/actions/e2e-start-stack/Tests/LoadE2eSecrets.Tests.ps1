# Pester 5, Linux (runs the real bash script; needs jq and openssl, as on ubuntu runners).
BeforeAll {
  $script:LoadScript = Join-Path $PSScriptRoot '..' 'load-e2e-secrets.sh'

  # Runs the script with the given E2E_SECRETS_JSON. Returns its exit code, output lines and the GITHUB_ENV it wrote.
  function Invoke-LoadSecrets([string]$Json) {
    $envFile = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType File -Path $envFile | Out-Null
    $env:GITHUB_ENV = $envFile
    $env:E2E_SECRETS_JSON = $Json
    $output = @(& bash $script:LoadScript 2>&1 | ForEach-Object { "$_" })
    $exit = $LASTEXITCODE
    Remove-Item Env:E2E_SECRETS_JSON -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Exit = $exit; Output = $output; Env = (Get-Content $envFile -Raw) }
  }
}

Describe 'Loading E2E secrets (real script)' -Skip:(-not $IsLinux) {
  It 'masks a secret whose value looks like a flag: a value alone cannot tell a password from a flag' {
    $run = Invoke-LoadSecrets '{"DATABASE_PASSWORD":"false","RUN_PAYSTACK":"false"}'

    $run.Exit | Should -Be 0
    # Both keys share the value; it is masked (once per key) and never passed through unmasked.
    @($run.Output | Where-Object { $_ -eq '::add-mask::false' }) | Should -HaveCount 2
    $run.Output | Should -Not -Match 'not masked'
    $run.Env | Should -Match "DATABASE_PASSWORD<<EOF_[0-9a-f]+\nfalse\n"
  }

  It 'warns about a flag-like value, naming the key, so a non-secret flag can move to e2e_env_vars' {
    $run = Invoke-LoadSecrets '{"E2E_RUN_NOTIFICATIONS":"1"}'

    $run.Output | Should -Contain '::add-mask::1'
    @($run.Output | Where-Object { $_ -like '::warning title=Flag-like value in e2e_secrets::E2E_RUN_NOTIFICATIONS has a flag-like value*' }) | Should -HaveCount 1
  }

  It 'masks an ordinary secret without a warning' {
    $run = Invoke-LoadSecrets '{"PAYSTACK_TEST_SECRET_KEY":"sk_test_abc123","PORT":"10"}'

    $run.Output | Should -Contain '::add-mask::sk_test_abc123'
    $run.Output | Should -Contain '::add-mask::10'
    $run.Output | Should -Not -Match '::warning'
    $run.Env | Should -Match "PAYSTACK_TEST_SECRET_KEY<<EOF_[0-9a-f]+\nsk_test_abc123\n"
  }

  It 'does nothing for an empty or absent secrets object' {
    (Invoke-LoadSecrets '{}').Exit | Should -Be 0
    (Invoke-LoadSecrets '').Exit | Should -Be 0
  }

  It 'fails on invalid JSON' {
    (Invoke-LoadSecrets '{not json').Exit | Should -Be 1
  }
}
