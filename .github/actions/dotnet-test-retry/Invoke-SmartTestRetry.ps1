<#
.SYNOPSIS
  Smart .NET Test Retry — runs dotnet tests, retries only failed tests.
.DESCRIPTION
  Called from action.yml. All inputs are read from environment variables
  prefixed with INPUT_ (set by the action step).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

# Ensure PowerShell 7.3+ correctly quotes native command arguments
$PSNativeCommandArgumentPassing = 'Standard'

# Avoid literal pipe in the script text (some runner/masking combos cause parsing issues)
$PIPE = [char]124

# Inputs (set as env vars by action.yml)
$project        = $env:INPUT_PROJECT
$baseFilter     = $env:INPUT_FILTER
$maxAttempts    = [int]$env:INPUT_MAX_ATTEMPTS
$resultsDir     = $env:INPUT_RESULTS_DIRECTORY
$trxPrefix      = $env:INPUT_TRX_FILENAME_PREFIX
$config         = $env:INPUT_CONFIGURATION
$noBuild        = $env:INPUT_NO_BUILD
$additional     = $env:INPUT_ADDITIONAL_ARGS
$dryRunTrx      = $env:INPUT_DRY_RUN_TRX
$consoleVerb    = $env:INPUT_CONSOLE_VERBOSITY

Write-Host '🧪 Smart .NET Test Retry'
Write-Host ('   Project: {0}' -f $project)
Write-Host ('   Filter:  {0}' -f ($(if ([string]::IsNullOrWhiteSpace($baseFilter)) { 'none (all tests)' } else { $baseFilter })))
Write-Host ('   Max attempts: {0}' -f $maxAttempts)
Write-Host ('   Results directory: {0}' -f $resultsDir)
Write-Host ('   Console verbosity: {0}' -f $consoleVerb)

New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null

function Get-TrxPath([int]$attempt) {
  Join-Path $resultsDir ('{0}-{1}.trx' -f $trxPrefix, $attempt)
}

# TRX loading and retry selection (Load-Trx, Get-FailedFQNsFromTrx, provider-quota skips) live in their own file so
# Tests/TrxSelection.Tests.ps1 can check them against TRX fixtures.
. (Join-Path $PSScriptRoot 'TrxSelection.ps1')

function Get-TrxCounters([string]$trxPath) {
  if (-not (Test-Path $trxPath)) { return $null }
  try {
    $doc = Load-Trx $trxPath
    $counters = $doc.Xml.SelectSingleNode('//trx:ResultSummary/trx:Counters', $doc.Ns)
    if ($counters -eq $null) { return $null }

    # Read all counter attributes so totals always add up.
    # TRX Counters include: total, passed, failed, error, timeout,
    # aborted, inconclusive, notExecuted, completed, inProgress, etc.
    $h = @{
      total         = [int]$counters.GetAttribute('total')
      passed        = [int]$counters.GetAttribute('passed')
      failed        = [int]$counters.GetAttribute('failed')
      error         = [int]$counters.GetAttribute('error')
      aborted       = [int]$counters.GetAttribute('aborted')
      timeout       = [int]$counters.GetAttribute('timeout')
      notExecuted   = 0
      inconclusive  = 0
    }
    # These attributes may not exist in every TRX; guard with try/catch
    try { $h.notExecuted  = [int]$counters.GetAttribute('notExecuted') }  catch {}
    try { $h.inconclusive = [int]$counters.GetAttribute('inconclusive') } catch {}
    return $h
  }
  catch {
    Write-Host "⚠️ Error parsing TRX counters: ${_}"
    return $null
  }
}

function Get-TrxSummary([string]$trxPath) {
  if (-not (Test-Path $trxPath)) { return $null }
  try {
    $doc = Load-Trx $trxPath
    $counters = $doc.Xml.SelectSingleNode('//trx:ResultSummary/trx:Counters', $doc.Ns)
    if ($counters -eq $null) { return $null }

    $h = @{
      total   = $counters.GetAttribute('total')
      passed  = $counters.GetAttribute('passed')
      failed  = $counters.GetAttribute('failed')
      error   = $counters.GetAttribute('error')
      aborted = $counters.GetAttribute('aborted')
      timeout = $counters.GetAttribute('timeout')
      notExecuted  = '0'
      inconclusive = '0'
    }
    $ne = $counters.GetAttribute('notExecuted')
    if (-not [string]::IsNullOrWhiteSpace($ne)) { $h.notExecuted = $ne }
    $ic = $counters.GetAttribute('inconclusive')
    if (-not [string]::IsNullOrWhiteSpace($ic)) { $h.inconclusive = $ic }
    return $h
  }
  catch {
    Write-Host ("⚠️ Error parsing TRX summary: {0}" -f $_.Exception.Message)
    return $null
  }
}

