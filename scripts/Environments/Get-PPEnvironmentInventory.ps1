#Requires -Version 7.4
#Requires -Modules Az.Accounts
<#
.SYNOPSIS
    Lists every Power Platform environment with its type, region, Dataverse details and creator.
.DESCRIPTION
    Read-only. Uses the Power Platform admin API (the same data as the Environments page in the
    Power Platform admin center). One row per environment, exported to CSV. Flags environments
    that have Dataverse but no security group, and trial or developer environments that are old.
.PARAMETER EnvironmentName
    Environment names (GUIDs) or display names to include. All environments when omitted.
.PARAMETER OldTrialDays
    Trial and developer environments older than this many days are flagged. Default 30.
.PARAMETER OutputFolder
    Folder for CSV output. Defaults to ./output.
.EXAMPLE
    ./Get-PPEnvironmentInventory.ps1
.EXAMPLE
    ./Get-PPEnvironmentInventory.ps1 -EnvironmentName 'Contoso Sales (Prod)'
#>
[CmdletBinding()]
param(
    [string[]]$EnvironmentName,
    [ValidateRange(1, 3650)][int]$OldTrialDays = 30,
    [string]$OutputFolder = (Join-Path (Get-Location) 'output')
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Invoke-PowerPlatformApi -ErrorAction SilentlyContinue)) {
    throw 'Dot-source ./scripts/Connect/Connect-M365Admin.ps1 and run Connect-M365Admin -Service PowerPlatform first.'
}
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

$now = Get-Date
$rows = foreach ($e in (Get-PowerPlatformEnvironment -Name $EnvironmentName)) {
    $p = $e.properties
    $dv = $p.linkedEnvironmentMetadata
    $created = if ($p.createdTime) { [datetime]$p.createdTime } else { $null }
    $ageDays = if ($created) { [int]($now - $created).TotalDays } else { $null }
    $flags = @()
    if ($dv -and -not $dv.securityGroupId -and $p.environmentSku -notin 'Default', 'Teams', 'Developer') { $flags += 'NoSecurityGroup' }
    if ($p.environmentSku -in 'Trial', 'Developer' -and $ageDays -gt $OldTrialDays) { $flags += "Older$($OldTrialDays)Days" }
    if ($p.states.runtime.id -and $p.states.runtime.id -ne 'Enabled') { $flags += "Runtime$($p.states.runtime.id)" }

    [pscustomobject]@{
        DisplayName     = $p.displayName
        EnvironmentName = $e.name
        Type            = $p.environmentSku
        IsDefault       = [bool]$p.isDefault
        Region          = $e.location
        State           = $p.states.runtime.id
        Managed         = $p.governanceConfiguration.protectionLevel -eq 'Standard'
        HasDataverse    = [bool]$dv
        DataverseUrl    = $dv.instanceUrl
        DataverseVersion = $dv.version
        SecurityGroupId = $dv.securityGroupId
        CreatedBy       = $p.createdBy.userPrincipalName ?? $p.createdBy.displayName
        Created         = $created
        AgeDays         = $ageDays
        Flags           = $flags -join ', '
    }
}

$file = Join-Path $OutputFolder "PPEnvironments-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$rows | Sort-Object Type, DisplayName | Export-Csv $file -NoTypeInformation
$rows | Group-Object Type | Sort-Object Count -Descending | Select-Object Count, Name | Format-Table -AutoSize
Write-Information "Environments: $(@($rows).Count), flagged: $(@($rows | Where-Object Flags).Count). CSV: $file" -InformationAction Continue
