# Pester 5. Run: Invoke-Pester -Path .github/actions/dotnet-test-retry/Tests
BeforeAll {
  . (Join-Path $PSScriptRoot '..' 'TrxSelection.ps1')

  # A TRX with one result per entry: @{ Name; Outcome; Message (optional) }.
  function New-TrxFixture([object[]]$Results) {
    $definitions = ''
    $resultXml = ''
    $i = 0
    foreach ($r in $Results) {
      $i++
      $id = [guid]::NewGuid().ToString()
      $definitions += ('<UnitTest name="{0}" id="{1}"><TestMethod className="Suite.Feature" name="{0}" /></UnitTest>' -f $r.Name, $id)
      $output = ''
      if ($r.ContainsKey('Message')) {
        $output = ('<Output><ErrorInfo><Message>{0}</Message></ErrorInfo></Output>' -f [System.Security.SecurityElement]::Escape($r.Message))
      }
      $resultXml += ('<UnitTestResult testId="{0}" testName="{1}" outcome="{2}">{3}</UnitTestResult>' -f $id, $r.Name, $r.Outcome, $output)
    }
    $path = Join-Path $TestDrive ('fixture-{0}.trx' -f [guid]::NewGuid())
    @"
<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Results>$resultXml</Results>
  <TestDefinitions>$definitions</TestDefinitions>
</TestRun>
"@ | Set-Content -Path $path -Encoding utf8
    return $path
  }

  $quotaMessage = '[provider-quota] Paystack returned 503 payment_provider_rate_limited: its test-mode daily bank-resolution limit is exhausted.'
  $optInMessage = '[opt-in] Paystack E2E is opt-in. Set E2E_RUN_PAYSTACK=true to run @paystack scenarios.'
}

Describe 'Retry selection' {
  It 'retries a test that failed' {
    $trx = New-TrxFixture @(@{ Name = 'Fails'; Outcome = 'Failed'; Message = 'Expected 201 but got 500' })
    @(Get-FailedFQNsFromTrx $trx) | Should -Be @('Suite.Feature.Fails')
  }

  It 'does not retry a test skipped for an exhausted provider quota' {
    $trx = New-TrxFixture @(@{ Name = 'QuotaSkipped'; Outcome = 'NotExecuted'; Message = $quotaMessage })
    @(Get-FailedFQNsFromTrx $trx) | Should -HaveCount 0
  }

  It 'still retries a setup error that does not carry the provider-quota marker' {
    $trx = New-TrxFixture @(@{ Name = 'SetupBroke'; Outcome = 'NotExecuted'; Message = 'Paystack did not create a test settlement subaccount (503): {"code":"some_other_failure"}' })
    @(Get-FailedFQNsFromTrx $trx) | Should -Be @('Suite.Feature.SetupBroke')
  }

  It 'only honours the marker at the start of the message' {
    $trx = New-TrxFixture @(@{ Name = 'MarkerQuoted'; Outcome = 'NotExecuted'; Message = "Setup failed after: $quotaMessage" })
    @(Get-FailedFQNsFromTrx $trx) | Should -Be @('Suite.Feature.MarkerQuoted')
  }

  It 'never treats a failed test as a quota skip, whatever its message says' {
    $trx = New-TrxFixture @(@{ Name = 'FailedWithMarker'; Outcome = 'Failed'; Message = $quotaMessage })
    @(Get-FailedFQNsFromTrx $trx) | Should -Be @('Suite.Feature.FailedWithMarker')
    @(Get-ProviderQuotaSkippedFQNsFromTrx $trx) | Should -HaveCount 0
  }

  It 'keeps ignoring deployed-safety skips' {
    $trx = New-TrxFixture @(@{ Name = 'DeployedSafety'; Outcome = 'NotExecuted'; Message = 'Skipping non-@deployed-smoke scenario on a deployed environment.' })
    @(Get-FailedFQNsFromTrx $trx) | Should -HaveCount 0
  }

  It 'does not retry a plain ignored test without error details' {
    $trx = New-TrxFixture @(@{ Name = 'Ignored'; Outcome = 'NotExecuted' })
    @(Get-FailedFQNsFromTrx $trx) | Should -HaveCount 0
  }

  It 'selects only the real failures from a mixed run (one failure among twenty quota skips)' {
    $results = @(@{ Name = 'RealFailure'; Outcome = 'Failed'; Message = 'Expected 409, received 403' })
    1..20 | ForEach-Object { $results += @{ Name = "Quota$_"; Outcome = 'NotExecuted'; Message = $quotaMessage } }
    $trx = New-TrxFixture $results
    @(Get-FailedFQNsFromTrx $trx) | Should -Be @('Suite.Feature.RealFailure')
    @(Get-ProviderQuotaSkippedFQNsFromTrx $trx) | Should -HaveCount 20
  }
}