function Merge-TrxResults([string]$baseTrxPath, [int]$totalAttempts) {
  # Produces a merged TRX that starts from the first attempt (full suite)
  # and overwrites results for retried tests with their latest outcome.
  # This fixes GitHub's test-results tab double-counting across TRX files.
  
  if ($totalAttempts -le 1) { return }
  
  $mergedPath = Join-Path $resultsDir ('{0}-merged.trx' -f $trxPrefix)
  
  try {
    $baseDoc = Load-Trx $baseTrxPath
    $baseXml = $baseDoc.Xml
    $baseNs  = $baseDoc.Ns

    # Build lookup: testName -> latest UnitTestResult node from retry TRXes. A later skip never replaces an earlier
    # failure (Test-ReplacesEarlierResult): a test that failed and was then skipped stays failed, with its evidence.
    $earlierOutcomes = @{}
    foreach ($node in $baseXml.SelectNodes('//trx:Results/trx:UnitTestResult', $baseNs)) {
      $earlierOutcomes[$node.GetAttribute('testName')] = $node.GetAttribute('outcome')
    }
    $latestResults = @{}
    for ($a = 2; $a -le $totalAttempts; $a++) {
      $retryTrx = Get-TrxPath $a
      if (-not (Test-Path $retryTrx)) { continue }
      try {
        $retryDoc = Load-Trx $retryTrx
        $retryNodes = $retryDoc.Xml.SelectNodes('//trx:Results/trx:UnitTestResult', $retryDoc.Ns)
        foreach ($node in $retryNodes) {
          $tn = $node.GetAttribute('testName')
          if ([string]::IsNullOrWhiteSpace($tn)) { continue }
          if (-not (Test-ReplacesEarlierResult -EarlierOutcome $earlierOutcomes[$tn] -LaterOutcome $node.GetAttribute('outcome'))) { continue }
          $latestResults[$tn] = $node
          $earlierOutcomes[$tn] = $node.GetAttribute('outcome')
        }
      }
      catch {
        Write-Host ("   ⚠️ Could not parse retry TRX {0}: {1}" -f $retryTrx, $_.Exception.Message)
      }
    }

    if ($latestResults.Count -eq 0) {
      Write-Host '   ℹ️ No retry results to merge'
      return
    }

    # Overwrite matching results in base TRX
    $resultsNode = $baseXml.SelectSingleNode('//trx:Results', $baseNs)
    $baseResults = $baseXml.SelectNodes('//trx:Results/trx:UnitTestResult', $baseNs)
    $updatedCount = 0

    foreach ($baseResult in $baseResults) {
      $tn = $baseResult.GetAttribute('testName')
      if ($latestResults.ContainsKey($tn)) {
        $imported = $baseXml.ImportNode($latestResults[$tn], $true)
        $resultsNode.ReplaceChild($imported, $baseResult) | Out-Null
        $updatedCount++
      }
    }

    # Recalculate counters — track ALL outcome types so totals add up
    $allResults = $baseXml.SelectNodes('//trx:Results/trx:UnitTestResult', $baseNs)
    $total = $allResults.Count
    $passed = 0; $failed = 0; $errored = 0
    $notExecuted = 0; $inconclusive = 0; $aborted = 0; $timeout = 0
    $other = 0
    foreach ($r in $allResults) {
      switch ($r.GetAttribute('outcome')) {
        'Passed'       { $passed++ }
        'Failed'       { $failed++ }
        'Error'        { $errored++ }
        'NotExecuted'  { $notExecuted++ }
        'Inconclusive' { $inconclusive++ }
        'Aborted'      { $aborted++ }
        'Timeout'      { $timeout++ }
        default        { $other++; $passed++ }  # Completed, Warning, etc. → treat as passed
      }
    }
    if ($other -gt 0) {
      Write-Host ("   ℹ️ {0} test(s) with uncommon outcomes (Completed/Warning/etc.) counted as passed" -f $other)
    }
    $executed = $total - $notExecuted - $inconclusive

    $countersNode = $baseXml.SelectSingleNode('//trx:ResultSummary/trx:Counters', $baseNs)
    if ($countersNode) {
      $countersNode.SetAttribute('total', $total)
      $countersNode.SetAttribute('executed', $executed)
      $countersNode.SetAttribute('passed', $passed)
      $countersNode.SetAttribute('failed', $failed)
      $countersNode.SetAttribute('error', $errored)
      $countersNode.SetAttribute('notExecuted', $notExecuted)
      $countersNode.SetAttribute('inconclusive', $inconclusive)
      $countersNode.SetAttribute('aborted', $aborted)
      $countersNode.SetAttribute('timeout', $timeout)
    }

    # Update outcome
    $summaryNode = $baseXml.SelectSingleNode('//trx:ResultSummary', $baseNs)
    if ($summaryNode) {
      $summaryNode.SetAttribute('outcome', $(if ($failed -gt 0 -or $errored -gt 0) { 'Failed' } else { 'Passed' }))
    }

    $baseXml.Save($mergedPath)

    Write-Host ("   📊 Merged TRX: {0} (updated {1} retried test results)" -f $mergedPath, $updatedCount)
    $mergedExtra = ''
    if ($notExecuted -gt 0) { $mergedExtra += (', notExecuted={0}' -f $notExecuted) }
    if ($inconclusive -gt 0) { $mergedExtra += (', inconclusive={0}' -f $inconclusive) }
    Write-Host ("   📊 Merged totals: total={0}, passed={1}, failed={2}, error={3}{4}" -f $total, $passed, $failed, $errored, $mergedExtra)

    # Remove individual attempt TRXes so GitHub only picks up the merged one
    for ($a = 1; $a -le $totalAttempts; $a++) {
      $attemptTrx = Get-TrxPath $a
      if (Test-Path $attemptTrx) {
        Remove-Item $attemptTrx -Force
        Write-Host ("   🗑️ Removed attempt TRX: {0}" -f $attemptTrx)
      }
    }
  }
  catch {
    Write-Host ("   ⚠️ TRX merge failed (non-fatal): {0}" -f $_.Exception.Message)
    Write-Host "   Individual attempt TRXes will be uploaded instead."
  }
}

