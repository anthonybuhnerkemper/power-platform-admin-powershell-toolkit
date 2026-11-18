#Requires -Version 7.4
#Requires -Modules Az.Accounts
<#
.SYNOPSIS
    Reports on data loss prevention (DLP) policies and which environments they cover.
.DESCRIPTION
    Read-only. Reads tenant and environment DLP policies from the Power Platform governance API
    and writes three CSV files:
      * Policies: one row per policy with its scope and connector counts per group.
      * Connectors: one row per policy and connector, with the group (Business, NonBusiness, Blocked).
      * Coverage: one row per environment with the policies that apply to it.
    Environments with no policy at all are flagged, because any connector can be mixed there.
.PARAMETER OutputFolder
    Folder for CSV output. Defaults to ./output.
.EXAMPLE
    ./Get-PPDlpPolicyReport.ps1
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

# The API calls the groups Confidential (Business), General (Non-business) and Blocked.
$groupName = @{ Confidential = 'Business'; General = 'NonBusiness'; Blocked = 'Blocked' }
$policies = @(Invoke-PowerPlatformApi -All -Uri 'https://api.bap.microsoft.com/providers/PowerPlatform.Governance/v1/policies')
$environments = @(Get-PowerPlatformEnvironment)

$policyRows = [System.Collections.Generic.List[object]]::new()
$connectorRows = [System.Collections.Generic.List[object]]::new()
foreach ($pol in $policies) {
    $counts = @{ Business = 0; NonBusiness = 0; Blocked = 0 }
    foreach ($grp in @($pol.connectorGroups)) {
        $label = $groupName[[string]$grp.classification] ?? [string]$grp.classification
        foreach ($c in @($grp.connectors)) {
            $counts[$label]++
            $connectorRows.Add([pscustomobject]@{
                    Policy    = $pol.displayName
                    Group     = $label
                    Connector = $c.name
                    Id        = $c.id
                })
        }
    }
    $policyRows.Add([pscustomobject]@{
            Policy            = $pol.displayName
            PolicyName        = $pol.name
            Scope             = $pol.environmentType
            Environments      = (@($pol.environments | ForEach-Object { $_.name }) -join '; ')
            DefaultGroup      = $groupName[[string]$pol.defaultConnectorsClassification] ?? $pol.defaultConnectorsClassification
            BusinessCount     = $counts.Business
            NonBusinessCount  = $counts.NonBusiness
            BlockedCount      = $counts.Blocked
            CreatedBy         = $pol.createdBy.displayName
            LastModified      = $pol.lastModifiedTime
        })
}

$coverageRows = foreach ($e in $environments) {
    $applies = foreach ($pol in $policies) {
        $listed = $e.name -in @($pol.environments | ForEach-Object { $_.name })
        $hit = switch ($pol.environmentType) {
            'AllEnvironments' { $true }
            'ExceptEnvironments' { -not $listed }
            'OnlyEnvironments' { $listed }
            'SingleEnvironment' { $listed }
            default { $listed }
        }
        if ($hit) { $pol.displayName }
    }
    [pscustomobject]@{
        Environment     = $e.properties.displayName
        EnvironmentName = $e.name
        Type            = $e.properties.environmentSku
        PolicyCount     = @($applies).Count
        Policies        = @($applies) -join '; '
        Flag            = if (-not $applies) { 'NoDlpPolicy' } else { '' }
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$files = @{
    Policies   = Join-Path $OutputFolder "PPDlpPolicies-$stamp.csv"
    Connectors = Join-Path $OutputFolder "PPDlpConnectors-$stamp.csv"
    Coverage   = Join-Path $OutputFolder "PPDlpCoverage-$stamp.csv"
}
$policyRows | Sort-Object Policy | Export-Csv $files.Policies -NoTypeInformation
$connectorRows | Sort-Object Policy, Group, Connector | Export-Csv $files.Connectors -NoTypeInformation
$coverageRows | Sort-Object PolicyCount, Environment | Export-Csv $files.Coverage -NoTypeInformation
$policyRows | Select-Object Policy, Scope, BusinessCount, NonBusinessCount, BlockedCount | Format-Table -AutoSize
$uncovered = @($coverageRows | Where-Object Flag)
if ($uncovered) { Write-Warning "Environments with no DLP policy: $($uncovered.Environment -join ', ')" }
Write-Information "DLP policies: $($policies.Count). CSV files: $($files.Values -join ', ')" -InformationAction Continue