Describe 'Opt-in skips' {
  It 'does not retry a test skipped as opt-in (ignored or inconclusive)' {
    $trx = New-TrxFixture @(
      @{ Name = 'Ignored'; Outcome = 'NotExecuted'; Message = $optInMessage },
      @{ Name = 'Inconclusive'; Outcome = 'Inconclusive'; Message = $optInMessage })
    @(Get-FailedFQNsFromTrx $trx) | Should -HaveCount 0
    @(Get-OptInSkippedFQNsFromTrx $trx) | Should -Be @('Suite.Feature.Ignored', 'Suite.Feature.Inconclusive')
  }

  It 'still retries a skip whose message does not start with the opt-in marker' {
    $trx = New-TrxFixture @(@{ Name = 'Challenge'; Outcome = 'NotExecuted'; Message = 'Paystack hosted checkout is showing Cloudflare human verification ([opt-in] not applicable).' })
    @(Get-FailedFQNsFromTrx $trx) | Should -Be @('Suite.Feature.Challenge')
    @(Get-OptInSkippedFQNsFromTrx $trx) | Should -HaveCount 0
  }

  It 'never treats a failed test as an opt-in skip, whatever its message says' {
    $trx = New-TrxFixture @(@{ Name = 'FailedWithMarker'; Outcome = 'Failed'; Message = $optInMessage })
    @(Get-FailedFQNsFromTrx $trx) | Should -Be @('Suite.Feature.FailedWithMarker')
    @(Get-OptInSkippedFQNsFromTrx $trx) | Should -HaveCount 0
  }
}

Describe 'TRX readability' {
  It 'tells a TRX with no failures from a missing or corrupt one' {
    $clean = New-TrxFixture @(@{ Name = 'Passes'; Outcome = 'Passed' })
    $corrupt = Join-Path $TestDrive 'corrupt.trx'
    Set-Content -Path $corrupt -Value '<TestRun><Results>' -Encoding utf8

    Test-TrxReadable $clean | Should -BeTrue
    Test-TrxReadable $corrupt | Should -BeFalse
    Test-TrxReadable (Join-Path $TestDrive 'missing.trx') | Should -BeFalse
    # Why callers need it: an empty failure list arrives as $null, exactly like a missing TRX.
    Get-FailedFQNsFromTrx $clean | Should -BeNullOrEmpty
  }
}

Describe 'Provider-quota skip report' {
  It 'counts quota skips across attempts once each, and reports none when there are none' {
    $dir = Join-Path $TestDrive ('results-{0}' -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dir | Out-Null
    Copy-Item (New-TrxFixture @(
        @{ Name = 'QuotaA'; Outcome = 'NotExecuted'; Message = $quotaMessage },
        @{ Name = 'Flaky'; Outcome = 'Failed'; Message = 'boom' })) (Join-Path $dir 'e2e-attempt-1.trx')
    Copy-Item (New-TrxFixture @(
        @{ Name = 'QuotaA'; Outcome = 'NotExecuted'; Message = $quotaMessage },
        @{ Name = 'Flaky'; Outcome = 'NotExecuted'; Message = $quotaMessage },
        @{ Name = 'OptedOut'; Outcome = 'NotExecuted'; Message = $optInMessage })) (Join-Path $dir 'e2e-attempt-2.trx')

    $output = Join-Path $TestDrive 'output.txt'
    $summary = Join-Path $TestDrive 'summary.md'
    $env:INPUT_RESULTS_DIRECTORY = $dir
    $env:INPUT_TRX_FILENAME_PREFIX = 'e2e-attempt'
    $env:GITHUB_OUTPUT = $output
    $env:GITHUB_STEP_SUMMARY = $summary
    & (Join-Path $PSScriptRoot '..' 'Report-ProviderQuotaSkips.ps1') | Out-Null

    (Get-Content $output) | Should -Contain 'provider-quota-skipped-count=2'
    (Get-Content $output) | Should -Contain 'opt-in-skipped-count=1'
    (Get-Content $summary -Raw) | Should -Match 'Suite\.Feature\.QuotaA'
    (Get-Content $summary -Raw) | Should -Match 'opt-in test\(s\) not run[\s\S]*Suite\.Feature\.OptedOut'

    Remove-Item $output
    $empty = Join-Path $TestDrive ('empty-{0}' -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $empty | Out-Null
    $env:INPUT_RESULTS_DIRECTORY = $empty
    & (Join-Path $PSScriptRoot '..' 'Report-ProviderQuotaSkips.ps1') | Out-Null
    (Get-Content $output) | Should -Contain 'provider-quota-skipped-count=0'
    (Get-Content $output) | Should -Contain 'opt-in-skipped-count=0'
  }
}