function Build-OrFilter([string[]]$fqns) {
  # Strip NUnit/xUnit parameterized test arguments from FQNs to avoid shell quoting issues.
  # e.g. Class.Method("arg1","arg2") → Class.Method
  # Embedded quotes, parens, ampersands, and commas in param values break PowerShell's
  # native command argument passing, causing MSBuild to receive broken switches.
  # Trade-off: uses ~ (contains) matching, so all parameterizations of a method are retried.
  $parts = New-Object System.Collections.Generic.List[string]
  $seen  = @{}
  foreach ($t in $fqns) {
    if ([string]::IsNullOrWhiteSpace($t)) { continue }
    $clean = $t
    $parenIdx = $clean.IndexOf('(')
    if ($parenIdx -gt 0) { $clean = $clean.Substring(0, $parenIdx) }
    if (-not $seen.ContainsKey($clean)) {
      $seen[$clean] = $true
      $parts.Add(('FullyQualifiedName~{0}' -f $clean))
    }
  }
  [string]::Join($PIPE, $parts)
}

function Invoke-DotNetTest([string]$filterExpr, [int]$attempt) {
  $trxFile = ('{0}-{1}.trx' -f $trxPrefix, $attempt)

  # IMPORTANT: add console logger verbosity so you see detailed test output in Actions logs
  $args = @(
    'test', $project,
    '-c', $config,
    '--logger', ('trx;LogFileName={0}' -f $trxFile),
    '--logger', ('console;verbosity={0}' -f $consoleVerb),
    '--results-directory', $resultsDir
  )

  if ($noBuild -eq 'true') { $args += '--no-build' }

  if (-not [string]::IsNullOrWhiteSpace($additional)) {
    # Tokenize additional args (best-effort)
    $extra = [System.Management.Automation.PSParser]::Tokenize($additional, [ref]$null) |
      Where-Object { $_.Type -eq 'CommandArgument' -or $_.Type -eq 'String' } |
      ForEach-Object { $_.Content }
    if ($extra) { $args += $extra }
  }

  if (-not [string]::IsNullOrWhiteSpace($filterExpr)) {
    $args += @('--filter', $filterExpr)
  }

  # Use GitHub Actions collapsible log groups
  Write-Host ('::group::dotnet {0}' -f ($args -join ' '))
  # Stream dotnet output to the log, but do not emit it as function output
  (& dotnet @args) | Out-Host
  $exitCode = $LASTEXITCODE
  Write-Host '::endgroup::'
  
  # Return only the exit code (int), not an array contaminated with stdout
  return [int]$exitCode
}

