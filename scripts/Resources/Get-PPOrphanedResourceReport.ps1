#Requires -Version 7.4
#Requires -Modules Az.Accounts, Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Finds apps and flows whose owner is deleted or disabled in Microsoft Entra ID.
.DESCRIPTION
    Read-only. Collects app owners and flow creators from the Power Platform admin APIs, then
    checks each owner in Microsoft Graph. An owner that no longer exists is Deleted. A user with
    accountEnabled = false is Disabled. Owners that are service principals are skipped.
    These apps and flows often break or keep running with nobody responsible for them.
    Hand the CSV to the business, then use Set-PPAppOwnerFromCsv.ps1 to give apps a new owner.
.PARAMETER EnvironmentName
    Environment names (GUIDs) or display names to include. All environments when omitted.
.PARAMETER IncludeHealthy
    Also list resources whose owner is active, so the CSV shows everything.
.PARAMETER OutputFolder
    Folder for CSV output. Defaults to ./output.
.EXAMPLE
    ./Get-PPOrphanedResourceReport.ps1
.EXAMPLE
    ./Get-PPOrphanedResourceReport.ps1 -EnvironmentName 'Contoso Default' -IncludeHealthy
#>
[CmdletBinding()]
param(
    [string[]]$EnvironmentName,
    [switch]$IncludeHealthy,
    [string]$OutputFolder = (Join-Path (Get-Location) 'output')
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Invoke-PowerPlatformApi -ErrorAction SilentlyContinue)) {
    throw 'Dot-source ./scripts/Connect/Connect-M365Admin.ps1 and run Connect-M365Admin -Service PowerPlatform first.'
}
if (-not (Get-MgContext)) { throw 'Not connected to Graph. Run Connect-M365Admin -Service PowerPlatform, Graph first.' }
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

$ownerCache = @{}
function Get-OwnerState {
    param([string]$ObjectId)
    if (-not $ObjectId) { return [pscustomobject]@{ State = 'Unknown'; Upn = $null } }
    if ($ownerCache.ContainsKey($ObjectId)) { return $ownerCache[$ObjectId] }
    $result = try {
        $u = Invoke-MgGraphRequest -Method GET -OutputType PSObject -Uri "v1.0/users/$($ObjectId)?`$select=id,userPrincipalName,accountEnabled"
        [pscustomobject]@{ State = if ($u.accountEnabled) { 'Active' } else { 'Disabled' }; Upn = $u.userPrincipalName }
    }
    catch {
        if ($_.Exception.Message -notmatch 'NotFound|404|does not exist') { [pscustomobject]@{ State = 'LookupFailed'; Upn = $null } }
        else {
            try {
                [void](Invoke-MgGraphRequest -Method GET -OutputType PSObject -Uri "v1.0/servicePrincipals/$($ObjectId)?`$select=id")
                [pscustomobject]@{ State = 'ServicePrincipal'; Upn = $null }
            }
            catch { [pscustomobject]@{ State = 'Deleted'; Upn = $null } }
        }
    }
    $ownerCache[$ObjectId] = $result
    $result
}

$rows = foreach ($e in (Get-PowerPlatformEnvironment -Name $EnvironmentName)) {
    $envLabel = $e.properties.displayName
    $resources = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($a in (Invoke-PowerPlatformApi -All -Uri "https://api.powerapps.com/providers/Microsoft.PowerApps/scopes/admin/environments/$($e.name)/apps?api-version=2016-11-01")) {
            $resources.Add([pscustomobject]@{ Kind = 'App'; Name = $a.properties.displayName; Id = $a.name; Owner = $a.properties.owner.id; OwnerName = $a.properties.owner.displayName; LastModified = $a.properties.lastModifiedTime; State = $null })
        }
    }
    catch { Write-Warning "$envLabel apps: $($_.Exception.Message)" }
    try {
        foreach ($f in (Invoke-PowerPlatformApi -All -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/scopes/admin/environments/$($e.name)/v2/flows?api-version=2016-11-01")) {
            $resources.Add([pscustomobject]@{ Kind = 'Flow'; Name = $f.properties.displayName; Id = $f.name; Owner = $f.properties.creator.objectId ?? $f.properties.creator.userId; OwnerName = $null; LastModified = $f.properties.lastModifiedTime; State = $f.properties.state })
        }
    }
    catch { Write-Warning "$envLabel flows: $($_.Exception.Message)" }

    foreach ($r in $resources) {
        $owner = Get-OwnerState -ObjectId $r.Owner
        if (-not $IncludeHealthy -and $owner.State -notin 'Deleted', 'Disabled') { continue }
        [pscustomobject]@{
            Environment     = $envLabel
            EnvironmentName = $e.name
            Kind            = $r.Kind
            Name            = $r.Name
            ResourceId      = $r.Id
            FlowState       = $r.State
            OwnerObjectId   = $r.Owner
            OwnerName       = $r.OwnerName
            OwnerUpn        = $owner.Upn
            OwnerState      = $owner.State
            LastModified    = $r.LastModified
        }
    }
}

$file = Join-Path $OutputFolder "PPOrphaned-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$rows | Sort-Object OwnerState, Environment, Kind, Name | Export-Csv $file -NoTypeInformation
$rows | Group-Object OwnerState, Kind | Select-Object Count, Name | Format-Table -AutoSize
$orphans = @($rows | Where-Object OwnerState -in 'Deleted', 'Disabled')
Write-Information "Orphaned apps and flows: $($orphans.Count) (owners checked: $($ownerCache.Count)). CSV: $file" -InformationAction Continue
