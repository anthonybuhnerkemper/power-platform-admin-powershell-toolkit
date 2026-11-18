#Requires -Version 7.4
#Requires -Modules Az.Accounts
<#
.SYNOPSIS
    Gives Power Apps a new owner from a CSV, for example after the old owner left.
.DESCRIPTION
    The CSV needs the columns EnvironmentName, AppName and NewOwnerObjectId (the Entra object ID
    of the new owner). Optional column RoleForOldOwner: CanEdit (default), CanView or None.
    See samples/app-owner-changes.sample.csv. Get the environment and app names from
    Get-PPOrphanedResourceReport.ps1 or Get-PPAppInventory.ps1.
    The new owner also needs access to the data the app uses, so tell them before you run this.
    Supports -WhatIf. Run it with -WhatIf first.
.PARAMETER Path
    Path to the CSV file.
.EXAMPLE
    ./Set-PPAppOwnerFromCsv.ps1 -Path ./samples/app-owner-changes.sample.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ -PathType Leaf })][string]$Path
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Invoke-PowerPlatformApi -ErrorAction SilentlyContinue)) {
    throw 'Dot-source ./scripts/Connect/Connect-M365Admin.ps1 and run Connect-M365Admin -Service PowerPlatform first.'
}

$rows = @(Import-Csv $Path)
if (-not $rows) { throw "No rows in $Path" }
$required = 'EnvironmentName', 'AppName', 'NewOwnerObjectId'
$missing = @($required | Where-Object { $_ -notin $rows[0].PSObject.Properties.Name })
if ($missing) { throw "CSV is missing column(s): $($missing -join ', ')" }
$guid = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'

$done = 0
foreach ($r in $rows) {
    if ($r.NewOwnerObjectId -notmatch $guid) { Write-Warning "Skipping $($r.AppName): NewOwnerObjectId is not a GUID."; continue }
    $oldRole = if ($r.PSObject.Properties['RoleForOldOwner'] -and $r.RoleForOldOwner) { $r.RoleForOldOwner } else { 'CanEdit' }
    if ($oldRole -notin 'CanEdit', 'CanView', 'None') { Write-Warning "Skipping $($r.AppName): RoleForOldOwner must be CanEdit, CanView or None."; continue }

    $base = "https://api.powerapps.com/providers/Microsoft.PowerApps/scopes/admin/environments/$($r.EnvironmentName)/apps/$($r.AppName)"
    try { $app = Invoke-PowerPlatformApi -Uri "$($base)?api-version=2016-11-01" }
    catch { Write-Warning "Skipping $($r.AppName): app not found in $($r.EnvironmentName). $($_.Exception.Message)"; continue }

    $label = "$($app.properties.displayName) ($($r.AppName))"
    if (-not $PSCmdlet.ShouldProcess($label, "Change owner from $($app.properties.owner.displayName) to $($r.NewOwnerObjectId), old owner keeps $oldRole")) { continue }
    try {
        $body = @{ newAppOwner = $r.NewOwnerObjectId; roleForOldAppOwner = $oldRole }
        [void](Invoke-PowerPlatformApi -Method Post -Body $body -Uri "$base/modifyAppOwner?api-version=2022-11-01")
        $done++
        Write-Information "$($label): owner changed" -InformationAction Continue
    }
    catch { Write-Warning "Failed on $($label): $($_.Exception.Message)" }
}
Write-Information "Apps updated: $done of $($rows.Count)" -InformationAction Continue
