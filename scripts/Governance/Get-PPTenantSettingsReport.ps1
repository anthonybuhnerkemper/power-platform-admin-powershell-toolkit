#Requires -Version 7.4
#Requires -Modules Az.Accounts
<#
.SYNOPSIS
    Exports Power Platform tenant settings and checks the ones that control who can create what.
.DESCRIPTION
    Read-only. Calls the listTenantSettings admin API (it is a POST, but it only reads) and:
      * saves the full settings as JSON, so you can compare two exports later;
      * flattens every setting to one CSV row (Setting, Value);
      * checks a short list of governance settings against a suggested baseline, such as
        "only admins can create production, trial and developer environments".
    The baseline is a starting point, not a rule. Change $baseline to match your own policy.
.PARAMETER OutputFolder
    Folder for output. Defaults to ./output.
.EXAMPLE
    ./Get-PPTenantSettingsReport.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputFolder = (Join-Path (Get-Location) 'output')
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Invoke-PowerPlatformApi -ErrorAction SilentlyContinue)) {
    throw 'Dot-source ./scripts/Connect/Connect-M365Admin.ps1 and run Connect-M365Admin -Service PowerPlatform first.'
}
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

$settings = Invoke-PowerPlatformApi -Method Post -Body @{} -Uri 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/listTenantSettings?api-version=2020-10-01'

function ConvertTo-SettingRow {
    param([object]$Node, [string]$Prefix)
    foreach ($prop in $Node.PSObject.Properties) {
        $path = if ($Prefix) { "$Prefix.$($prop.Name)" } else { $prop.Name }
        if ($prop.Value -is [System.Management.Automation.PSCustomObject]) { ConvertTo-SettingRow -Node $prop.Value -Prefix $path }
        else { [pscustomobject]@{ Setting = $path; Value = if ($prop.Value -is [array]) { $prop.Value -join '; ' } else { $prop.Value } } }
    }
}
$flat = @(ConvertTo-SettingRow -Node $settings)
$lookup = @{}
foreach ($r in $flat) { $lookup[$r.Setting] = $r.Value }

# Suggested baseline. Setting path = value you want.
$baseline = [ordered]@{
    'disableEnvironmentCreationByNonAdminUsers'                              = $true
    'disableTrialEnvironmentCreationByNonAdminUsers'                         = $true
    'powerPlatform.governance.disableDeveloperEnvironmentCreationByNonAdminUsers' = $true
    'disableCapacityAllocationByEnvironmentAdmins'                           = $true
    'disablePortalsCreationByNonAdminUsers'                                  = $true
    'powerPlatform.powerApps.disableShareWithEveryone'                       = $true
    'powerPlatform.powerApps.enableGuestsToMake'                             = $false
    'powerPlatform.governance.enableDefaultEnvironmentRouting'               = $true
}
$checks = foreach ($key in $baseline.Keys) {
    $present = $lookup.ContainsKey($key)
    $current = if ($present) { $lookup[$key] } else { $null }
    [pscustomobject]@{
        Setting     = $key
        Current     = $current
        Suggested   = $baseline[$key]
        Result      = if (-not $present) { 'NotReturned' } elseif ([string]$current -eq [string]$baseline[$key]) { 'Match' } else { 'Review' }
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$jsonFile = Join-Path $OutputFolder "PPTenantSettings-$stamp.json"
$csvFile = Join-Path $OutputFolder "PPTenantSettings-$stamp.csv"
$checkFile = Join-Path $OutputFolder "PPTenantSettingsCheck-$stamp.csv"
$settings | ConvertTo-Json -Depth 20 | Set-Content -Path $jsonFile -Encoding utf8
$flat | Sort-Object Setting | Export-Csv $csvFile -NoTypeInformation
$checks | Export-Csv $checkFile -NoTypeInformation
$checks | Format-Table -AutoSize
Write-Information "Settings exported: $($flat.Count). To review: $(@($checks | Where-Object Result -eq 'Review').Count). Files: $jsonFile, $csvFile, $checkFile" -InformationAction Continue