function Print-AttemptDiagnostics([int]$attempt, [int]$exitCode) {
  $trxPath = Get-TrxPath $attempt
  Write-Host ("   dotnet exit code: {0}" -f $exitCode)
  Write-Host ("   TRX: {0}" -f $trxPath)

  if (Test-Path $trxPath) {
    Write-Host ("   TRX size: {0} bytes" -f ((Get-Item $trxPath).Length))
    $sum = Get-TrxSummary $trxPath
    if ($sum) {
      $extraInfo = ''
      if ([int]$sum.notExecuted -gt 0) { $extraInfo += (', notExecuted={0}' -f $sum.notExecuted) }
      if ([int]$sum.inconclusive -gt 0) { $extraInfo += (', inconclusive={0}' -f $sum.inconclusive) }
      Write-Host ("   TRX summary: total={0}, passed={1}, failed={2}, error={3}, aborted={4}, timeout={5}{6}" -f `
          $sum.total, $sum.passed, $sum.failed, $sum.error, $sum.aborted, $sum.timeout, $extraInfo)
    } else {
      Write-Host "   TRX summary: (not found)"
    }
    
    # Detect infrastructure failure: dotnet failed but TRX shows 0 tests executed
    if ($exitCode -ne 0) {
      $counters = Get-TrxCounters $trxPath
      if ($counters -and $counters.total -eq 0) {
        Write-Host "   ⚠️ INFRASTRUCTURE FAILURE: dotnet exit code non-zero but 0 tests executed (test runner crash/error)"
      }
    }
  } else {
    Write-Host "   ⚠️ TRX not found! (test runner may have crashed before completing)"
  }
}

# ─── Main entry point ───────────────────────────────────────────────────────────

# Dry-run mode: validate parsing + filter generation without running tests
if (-not [string]::IsNullOrWhiteSpace($dryRunTrx)) {
  Write-Host ''
  Write-Host ('DRY RUN - parsing TRX: {0}' -f $dryRunTrx)

  if (-not (Test-TrxReadable $dryRunTrx)) {
    Write-Host 'DRY RUN - ERROR: TRX file not found or unreadable'
    exit 1
  }

  $failed = @(Get-FailedFQNsFromTrx $dryRunTrx)
  $orFilter = Build-OrFilter $failed
  $retryFilter = if (-not [string]::IsNullOrWhiteSpace($baseFilter)) { '({0})&({1})' -f $baseFilter, $orFilter } else { $orFilter }

  Write-Host ('DRY RUN - failures: {0}' -f $failed.Count)
  $failed | ForEach-Object { Write-Host ('  - {0}' -f $_) }
  Write-Host ''
  Write-Host 'DRY RUN - retry filter:'
  Write-Host $retryFilter

  'exit-code=0' >> $env:GITHUB_OUTPUT
  'attempts-used=0' >> $env:GITHUB_OUTPUT
  'failed-tests-count=0' >> $env:GITHUB_OUTPUT
  'failed-tests-last-count=0' >> $env:GITHUB_OUTPUT
  'failed-tests-last=' >> $env:GITHUB_OUTPUT
  exit 0
}

# Attempt 1
$attempt = 1
Write-Host ''
Write-Host ('🔄 Running tests (attempt {0}/{1})' -f $attempt, $maxAttempts)

$exitCode = Invoke-DotNetTest $baseFilter 1
Print-AttemptDiagnostics 1 $exitCode

# Fast path: successful run should exit immediately
if ($exitCode -eq 0) {
  Write-Host '✅ All tests passed on first attempt'
  'exit-code=0' >> $env:GITHUB_OUTPUT
  'attempts-used=1' >> $env:GITHUB_OUTPUT
  'failed-tests-count=0' >> $env:GITHUB_OUTPUT
  'failed-tests-last-count=0' >> $env:GITHUB_OUTPUT
  'failed-tests-last=' >> $env:GITHUB_OUTPUT
  exit 0
}

$failed1 = @(Get-FailedFQNsFromTrx (Get-TrxPath 1))

# Handle infrastructure failures on first attempt: no readable TRX, or a non-zero exit with nothing to retry (no
# failure recorded). Neither is a pass, and a retry would have nothing to run.
if (-not (Test-TrxReadable (Get-TrxPath 1)) -or $failed1.Count -eq 0) {
  if ($failed1.Count -eq 0 -and (Test-TrxReadable (Get-TrxPath 1))) {
    Write-Host ('❌ INFRASTRUCTURE FAILURE: dotnet test exited {0} on the first attempt but the TRX records no retryable failure.' -f $exitCode)
  } else {
    Write-Host ('❌ INFRASTRUCTURE FAILURE: TRX file missing or unreadable after first attempt.')
  }
  Write-Host ('   Test runner crashed or failed before completing.')

  ('exit-code={0}' -f $exitCode) >> $env:GITHUB_OUTPUT
  'attempts-used=1' >> $env:GITHUB_OUTPUT
  'failed-tests-count=0' >> $env:GITHUB_OUTPUT
  'failed-tests-last-count=0' >> $env:GITHUB_OUTPUT
  'failed-tests-last=' >> $env:GITHUB_OUTPUT
  exit $exitCode
}

$failedFirstCount = $failed1.Count
$lastKnownFailed = $failed1
Write-Host ("   Failures detected (attempt 1): {0}" -f $failedFirstCount)

# Every test with a failure outcome (Failed, Error, Timeout, Aborted) that has not passed since. Only a later pass
# resolves a failure: a retry that skips the test (a provider-quota skip included) or exits 0 without running it leaves
# it failed. The run passes only when this is empty, so a failure can never turn green without the test passing.
# Skips are retried as before (they may hide a hook failure) but are not failures: an opt-in scenario that skips on
# every attempt (Assert.Ignore) does not fail the run.
$unresolved = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($t in @(Get-FailureOutcomeFQNsFromTrx (Get-TrxPath 1))) {
  if (-not [string]::IsNullOrWhiteSpace($t)) { [void]$unresolved.Add($t) }
}

function Write-UnresolvedFailure([string]$reason) {
  # Reports the failures that never passed and exits non-zero (the run is not green).
  $names = @($unresolved | Sort-Object)
  Merge-TrxResults (Get-TrxPath 1) $attempt
  Write-Host ''
  Write-Host ('❌ {0} test(s) failed and never passed: {1}' -f $names.Count, $reason)
  $names | ForEach-Object { Write-Host ('   - {0}' -f $_) }
  'exit-code=1' >> $env:GITHUB_OUTPUT
  ('attempts-used={0}' -f $attempt) >> $env:GITHUB_OUTPUT
  ('failed-tests-count={0}' -f $failedFirstCount) >> $env:GITHUB_OUTPUT
  ('failed-tests-last-count={0}' -f $names.Count) >> $env:GITHUB_OUTPUT
  ('failed-tests-last={0}' -f [string]::Join($PIPE, $names)) >> $env:GITHUB_OUTPUT
  exit 1
}

# Retry attempts: re-run ONLY failures from previous attempt
while ($attempt -lt $maxAttempts) {
  $attempt++
  Write-Host ''

  $trxPrev = Get-TrxPath ($attempt - 1)
  $failedPrev = @(Get-FailedFQNsFromTrx $trxPrev)

  # The previous attempt exited non-zero. With no readable TRX, or a TRX that records no retryable failure, there is
  # nothing new to retry, so run the last known failure list again. That is never a pass by itself: only a later attempt
  # that exits 0 with every failure resolved passes the run.
  if (-not (Test-TrxReadable $trxPrev)) {
    Write-Host ('   ⚠️ TRX from attempt {0} missing or unreadable — retrying the last known failure list ({1} tests).' -f ($attempt - 1), $lastKnownFailed.Count)
    $failedPrev = $lastKnownFailed
  } elseif ($failedPrev.Count -eq 0) {
    Write-Host ('   ⚠️ Attempt {0} exited {1} but its TRX records no retryable failure — retrying the last known failure list ({2} tests).' -f ($attempt - 1), $exitCode, $lastKnownFailed.Count)
    $failedPrev = $lastKnownFailed
  }

  $failedPrev = @($failedPrev)
  if ($failedPrev.Count -gt 0) { $lastKnownFailed = $failedPrev }

  Write-Host ('⚠️ Retrying failed tests (attempt {0}/{1})' -f $attempt, $maxAttempts)
  Write-Host ('   Failed tests to retry: {0}' -f $failedPrev.Count)

  $orFilter = Build-OrFilter $failedPrev
  $retryFilter = if (-not [string]::IsNullOrWhiteSpace($baseFilter)) { '({0})&({1})' -f $baseFilter, $orFilter } else { $orFilter }

  Write-Host ('   Filter: {0}' -f $retryFilter)
  $exitCode = Invoke-DotNetTest $retryFilter $attempt
  Print-AttemptDiagnostics $attempt $exitCode

  # A retried skip that now fails is a failure too; then resolve exactly the failures this attempt ran to a pass.
  foreach ($t in @(Get-FailureOutcomeFQNsFromTrx (Get-TrxPath $attempt))) {
    if (-not [string]::IsNullOrWhiteSpace($t)) { [void]$unresolved.Add($t) }
  }
  foreach ($t in @(Get-PassedFQNsFromTrx (Get-TrxPath $attempt))) {
    if (-not [string]::IsNullOrWhiteSpace($t)) { [void]$unresolved.Remove($t) }
  }

  if ($exitCode -eq 0 -and $unresolved.Count -gt 0) {
    Write-UnresolvedFailure ('attempt {0} exited 0 without passing them (for example, a provider quota was exhausted)' -f $attempt)
  }

  if ($exitCode -eq 0) {
    Write-Host ('✅ Passed on attempt {0}' -f $attempt)
    Merge-TrxResults (Get-TrxPath 1) $attempt
    'exit-code=0' >> $env:GITHUB_OUTPUT
    ('attempts-used={0}' -f $attempt) >> $env:GITHUB_OUTPUT
    ('failed-tests-count={0}' -f $failedFirstCount) >> $env:GITHUB_OUTPUT
    'failed-tests-last-count=0' >> $env:GITHUB_OUTPUT
    'failed-tests-last=' >> $env:GITHUB_OUTPUT
    exit 0
  }

  # Pause between attempts (5 s; tests set SMART_RETRY_DELAY_SECONDS=0).
  Start-Sleep -Seconds ([int]($env:SMART_RETRY_DELAY_SECONDS ?? '5'))
}

# Exhausted attempts
$lastFailed = @(Get-FailedFQNsFromTrx (Get-TrxPath $attempt))

if (-not (Test-TrxReadable (Get-TrxPath $attempt)) -or $lastFailed.Count -eq 0) {
  Write-Host ''
  Write-Host ('   ⚠️ TRX from final attempt missing or without a retryable failure — using last known failure list ({0} tests).' -f $lastKnownFailed.Count)
  $lastFailed = @($lastKnownFailed)
}

# Report every failure that never passed, including any the final attempt only skipped.
foreach ($t in $lastFailed) { [void]$unresolved.Add($t) }
if ($unresolved.Count -gt 0) { $lastFailed = @($unresolved | Sort-Object) }
$lastFailedPipe = [string]::Join($PIPE, $lastFailed)

# Show the TRX summary from the first attempt (full test suite run)
$firstTrxSum = Get-TrxSummary (Get-TrxPath 1)

Merge-TrxResults (Get-TrxPath 1) $attempt

Write-Host ''
Write-Host ('❌ Tests failed after {0} attempts' -f $maxAttempts)
if ($firstTrxSum) {
  $firstExtra = ''
  if ([int]$firstTrxSum.notExecuted -gt 0) { $firstExtra += (', notExecuted={0}' -f $firstTrxSum.notExecuted) }
  if ([int]$firstTrxSum.inconclusive -gt 0) { $firstExtra += (', inconclusive={0}' -f $firstTrxSum.inconclusive) }
  Write-Host ('   TRX summary (attempt 1): total={0}, passed={1}, failed={2}, error={3}, aborted={4}, timeout={5}{6}' -f `
    $firstTrxSum.total, $firstTrxSum.passed, $firstTrxSum.failed, $firstTrxSum.error, $firstTrxSum.aborted, $firstTrxSum.timeout, $firstExtra)
}
Write-Host ('   Final failed tests: {0}' -f $lastFailed.Count)

('exit-code={0}' -f $exitCode) >> $env:GITHUB_OUTPUT
('attempts-used={0}' -f $attempt) >> $env:GITHUB_OUTPUT
('failed-tests-count={0}' -f $failedFirstCount) >> $env:GITHUB_OUTPUT
('failed-tests-last-count={0}' -f $lastFailed.Count) >> $env:GITHUB_OUTPUT
('failed-tests-last={0}' -f $lastFailedPipe) >> $env:GITHUB_OUTPUT

exit $exitCode
