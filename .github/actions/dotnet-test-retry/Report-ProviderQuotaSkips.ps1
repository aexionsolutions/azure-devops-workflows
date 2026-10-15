<#
.SYNOPSIS
  Reports the tests that did not run because a provider's quota was exhausted (see TrxSelection.ps1).
.DESCRIPTION
  Runs after Invoke-SmartTestRetry.ps1 whatever its outcome. A quota skip is neither retried nor counted as a
  failure, so without this report it would read as coverage: it is listed in the job summary, raised as a warning
  annotation and returned as the provider-quota-skipped-count output.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'TrxSelection.ps1')

$resultsDir = $env:INPUT_RESULTS_DIRECTORY
$trxPrefix  = $env:INPUT_TRX_FILENAME_PREFIX

$skipped = New-Object System.Collections.Generic.List[string]
$attempts = @(Get-ChildItem -Path $resultsDir -Filter ('{0}-*.trx' -f $trxPrefix) -ErrorAction SilentlyContinue)
foreach ($trx in $attempts) {
  foreach ($name in @(Get-ProviderQuotaSkippedFQNsFromTrx $trx.FullName)) {
    if (-not [string]::IsNullOrWhiteSpace($name)) { $skipped.Add($name) }
  }
}
$skipped = @($skipped | Sort-Object -Unique)

('provider-quota-skipped-count={0}' -f $skipped.Count) >> $env:GITHUB_OUTPUT
if ($skipped.Count -eq 0) { exit 0 }

Write-Host ('⚠️ {0} test(s) did not run: a provider quota was exhausted. They are not failures, and they gave no coverage:' -f $skipped.Count)
$skipped | ForEach-Object { Write-Host ('   - {0}' -f $_) }
Write-Host ('::warning title=Provider quota exhausted::{0} test(s) did not run because a provider quota was exhausted; they gave no coverage. See the job summary.' -f $skipped.Count)
if ($env:GITHUB_STEP_SUMMARY) {
  @(
    ''
    ('### ⚠️ {0} test(s) not run: provider quota exhausted' -f $skipped.Count)
    'Not failures, and no coverage from them:'
    ($skipped | ForEach-Object { '- `{0}`' -f $_ })
  ) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
exit 0
