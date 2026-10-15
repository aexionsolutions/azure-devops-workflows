<#
.SYNOPSIS
  TRX reading and retry selection for Invoke-SmartTestRetry.ps1.
.DESCRIPTION
  Kept in its own file so the selection rules can be tested against TRX fixtures (Tests/TrxSelection.Tests.ps1)
  without running dotnet. Dot-sourced by Invoke-SmartTestRetry.ps1.

  Provider-quota skips: a test that cannot run because an external provider's quota is exhausted (for example
  Paystack test mode's daily bank-resolution limit) marks itself inconclusive with a message that starts with
  the marker below. Such a test is neither retried (a retry would hit the same exhausted quota) nor counted as a
  failure, and it is reported separately: it gave no coverage, it did not pass. Only the caller can establish
  quota exhaustion (from the provider's own response), so only a message starting with the marker counts; a
  setup error without it is still retried and still fails.

  Opt-in skips: a test that is off by configuration (its credentials or opt-in flag are absent) skips itself with a
  message that starts with the opt-in marker below. A retry runs with the same configuration, so it is not retried; it
  is not a failure, and it is reported separately as giving no coverage. Only a message starting with the marker
  counts: any other skip with a message may hide a hook failure, so it is still retried.
#>

$script:ProviderQuotaMarker = '[provider-quota]'
$script:OptInMarker = '[opt-in]'

function Load-Trx([string]$path) {
  $xml = New-Object System.Xml.XmlDocument
  $xml.PreserveWhitespace = $true
  $xml.Load($path)

  $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
  $ns.AddNamespace('trx', 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010')
  @{ Xml = $xml; Ns = $ns }
}

function Get-ResultMessage {
  param(
    [System.Xml.XmlNode]$Node,
    [System.Xml.XmlNamespaceManager]$Ns
  )

  $messageNode = $Node.SelectSingleNode('trx:Output/trx:ErrorInfo/trx:Message', $Ns)
  if ($messageNode -eq $null) { return '' }
  return $messageNode.InnerText
}

function Test-IntentionalNotExecutedSkip {
  param(
    [System.Xml.XmlNode]$Node,
    [System.Xml.XmlNamespaceManager]$Ns
  )

  $messageNode = $Node.SelectSingleNode('trx:Output/trx:ErrorInfo/trx:Message', $Ns)
  $stackNode = $Node.SelectSingleNode('trx:Output/trx:ErrorInfo/trx:StackTrace', $Ns)
  $parts = @()
  if ($messageNode -ne $null) { $parts += $messageNode.InnerText }
  if ($stackNode -ne $null) { $parts += $stackNode.InnerText }

  $text = $parts -join "`n"
  if ([string]::IsNullOrWhiteSpace($text)) { return $false }

  return (
    $text -like '*Skipping non-@deployed-smoke scenario*' -or
    $text -like '*Use tools/e2e/run-deployed-e2e.ps1*' -or
    $text -like '*run-deployed-e2e.ps1*AllowMutatingFullRun*'
  )
}

# True when the result did not run because a provider's quota is exhausted: not executed (or inconclusive), with a
# message that starts with the provider-quota marker. A failed result is never a quota skip, whatever it says.
function Test-ProviderQuotaSkip {
  param(
    [System.Xml.XmlNode]$Node,
    [System.Xml.XmlNamespaceManager]$Ns
  )

  $outcome = $Node.GetAttribute('outcome')
  if ($outcome -ne 'NotExecuted' -and $outcome -ne 'Inconclusive') { return $false }
  return (Test-SkipMessageMarker -Node $Node -Ns $Ns -Marker $script:ProviderQuotaMarker)
}

# True when the result skipped itself because the test is off by configuration: not executed (or inconclusive), with a
# message that starts with the opt-in marker. A failed result is never an opt-in skip, whatever it says.
function Test-OptInSkip {
  param(
    [System.Xml.XmlNode]$Node,
    [System.Xml.XmlNamespaceManager]$Ns
  )

  return (Test-SkipMessageMarker -Node $Node -Ns $Ns -Marker $script:OptInMarker)
}

function Test-SkipMessageMarker {
  param(
    [System.Xml.XmlNode]$Node,
    [System.Xml.XmlNamespaceManager]$Ns,
    [string]$Marker
  )

  $outcome = $Node.GetAttribute('outcome')
  if ($outcome -ne 'NotExecuted' -and $outcome -ne 'Inconclusive') { return $false }
  $message = (Get-ResultMessage -Node $Node -Ns $Ns).TrimStart()
  return $message.StartsWith($Marker, [System.StringComparison]::Ordinal)
}

# Whether an attempt's TRX exists and parses. The FQN functions return an empty result as $null (PowerShell unrolls an
# empty array), so "no failures" and "no readable TRX" must be told apart with this, never with a $null check.
function Test-TrxReadable([string]$trxPath) {
  if (-not (Test-Path $trxPath)) { return $false }
  try {
    [void](Load-Trx $trxPath)
    return $true
  }
  catch {
    return $false
  }
}

function Get-FqnMap {
  param(
    [System.Xml.XmlDocument]$Xml,
    [System.Xml.XmlNamespaceManager]$Ns
  )

  # Map UnitTest name -> FullyQualifiedName (className.method)
  $map = @{}
  foreach ($ut in $Xml.SelectNodes('//trx:TestDefinitions/trx:UnitTest', $Ns)) {
    $displayName = $ut.GetAttribute('name')
    if ([string]::IsNullOrWhiteSpace($displayName)) { continue }

    $tm = $ut.SelectSingleNode('./trx:TestMethod', $Ns)
    $map[$displayName] = $displayName
    if ($tm -ne $null) {
      $className = $tm.GetAttribute('className')
      $method    = $tm.GetAttribute('name')
      if (-not [string]::IsNullOrWhiteSpace($className) -and -not [string]::IsNullOrWhiteSpace($method)) {
        $map[$displayName] = ('{0}.{1}' -f $className, $method)
      }
    }
  }
  return $map
}

function ConvertTo-Fqns {
  param($Nodes, [hashtable]$Map)

  $names = New-Object System.Collections.Generic.List[string]
  foreach ($n in @($Nodes)) {
    if ($n -eq $null) { continue }
    $tn = $n.GetAttribute('testName')
    if ([string]::IsNullOrWhiteSpace($tn)) { continue }
    if ($Map.ContainsKey($tn)) { $names.Add($Map[$tn]) } else { $names.Add($tn) }
  }
  return @($names | Sort-Object -Unique)
}

function Get-FailedFQNsFromTrx([string]$trxPath) {
  # $null when the TRX is missing or unreadable, but an empty list also arrives as $null (PowerShell unrolls it), so
  # callers tell "no failures" from "no TRX" with Test-TrxReadable.
  if (-not (Test-Path $trxPath)) { return $null }

  try {
    $doc = Load-Trx $trxPath
  }
  catch {
    Write-Host ("   ⚠️ TRX file exists but is corrupt/truncated: {0}" -f $_.Exception.Message)
    return $null
  }

  $xml = $doc.Xml
  $ns  = $doc.Ns
  $map = Get-FqnMap -Xml $xml -Ns $ns

  # Collect tests with explicitly failed/errored outcomes
  $failedNodes = $xml.SelectNodes("//trx:Results/trx:UnitTestResult[@outcome='Failed' or @outcome='Error' or @outcome='Timeout' or @outcome='Aborted']", $ns)

  # Also collect NotExecuted tests, but ONLY real hook/setup failures.
  # Intentional deployed-safety skips, provider-quota skips and opt-in skips are emitted as
  # NotExecuted with ErrorInfo too, so filter those out before building the retry list.
  $notExecNodes = $xml.SelectNodes("//trx:Results/trx:UnitTestResult[@outcome='NotExecuted']", $ns)
  $intentionalNotExecutedSkips = @($notExecNodes | Where-Object {
    Test-IntentionalNotExecutedSkip -Node $_ -Ns $ns
  })
  $quotaSkips = @($notExecNodes | Where-Object {
    Test-ProviderQuotaSkip -Node $_ -Ns $ns
  })
  $optInSkips = @($notExecNodes | Where-Object {
    Test-OptInSkip -Node $_ -Ns $ns
  })
  $hookFailures = @($notExecNodes | Where-Object {
    $hasErrorInfo = $_.SelectSingleNode('trx:Output/trx:ErrorInfo', $ns) -ne $null
    $hasErrorInfo -and -not (Test-IntentionalNotExecutedSkip -Node $_ -Ns $ns) -and -not (Test-ProviderQuotaSkip -Node $_ -Ns $ns) -and -not (Test-OptInSkip -Node $_ -Ns $ns)
  })
  $skippedCount = $notExecNodes.Count - $hookFailures.Count
  if ($skippedCount -gt 0) {
    Write-Host ("   ℹ️ {0} intentionally-skipped test(s) will not be retried" -f $skippedCount)
  }
  if ($intentionalNotExecutedSkips.Count -gt 0) {
    Write-Host ("   ℹ️ {0} deployed-safety skipped test(s) were ignored by retry selection" -f $intentionalNotExecutedSkips.Count)
  }
  if ($quotaSkips.Count -gt 0) {
    Write-Host ("   ℹ️ {0} test(s) skipped for an exhausted provider quota were ignored by retry selection (no coverage from them)" -f $quotaSkips.Count)
  }
  if ($optInSkips.Count -gt 0) {
    Write-Host ("   ℹ️ {0} opt-in test(s) skipped by configuration were ignored by retry selection (no coverage from them)" -f $optInSkips.Count)
  }

  return (ConvertTo-Fqns -Nodes (@($failedNodes) + $hookFailures) -Map $map)
}

# The tests skipped for an exhausted provider quota (fully qualified names); empty when there are none, $null when
# the TRX is missing or unreadable.
function Get-ProviderQuotaSkippedFQNsFromTrx([string]$trxPath) {
  if (-not (Test-Path $trxPath)) { return $null }
  try {
    $doc = Load-Trx $trxPath
  }
  catch {
    return $null
  }

  $nodes = @($doc.Xml.SelectNodes("//trx:Results/trx:UnitTestResult[@outcome='NotExecuted' or @outcome='Inconclusive']", $doc.Ns) |
    Where-Object { Test-ProviderQuotaSkip -Node $_ -Ns $doc.Ns })
  return (ConvertTo-Fqns -Nodes $nodes -Map (Get-FqnMap -Xml $doc.Xml -Ns $doc.Ns))
}

# The tests skipped as opt-in (fully qualified names); empty when there are none, $null when the TRX is missing or
# unreadable.
function Get-OptInSkippedFQNsFromTrx([string]$trxPath) {
  if (-not (Test-Path $trxPath)) { return $null }
  try {
    $doc = Load-Trx $trxPath
  }
  catch {
    return $null
  }

  $nodes = @($doc.Xml.SelectNodes("//trx:Results/trx:UnitTestResult[@outcome='NotExecuted' or @outcome='Inconclusive']", $doc.Ns) |
    Where-Object { Test-OptInSkip -Node $_ -Ns $doc.Ns })
  return (ConvertTo-Fqns -Nodes $nodes -Map (Get-FqnMap -Xml $doc.Xml -Ns $doc.Ns))
}

# The tests that passed in an attempt (fully qualified names); empty when none did, $null when the TRX is missing or
# unreadable. Only a pass resolves an earlier failure: a skip (a provider-quota skip included) resolves nothing.
function Get-PassedFQNsFromTrx([string]$trxPath) {
  if (-not (Test-Path $trxPath)) { return $null }
  try {
    $doc = Load-Trx $trxPath
  }
  catch {
    return $null
  }

  $nodes = $doc.Xml.SelectNodes("//trx:Results/trx:UnitTestResult[@outcome='Passed']", $doc.Ns)
  return (ConvertTo-Fqns -Nodes $nodes -Map (Get-FqnMap -Xml $doc.Xml -Ns $doc.Ns))
}

# The tests with a failure outcome in an attempt (Failed, Error, Timeout, Aborted); empty when none, $null when the TRX
# is missing or unreadable. Unlike Get-FailedFQNsFromTrx (the retry list), this excludes every NotExecuted result:
# skips that carry a message (Assert.Ignore for an opt-in scenario, Assert.Inconclusive) are retried, but a skip is not
# a failure, so only these outcomes must later pass for the run to pass.
function Get-FailureOutcomeFQNsFromTrx([string]$trxPath) {
  if (-not (Test-Path $trxPath)) { return $null }
  try {
    $doc = Load-Trx $trxPath
  }
  catch {
    return $null
  }

  $nodes = $doc.Xml.SelectNodes("//trx:Results/trx:UnitTestResult[@outcome='Failed' or @outcome='Error' or @outcome='Timeout' or @outcome='Aborted']", $doc.Ns)
  return (ConvertTo-Fqns -Nodes $nodes -Map (Get-FqnMap -Xml $doc.Xml -Ns $doc.Ns))
}

# Whether a retry's result may replace a test's earlier result in the merged TRX. A later result normally does (it is
# the latest outcome), but a skip never replaces a failure: the failure stands, with its evidence, until the test passes.
function Test-ReplacesEarlierResult([string]$EarlierOutcome, [string]$LaterOutcome) {
  $failure = @('Failed', 'Error', 'Timeout', 'Aborted')
  $skip = @('NotExecuted', 'Inconclusive')
  return -not (($failure -contains $EarlierOutcome) -and ($skip -contains $LaterOutcome))
}
