#Requires -Version 7.4
#Requires -Modules Az.Accounts
<#
.SYNOPSIS
    Lists every Power Automate cloud flow in every environment with its state and creator.
.DESCRIPTION
    Read-only. Uses the Power Automate admin API. One row per flow with the creator object ID,
    state (Started, Stopped or Suspended), created and modified dates, and the suspension reason
    when Power Automate turned the flow off. Use -State to show only one state.
.PARAMETER EnvironmentName
    Environment names (GUIDs) or display names to include. All environments when omitted.
.PARAMETER State
    Only include flows in this state.
.PARAMETER OutputFolder
    Folder for CSV output. Defaults to ./output.
.EXAMPLE
    ./Get-PPFlowInventory.ps1
.EXAMPLE
    ./Get-PPFlowInventory.ps1 -State Suspended
#>
[CmdletBinding()]
param(
    [string[]]$EnvironmentName,
    [ValidateSet('Started', 'Stopped', 'Suspended')][string]$State,
    [string]$OutputFolder = (Join-Path (Get-Location) 'output')
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Invoke-PowerPlatformApi -ErrorAction SilentlyContinue)) {
    throw 'Dot-source ./scripts/Connect/Connect-M365Admin.ps1 and run Connect-M365Admin -Service PowerPlatform first.'
}
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

$rows = foreach ($e in (Get-PowerPlatformEnvironment -Name $EnvironmentName)) {
    $uri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/scopes/admin/environments/$($e.name)/v2/flows?api-version=2016-11-01"
    try { $flows = @(Invoke-PowerPlatformApi -Uri $uri -All) }
    catch { Write-Warning "$($e.properties.displayName): $($_.Exception.Message)"; continue }
    foreach ($f in $flows) {
        $p = $f.properties
        if ($State -and $p.state -ne $State) { continue }
        [pscustomobject]@{
            Environment       = $e.properties.displayName
            EnvironmentName   = $e.name
            Flow              = $p.displayName
            FlowName          = $f.name
            State             = $p.state
            CreatorObjectId   = $p.creator.objectId ?? $p.creator.userId
            Created           = $p.createdTime
            LastModified      = $p.lastModifiedTime
            SuspensionReason  = $p.flowSuspensionReason
            TriggerType       = @($p.definitionSummary.triggers | ForEach-Object { $_.type }) -join '; '
        }
    }
}

$file = Join-Path $OutputFolder "PPFlows-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$rows | Sort-Object Environment, Flow | Export-Csv $file -NoTypeInformation
$rows | Group-Object State | Select-Object Count, Name | Format-Table -AutoSize
Write-Information "Flows: $(@($rows).Count). CSV: $file" -InformationAction Continue
