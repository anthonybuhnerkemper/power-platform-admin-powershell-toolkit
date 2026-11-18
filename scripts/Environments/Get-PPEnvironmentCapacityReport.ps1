#Requires -Version 7.4
#Requires -Modules Az.Accounts
<#
.SYNOPSIS
    Shows Dataverse database, file and log storage used by each environment.
.DESCRIPTION
    Read-only. Reads properties.capacity from the Power Platform admin API, the same numbers as
    Licensing > Capacity in the admin center. One row per environment with MB used per storage
    type, sorted by total. Use -MinTotalMB to hide small environments.
    The admin center can take up to 24 hours to refresh these numbers.
.PARAMETER EnvironmentName
    Environment names (GUIDs) or display names to include. All environments when omitted.
.PARAMETER MinTotalMB
    Only show environments using at least this much storage in total. Default 0.
.PARAMETER OutputFolder
    Folder for CSV output. Defaults to ./output.
.EXAMPLE
    ./Get-PPEnvironmentCapacityReport.ps1
.EXAMPLE
    ./Get-PPEnvironmentCapacityReport.ps1 -MinTotalMB 1024
#>
[CmdletBinding()]
param(
    [string[]]$EnvironmentName,
    [ValidateRange(0, [int]::MaxValue)][int]$MinTotalMB = 0,
    [string]$OutputFolder = (Join-Path (Get-Location) 'output')
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Invoke-PowerPlatformApi -ErrorAction SilentlyContinue)) {
    throw 'Dot-source ./scripts/Connect/Connect-M365Admin.ps1 and run Connect-M365Admin -Service PowerPlatform first.'
}
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

$rows = foreach ($e in (Get-PowerPlatformEnvironment -Name $EnvironmentName -IncludeCapacity)) {
    $p = $e.properties
    if (-not $p.linkedEnvironmentMetadata) { continue }   # no Dataverse, no capacity to report
    $used = @{ Database = 0.0; File = 0.0; Log = 0.0 }
    $updated = $null
    foreach ($c in @($p.capacity)) {
        if ($c.capacityType -in $used.Keys) { $used[$c.capacityType] = [math]::Round([double]$c.actualConsumption, 1) }
        if ($c.updatedOn) { $updated = $c.updatedOn }
    }
    $total = $used.Database + $used.File + $used.Log
    if ($total -lt $MinTotalMB) { continue }
    [pscustomobject]@{
        DisplayName     = $p.displayName
        EnvironmentName = $e.name
        Type            = $p.environmentSku
        DatabaseMB      = $used.Database
        FileMB          = $used.File
        LogMB           = $used.Log
        TotalMB         = [math]::Round($total, 1)
        TotalGB         = [math]::Round($total / 1024, 2)
        UpdatedOn       = $updated
    }
}

$rows = @($rows | Sort-Object TotalMB -Descending)
$file = Join-Path $OutputFolder "PPCapacity-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$rows | Export-Csv $file -NoTypeInformation
$rows | Select-Object -First 10 DisplayName, Type, DatabaseMB, FileMB, LogMB, TotalGB | Format-Table -AutoSize
$sum = { param($n) [math]::Round((($rows | Measure-Object $n -Sum).Sum) / 1024, 2) }
Write-Information "Dataverse environments: $($rows.Count). Database $(& $sum 'DatabaseMB') GB, File $(& $sum 'FileMB') GB, Log $(& $sum 'LogMB') GB. CSV: $file" -InformationAction Continue
