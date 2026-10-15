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
echo "$*" > "$FAKE_STATE/args-$n"
# An attempt the test did not script is a broken fixture, not a simulated infrastructure failure: record it so the
# harness fails the test instead of letting a non-zero assertion accept it.
if [ ! -f "$FAKE_STATE/attempt-$n.trx" ]; then echo "$n" >> "$FAKE_STATE/unexpected"; exit 97; fi
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
    $unexpected = Join-Path $state 'unexpected'
    if (Test-Path $unexpected) {
      throw ('The retry script ran dotnet for attempt(s) {0}, but the test scripted only {1}: fix the fixture.' -f ((Get-Content $unexpected) -join ', '), $Attempts.Count)
    }

    $outputs = @{}
    foreach ($line in Get-Content $output) { $k, $v = $line -split '=', 2; $outputs[$k] = $v }
    # The results the run leaves: the merged TRX, or the first attempt's when no retry result replaced anything.
    $merged = Join-Path $results 'e2e-attempt-merged.trx'
    if (-not (Test-Path $merged)) { $merged = Join-Path $results 'e2e-attempt-1.trx' }
    $attemptCount = [int](Get-Content (Join-Path $state 'count'))
    return [pscustomobject]@{
      Exit = $exit
      Outputs = $outputs
      Attempts = $attemptCount
      # The dotnet command line of each attempt (index 0 = attempt 1), so a test can see what a retry was filtered to.
      Args = @(1..$attemptCount | ForEach-Object { Get-Content (Join-Path $state "args-$_") -Raw })
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

  It 'keeps it failed when the skipping retries exit non-zero too (never an infrastructure flake)' {
    # Attempt 2 only skips the failure and exits 1, so nothing new is retryable: attempt 3 re-runs the last known
    # failure, which skips again. It never passed, so the run fails with it.
    $quotaSkip = @{ Name = 'CancelsOrder'; Outcome = 'NotExecuted'; Message = $QuotaMessage }
    $run = Invoke-RetrySequence @(
      @{ Exit = 1; Results = @(@{ Name = 'CancelsOrder'; Outcome = 'Failed'; Message = '403' }) },
      @{ Exit = 1; Results = @($quotaSkip) },
      @{ Exit = 1; Results = @($quotaSkip) })

    $run.Exit | Should -Not -Be 0
    $run.Attempts | Should -Be 3
    $run.Args[2] | Should -Match 'CancelsOrder'
    $run.Outputs['exit-code'] | Should -Be '1'
    $run.Outputs['failed-tests-last'] | Should -Be 'Suite.Feature.CancelsOrder'
    Get-MergedOutcome $run 'CancelsOrder' | Should -Be 'Failed'
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

  It 'does not fail an unmarked skip that skips with a message on every attempt (Assert.Ignore is not a failure)' {
    # A skip with a message but without the [opt-in] marker may hide a hook failure, so it is retried; when it only
    # skips again it must not fail the run.
    $optIn = @{ Name = 'RegistersWithRealB2c'; Outcome = 'NotExecuted'; Message = 'Real B2C browser-auth scenarios are opt-in for local runs.' }
    $run = Invoke-RetrySequence @(
      @{ Exit = 1; Results = @(@{ Name = 'Flaky'; Outcome = 'Failed'; Message = 'timeout' }, $optIn) },
      @{ Exit = 0; Results = @(@{ Name = 'Flaky'; Outcome = 'Passed' }, $optIn) })

    $run.Exit | Should -Be 0
    $run.Outputs['exit-code'] | Should -Be '0'
  }

  It 'does not retry an opt-in skip: the retry runs only the real failure' {
    $optIn = @{ Name = 'RunsPaystack'; Outcome = 'NotExecuted'; Message = '[opt-in] Paystack E2E is opt-in. Set E2E_RUN_PAYSTACK=true.' }
    $run = Invoke-RetrySequence @(
      @{ Exit = 1; Results = @(@{ Name = 'Flaky'; Outcome = 'Failed'; Message = 'timeout' }, $optIn) },
      @{ Exit = 0; Results = @(@{ Name = 'Flaky'; Outcome = 'Passed' }) })

    $run.Exit | Should -Be 0
    $run.Args[1] | Should -Match 'Flaky'
    $run.Args[1] | Should -Not -Match 'RunsPaystack'
  }

  It 'fails the first attempt when dotnet exits non-zero but records no failure (nothing to retry is not a pass)' {
    $run = Invoke-RetrySequence @(
      @{ Exit = 1; Results = @(@{ Name = 'Steady'; Outcome = 'Passed' }) })

    $run.Exit | Should -Not -Be 0
    $run.Attempts | Should -Be 1
  }

  It 'never passes on a retry that exits non-zero, even when it records no failure' {
    # Attempt 2 passes the failed test but exits 1 (for example the test host crashed afterwards). A non-zero exit is
    # never a pass: the last known failures are retried, and only an attempt that exits 0 can pass the run.
    $run = Invoke-RetrySequence @(
      @{ Exit = 1; Results = @(@{ Name = 'Flaky'; Outcome = 'Failed'; Message = 'timeout' }) },
      @{ Exit = 1; Results = @(@{ Name = 'Flaky'; Outcome = 'Passed' }) },
      @{ Exit = 1; Results = @(@{ Name = 'Flaky'; Outcome = 'Passed' }) })

    $run.Exit | Should -Not -Be 0
    $run.Attempts | Should -Be 3
    $run.Args[2] | Should -Match 'Flaky'
  }

  It 'passes once a re-run of the last known failures exits 0' {
    $run = Invoke-RetrySequence @(
      @{ Exit = 1; Results = @(@{ Name = 'Flaky'; Outcome = 'Failed'; Message = 'timeout' }) },
      @{ Exit = 1; Results = @(@{ Name = 'Flaky'; Outcome = 'Passed' }) },
      @{ Exit = 0; Results = @(@{ Name = 'Flaky'; Outcome = 'Passed' }) })

    $run.Exit | Should -Be 0
    $run.Attempts | Should -Be 3
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
