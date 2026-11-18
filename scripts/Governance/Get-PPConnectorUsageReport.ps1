#Requires -Version 7.4
#Requires -Modules Az.Accounts
<#
.SYNOPSIS
    Shows which connectors are in use, by whom, and which ones are premium or custom.
.DESCRIPTION
    Read-only. Lists every connection in every environment (a connection is a signed-in use of
    a connector, such as SharePoint or SQL Server) and looks up each connector's tier.
    Writes a detail CSV (one row per connection) and a summary CSV (one row per connector with
    connection and maker counts). Premium and custom connectors need premium licenses for the
    people who use them, so this is a quick license check too.
.PARAMETER EnvironmentName
    Environment names (GUIDs) or display names to include. All environments when omitted.
.PARAMETER PremiumOnly
    Only include premium and custom connectors.
.PARAMETER OutputFolder
    Folder for CSV output. Defaults to ./output.
.EXAMPLE
    ./Get-PPConnectorUsageReport.ps1
.EXAMPLE
    ./Get-PPConnectorUsageReport.ps1 -PremiumOnly
#>
[CmdletBinding()]
param(
    [string[]]$EnvironmentName,
    [switch]$PremiumOnly,
    [string]$OutputFolder = (Join-Path (Get-Location) 'output')
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Invoke-PowerPlatformApi -ErrorAction SilentlyContinue)) {
    throw 'Dot-source ./scripts/Connect/Connect-M365Admin.ps1 and run Connect-M365Admin -Service PowerPlatform first.'
}
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

$rows = foreach ($e in (Get-PowerPlatformEnvironment -Name $EnvironmentName)) {
    $envLabel = $e.properties.displayName
    $tier = @{}
    try {
        $apis = Invoke-PowerPlatformApi -All -Uri "https://api.powerapps.com/providers/Microsoft.PowerApps/apis?api-version=2016-11-01&`$filter=environment%20eq%20%27$($e.name)%27"
        foreach ($api in $apis) {
            $tier[$api.name] = [pscustomobject]@{
                Tier   = if ($api.properties.isCustomApi) { 'Custom' } else { $api.properties.tier }
                Label  = $api.properties.displayName
            }
        }
    }
    catch { Write-Warning "$envLabel connectors: $($_.Exception.Message)" }
    try {
        $connections = @(Invoke-PowerPlatformApi -All -Uri "https://api.powerapps.com/providers/Microsoft.PowerApps/scopes/admin/environments/$($e.name)/connections?api-version=2016-11-01")
    }
    catch { Write-Warning "$envLabel connections: $($_.Exception.Message)"; continue }

    foreach ($c in $connections) {
        $p = $c.properties
        $apiName = ([string]$p.apiId -split '/')[-1]
        $info = $tier[$apiName]
        $connectorTier = $info.Tier ?? 'Unknown'
        if ($PremiumOnly -and $connectorTier -notin 'Premium', 'Custom') { continue }
        [pscustomobject]@{
            Environment     = $envLabel
            EnvironmentName = $e.name
            Connector       = $info.Label ?? $apiName
            ConnectorId     = $apiName
            Tier            = $connectorTier
            Connection      = $p.displayName
            CreatedBy       = $p.createdBy.email ?? $p.createdBy.displayName
            CreatedByObjectId = $p.createdBy.id
            Status          = @($p.statuses | ForEach-Object { $_.status }) -join '; '
            Created         = $p.createdTime
        }
    }
}

$summary = foreach ($g in ($rows | Group-Object ConnectorId)) {
    [pscustomobject]@{
        Connector    = $g.Group[0].Connector
        ConnectorId  = $g.Name
        Tier         = $g.Group[0].Tier
        Connections  = $g.Count
        Makers       = @($g.Group.CreatedByObjectId | Where-Object { $_ } | Sort-Object -Unique).Count
        Environments = @($g.Group.EnvironmentName | Sort-Object -Unique).Count
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$detailFile = Join-Path $OutputFolder "PPConnections-$stamp.csv"
$summaryFile = Join-Path $OutputFolder "PPConnectorSummary-$stamp.csv"
$rows | Sort-Object Environment, Connector | Export-Csv $detailFile -NoTypeInformation
$summary | Sort-Object Connections -Descending | Export-Csv $summaryFile -NoTypeInformation
$summary | Sort-Object Connections -Descending | Select-Object -First 15 Connector, Tier, Connections, Makers | Format-Table -AutoSize
$premium = @($summary | Where-Object Tier -in 'Premium', 'Custom')
Write-Information "Connections: $(@($rows).Count), connectors: $(@($summary).Count), premium or custom: $($premium.Count). CSV: $detailFile, $summaryFile" -InformationAction Continue
