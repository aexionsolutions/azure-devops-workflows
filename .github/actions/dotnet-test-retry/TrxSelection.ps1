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
#>

$script:ProviderQuotaMarker = '[provider-quota]'

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
  $message = (Get-ResultMessage -Node $Node -Ns $Ns).TrimStart()
  return $message.StartsWith($script:ProviderQuotaMarker, [System.StringComparison]::Ordinal)
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
  # Return $null (not @()) when TRX is missing/unreadable so caller can distinguish
  # between "TRX exists with 0 failures" vs "TRX doesn't exist/corrupt"
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
  # Intentional deployed-safety skips and provider-quota skips are emitted as
  # NotExecuted with ErrorInfo too, so filter those out before building the retry list.
  $notExecNodes = $xml.SelectNodes("//trx:Results/trx:UnitTestResult[@outcome='NotExecuted']", $ns)
  $intentionalNotExecutedSkips = @($notExecNodes | Where-Object {
    Test-IntentionalNotExecutedSkip -Node $_ -Ns $ns
  })
  $quotaSkips = @($notExecNodes | Where-Object {
    Test-ProviderQuotaSkip -Node $_ -Ns $ns
  })
  $hookFailures = @($notExecNodes | Where-Object {
    $hasErrorInfo = $_.SelectSingleNode('trx:Output/trx:ErrorInfo', $ns) -ne $null
    $hasErrorInfo -and -not (Test-IntentionalNotExecutedSkip -Node $_ -Ns $ns) -and -not (Test-ProviderQuotaSkip -Node $_ -Ns $ns)
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
