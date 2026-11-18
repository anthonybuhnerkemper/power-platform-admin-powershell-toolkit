#Requires -Version 7.4
#Requires -Modules Az.Accounts
<#
.SYNOPSIS
    Lists every Power App in every environment with its owner, sharing and connectors.
.DESCRIPTION
    Read-only. Uses the Power Apps admin API. One row per app with the owner, created and
    modified dates, how many users and groups it is shared with, and the connectors it uses.
    Use -NotModifiedForDays to find apps nobody has touched in a long time.
.PARAMETER EnvironmentName
    Environment names (GUIDs) or display names to include. All environments when omitted.
.PARAMETER NotModifiedForDays
    Only include apps not modified in this many days.
.PARAMETER OutputFolder
    Folder for CSV output. Defaults to ./output.
.EXAMPLE
    ./Get-PPAppInventory.ps1
.EXAMPLE
    ./Get-PPAppInventory.ps1 -NotModifiedForDays 180
#>
[CmdletBinding()]
param(
    [string[]]$EnvironmentName,
    [ValidateRange(1, 3650)][int]$NotModifiedForDays,
    [string]$OutputFolder = (Join-Path (Get-Location) 'output')
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Invoke-PowerPlatformApi -ErrorAction SilentlyContinue)) {
    throw 'Dot-source ./scripts/Connect/Connect-M365Admin.ps1 and run Connect-M365Admin -Service PowerPlatform first.'
}
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

$cutoff = if ($NotModifiedForDays) { (Get-Date).AddDays(-$NotModifiedForDays) } else { $null }
$rows = foreach ($e in (Get-PowerPlatformEnvironment -Name $EnvironmentName)) {
    $uri = "https://api.powerapps.com/providers/Microsoft.PowerApps/scopes/admin/environments/$($e.name)/apps?api-version=2016-11-01"
    try { $apps = @(Invoke-PowerPlatformApi -Uri $uri -All) }
    catch { Write-Warning "$($e.properties.displayName): $($_.Exception.Message)"; continue }
    foreach ($a in $apps) {
        $p = $a.properties
        $modified = if ($p.lastModifiedTime) { [datetime]$p.lastModifiedTime } else { $null }
        if ($cutoff -and $modified -and $modified -gt $cutoff) { continue }
        $connectors = @($p.connectionReferences.PSObject.Properties.Value | ForEach-Object { $_.displayName } | Sort-Object -Unique)
        [pscustomobject]@{
            Environment      = $e.properties.displayName
            EnvironmentName  = $e.name
            App              = $p.displayName
            AppName          = $a.name
            AppType          = $p.appType
            OwnerName        = $p.owner.displayName
            OwnerEmail       = $p.owner.email
            OwnerObjectId    = $p.owner.id
            Created          = $p.createdTime
            LastModified     = $modified
            SharedUsers      = $p.sharedUsersCount
            SharedGroups     = $p.sharedGroupsCount
            Connectors       = $connectors -join '; '
            BypassConsent    = [bool]$p.bypassConsent
        }
    }
}

$file = Join-Path $OutputFolder "PPApps-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$rows | Sort-Object Environment, App | Export-Csv $file -NoTypeInformation
$rows | Group-Object Environment | Sort-Object Count -Descending | Select-Object -First 10 Count, Name | Format-Table -AutoSize
Write-Information "Apps: $(@($rows).Count). CSV: $file" -InformationAction Continue
