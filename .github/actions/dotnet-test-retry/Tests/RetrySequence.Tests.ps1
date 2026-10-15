# Pester 5, Linux (the fake dotnet is a bash script; CI runs ubuntu). Runs the real Invoke-SmartTestRetry.ps1 end to end
# against a fake `dotnet` that replays a scripted TRX and exit code for each attempt, so the whole retry sequence is
# checked: a failure must stay a failure until the test passes.
BeforeAll {
  $script:RetryScript = Join-Path $PSScriptRoot '..' 'Invoke-SmartTestRetry.ps1'
  $script:QuotaMessage = '[provider-quota] Paystack returned 503 payment_provider_rate_limited.'

  function New-Trx([object[]]$Results) {
    $definitions = ''
    $resultXml = ''
    foreach ($r in $Results) {
      $id = [guid]::NewGuid().ToString()
      $definitions += ('<UnitTest name="{0}" id="{1}"><TestMethod className="Suite.Feature" name="{0}" /></UnitTest>' -f $r.Name, $id)
      $output = if ($r.ContainsKey('Message')) {
        '<Output><ErrorInfo><Message>{0}</Message></ErrorInfo></Output>' -f [System.Security.SecurityElement]::Escape($r.Message)
      } else { '' }
      $resultXml += ('<UnitTestResult testId="{0}" testName="{1}" outcome="{2}">{3}</UnitTestResult>' -f $id, $r.Name, $r.Outcome, $output)
    }
    $passed = @($Results | Where-Object { $_.Outcome -eq 'Passed' }).Count
    $failed = @($Results | Where-Object { $_.Outcome -eq 'Failed' }).Count
    $notExecuted = @($Results | Where-Object { $_.Outcome -eq 'NotExecuted' }).Count
    return @"
<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <ResultSummary outcome="Completed"><Counters total="$($Results.Count)" executed="$($passed + $failed)" passed="$passed" failed="$failed" error="0" timeout="0" aborted="0" inconclusive="0" notExecuted="$notExecuted" /></ResultSummary>
  <Results>$resultXml</Results>
  <TestDefinitions>$definitions</TestDefinitions>
</TestRun>
"@
  }

  # Runs the real retry script; each attempt gets the next scripted TRX and exit code. Returns exit code and outputs.
  function Invoke-RetrySequence([object[]]$Attempts) {
    $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $bin = Join-Path $root 'bin'
    $state = Join-Path $root 'state'
    $results = Join-Path $root 'results'
    New-Item -ItemType Directory -Path $bin, $state, $results | Out-Null
    for ($i = 0; $i -lt $Attempts.Count; $i++) {
      Set-Content -Path (Join-Path $state ("attempt-{0}.trx" -f ($i + 1))) -Value (New-Trx $Attempts[$i].Results) -Encoding utf8
      Set-Content -Path (Join-Path $state ("exit-{0}" -f ($i + 1))) -Value $Attempts[$i].Exit
    }
    @'
#!/usr/bin/env bash
n=$(( $(cat "$FAKE_STATE/count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_STATE/count"
while [ $# -gt 0 ]; do
  case "$1" in
    --logger) case "$2" in trx*) name="${2#*LogFileName=}";; esac; shift;;
    --results-directory) dir="$2"; shift;;
  esac
  shift
done
cp "$FAKE_STATE/attempt-$n.trx" "$dir/$name"
exit "$(cat "$FAKE_STATE/exit-$n")"
'@ | Set-Content -Path (Join-Path $bin 'dotnet') -NoNewline
    chmod +x (Join-Path $bin 'dotnet')

    $output = Join-Path $root 'github-output'
    $env:FAKE_STATE = $state
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$($env:PATH)"
    $env:INPUT_PROJECT = 'Fake.Tests.csproj'; $env:INPUT_FILTER = ''; $env:INPUT_MAX_ATTEMPTS = '3'
    $env:INPUT_RESULTS_DIRECTORY = $results; $env:INPUT_TRX_FILENAME_PREFIX = 'e2e-attempt'; $env:INPUT_CONFIGURATION = 'Release'
    $env:INPUT_NO_BUILD = 'true'; $env:INPUT_ADDITIONAL_ARGS = ''; $env:INPUT_DRY_RUN_TRX = ''; $env:INPUT_CONSOLE_VERBOSITY = 'quiet'
    $env:GITHUB_OUTPUT = $output
    $env:SMART_RETRY_DELAY_SECONDS = '0'
    & pwsh -NoProfile -File $script:RetryScript | Out-Null
    $exit = $LASTEXITCODE
    $env:PATH = ($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ -ne $bin }) -join [IO.Path]::PathSeparator

    $outputs = @{}
    foreach ($line in Get-Content $output) { $k, $v = $line -split '=', 2; $outputs[$k] = $v }
    # The results the run leaves: the merged TRX, or the first attempt's when no retry result replaced anything.
    $merged = Join-Path $results 'e2e-attempt-merged.trx'
    if (-not (Test-Path $merged)) { $merged = Join-Path $results 'e2e-attempt-1.trx' }
    return [pscustomobject]@{
      Exit = $exit
      Outputs = $outputs
      Attempts = [int](Get-Content (Join-Path $state 'count'))
      Merged = [xml](Get-Content $merged -Raw)
    }
  }

  function Get-MergedOutcome($run, [string]$name) {
    $ns = New-Object System.Xml.XmlNamespaceManager($run.Merged.NameTable)
    $ns.AddNamespace('trx', 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010')
    return $run.Merged.SelectSingleNode("//trx:UnitTestResult[@testName='$name']", $ns).GetAttribute('outcome')
  }
}

Describe 'Retry sequence (real script, fake dotnet)' -Skip:(-not $IsLinux) {
  It 'keeps a failure that a retry only skipped for an exhausted quota: the run fails and the failure stays in the results' {
    $run = Invoke-RetrySequence @(
      @{ Exit = 1; Results = @(@{ Name = 'CancelsOrder'; Outcome = 'Failed'; Message = '403 tenant_membership_required' }) },
      @{ Exit = 0; Results = @(@{ Name = 'CancelsOrder'; Outcome = 'NotExecuted'; Message = $QuotaMessage }) })

    $run.Exit | Should -Not -Be 0
    $run.Outputs['exit-code'] | Should -Be '1'
    $run.Outputs['failed-tests-last'] | Should -Be 'Suite.Feature.CancelsOrder'
    Get-MergedOutcome $run 'CancelsOrder' | Should -Be 'Failed'
  }

  It 'keeps it failed when the skipping retry exits non-zero too (never an infrastructure flake)' {
    $run = Invoke-RetrySequence @(
      @{ Exit = 1; Results = @(@{ Name = 'CancelsOrder'; Outcome = 'Failed'; Message = '403' }) },
      @{ Exit = 1; Results = @(@{ Name = 'CancelsOrder'; Outcome = 'NotExecuted'; Message = $QuotaMessage }) })

    $run.Exit | Should -Not -Be 0
    $run.Outputs['failed-tests-last'] | Should -Be 'Suite.Feature.CancelsOrder'
  }

  It 'passes when the failed test passes on retry' {
    $run = Invoke-RetrySequence @(
      @{ Exit = 1; Results = @(@{ Name = 'Flaky'; Outcome = 'Failed'; Message = 'timeout' }, @{ Name = 'Steady'; Outcome = 'Passed' }) },
      @{ Exit = 0; Results = @(@{ Name = 'Flaky'; Outcome = 'Passed' }) })

    $run.Exit | Should -Be 0
    $run.Attempts | Should -Be 2
    Get-MergedOutcome $run 'Flaky' | Should -Be 'Passed'
  }

  It 'does not retry or fail a test skipped for an exhausted quota on the first attempt' {
    $run = Invoke-RetrySequence @(
      @{ Exit = 1; Results = @(
          @{ Name = 'Flaky'; Outcome = 'Failed'; Message = 'timeout' },
          @{ Name = 'QuotaSkipped'; Outcome = 'NotExecuted'; Message = $QuotaMessage }) },
      @{ Exit = 0; Results = @(@{ Name = 'Flaky'; Outcome = 'Passed' }) })

    $run.Exit | Should -Be 0
    Get-MergedOutcome $run 'QuotaSkipped' | Should -Be 'NotExecuted'
  }

  It 'does not fail an opt-in scenario that skips with a message on every attempt (Assert.Ignore is not a failure)' {
    # RavenXpress: real-B2C and Graph scenarios Assert.Ignore when their configuration is absent. The retry list has
    # always included such skips; they are retried, skip again, and must not fail the run.
    $optIn = @{ Name = 'RegistersWithRealB2c'; Outcome = 'NotExecuted'; Message = 'Real B2C browser-auth scenarios are opt-in for local runs.' }
    $run = Invoke-RetrySequence @(
      @{ Exit = 1; Results = @(@{ Name = 'Flaky'; Outcome = 'Failed'; Message = 'timeout' }, $optIn) },
      @{ Exit = 0; Results = @(@{ Name = 'Flaky'; Outcome = 'Passed' }, $optIn) })

    $run.Exit | Should -Be 0
    $run.Outputs['exit-code'] | Should -Be '0'
  }

  It 'fails a test that keeps failing to the last attempt' {
    $failing = @{ Name = 'Broken'; Outcome = 'Failed'; Message = 'Expected 409, got 403' }
    $run = Invoke-RetrySequence @(
      @{ Exit = 1; Results = @($failing) }, @{ Exit = 1; Results = @($failing) }, @{ Exit = 1; Results = @($failing) })

    $run.Exit | Should -Not -Be 0
    $run.Attempts | Should -Be 3
    $run.Outputs['failed-tests-last'] | Should -Be 'Suite.Feature.Broken'
  }
}
