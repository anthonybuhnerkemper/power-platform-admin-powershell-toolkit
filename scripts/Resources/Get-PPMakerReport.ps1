#Requires -Version 7.4
#Requires -Modules Az.Accounts
<#
.SYNOPSIS
    Shows who builds in Power Platform: apps and flows per maker, across all environments.
.DESCRIPTION
    Read-only. Collects app owners and flow creators from the admin APIs and rolls them up to
    one row per person, with app and flow counts, the environments they build in and the last
    time they changed something. Add -ResolveUsers (with a Graph connection) to show the user
    principal name and department for each maker.
.PARAMETER EnvironmentName
    Environment names (GUIDs) or display names to include. All environments when omitted.
.PARAMETER ResolveUsers
    Look up each maker in Microsoft Entra ID through Microsoft Graph. Needs
    Connect-M365Admin -Service PowerPlatform, Graph and User.Read.All.
.PARAMETER OutputFolder
    Folder for CSV output. Defaults to ./output.
.EXAMPLE
    ./Get-PPMakerReport.ps1
.EXAMPLE
    ./Get-PPMakerReport.ps1 -ResolveUsers
#>
[CmdletBinding()]
param(
    [string[]]$EnvironmentName,
    [switch]$ResolveUsers,
    [string]$OutputFolder = (Join-Path (Get-Location) 'output')
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Invoke-PowerPlatformApi -ErrorAction SilentlyContinue)) {
    throw 'Dot-source ./scripts/Connect/Connect-M365Admin.ps1 and run Connect-M365Admin -Service PowerPlatform first.'
}
if ($ResolveUsers) {
    if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue) -or -not (Get-MgContext)) {
        throw 'For -ResolveUsers, run Connect-M365Admin -Service PowerPlatform, Graph first.'
    }
}
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

$items = [System.Collections.Generic.List[object]]::new()
foreach ($e in (Get-PowerPlatformEnvironment -Name $EnvironmentName)) {
    $envLabel = $e.properties.displayName
    try {
        $apps = Invoke-PowerPlatformApi -All -Uri "https://api.powerapps.com/providers/Microsoft.PowerApps/scopes/admin/environments/$($e.name)/apps?api-version=2016-11-01"
        foreach ($a in $apps) {
            $items.Add([pscustomobject]@{ Kind = 'App'; ObjectId = $a.properties.owner.id; Name = $a.properties.owner.displayName; Environment = $envLabel; Modified = $a.properties.lastModifiedTime })
        }
    }
    catch { Write-Warning "$envLabel apps: $($_.Exception.Message)" }
    try {
        $flows = Invoke-PowerPlatformApi -All -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/scopes/admin/environments/$($e.name)/v2/flows?api-version=2016-11-01"
        foreach ($f in $flows) {
            $items.Add([pscustomobject]@{ Kind = 'Flow'; ObjectId = $f.properties.creator.objectId ?? $f.properties.creator.userId; Name = $null; Environment = $envLabel; Modified = $f.properties.lastModifiedTime })
        }
    }
    catch { Write-Warning "$envLabel flows: $($_.Exception.Message)" }
}

$rows = foreach ($g in ($items | Where-Object ObjectId | Group-Object ObjectId)) {
    $name = ($g.Group | Where-Object Name | Select-Object -First 1).Name
    $upn = $null; $department = $null
    if ($ResolveUsers) {
        try {
            $u = Invoke-MgGraphRequest -Method GET -OutputType PSObject -Uri "v1.0/users/$($g.Name)?`$select=displayName,userPrincipalName,department"
            $name = $u.displayName; $upn = $u.userPrincipalName; $department = $u.department
        }
        catch { $upn = 'NotFound' }
    }
    [pscustomobject]@{
        Maker         = $name
        UserPrincipalName = $upn
        Department    = $department
        ObjectId      = $g.Name
        Apps          = @($g.Group | Where-Object Kind -eq 'App').Count
        Flows         = @($g.Group | Where-Object Kind -eq 'Flow').Count
        Environments  = (@($g.Group.Environment | Sort-Object -Unique) -join '; ')
        LastModified  = ($g.Group | Where-Object Modified | ForEach-Object { [datetime]$_.Modified } | Sort-Object -Descending | Select-Object -First 1)
    }
}

$rows = @($rows | Sort-Object { $_.Apps + $_.Flows } -Descending)
$file = Join-Path $OutputFolder "PPMakers-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$rows | Export-Csv $file -NoTypeInformation
$rows | Select-Object -First 10 Maker, UserPrincipalName, Apps, Flows | Format-Table -AutoSize
Write-Information "Makers: $($rows.Count), apps: $(@($items | Where-Object Kind -eq 'App').Count), flows: $(@($items | Where-Object Kind -eq 'Flow').Count). CSV: $file" -InformationAction Continue
