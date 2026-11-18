# Power Platform Admin PowerShell Toolkit

A practical toolkit and step-by-step guide for running **Power Platform** (Power Apps, Power Automate and Dataverse) as an admin with **PowerShell 7**.

It covers an environment inventory, Dataverse storage per environment, every app and flow with its owner, a makers report, apps and flows whose owner left (deleted or disabled in Entra ID), DLP policies and which environments they cover, connector usage with premium and custom connectors called out, a tenant settings export with a governance check, and giving orphaned apps a new owner from a CSV. Every script has comment-based help (`Get-Help ./script.ps1 -Full`), reports export to CSV, and the one change script supports `-WhatIf` / `-Confirm`.

The classic `Microsoft.PowerApps.Administration.PowerShell` module only runs on Windows PowerShell 5.1. To stay on PowerShell 7 (Windows, macOS or Linux), this toolkit signs in with **Az.Accounts** and calls the **Power Platform admin REST APIs** directly, through two small helpers in `Connect-M365Admin.ps1`. Authentication uses **certificates** (app-only) or **interactive** sign-in via the same `Connect-M365Admin` pattern as [graph-powershell7-admin-toolkit](https://github.com/anthonybuhnerkemper/graph-powershell7-admin-toolkit). No secrets are stored in the repo.

> ⚠️ **Disclaimer:** Test everything in a test tenant or a sandbox environment first. Examples use `contoso.com`, environments like `Contoso Sales (Prod)` and placeholder GUIDs (`00000000-0000-0000-0000-000000000000`). Review each script before running it in your environment.

## Prerequisites

| Requirement | Version / notes |
|---|---|
| PowerShell | 7.4 or later (`pwsh`), Windows, macOS or Linux |
| Az.Accounts | Every script (sign-in and tokens for the Power Platform APIs) |
| Microsoft.Graph.Authentication | Orphaned resource report, and the makers report with `-ResolveUsers` |
| Rights | **Power Platform Administrator** (or Global Administrator) for every report and the owner change; Graph **User.Read.All** to check owners in Entra ID |
| App-only | The app registration must be registered as a Power Platform management app once (see [docs/01](docs/01-prerequisites-and-connect.md)) |

```powershell
Install-Module Az.Accounts, Microsoft.Graph.Authentication -Scope CurrentUser
```

## Quick start

```powershell
git clone https://github.com/anthonybuhnerkemper/power-platform-admin-powershell-toolkit.git
cd power-platform-admin-powershell-toolkit

. ./scripts/Connect/Connect-M365Admin.ps1
Connect-M365Admin -Service PowerPlatform, Graph -Interactive

# Reports (CSV files land in ./output)
./scripts/Environments/Get-PPEnvironmentInventory.ps1
./scripts/Environments/Get-PPEnvironmentCapacityReport.ps1
./scripts/Resources/Get-PPAppInventory.ps1 -NotModifiedForDays 180
./scripts/Resources/Get-PPFlowInventory.ps1 -State Suspended
./scripts/Resources/Get-PPMakerReport.ps1 -ResolveUsers
./scripts/Resources/Get-PPOrphanedResourceReport.ps1
./scripts/Governance/Get-PPDlpPolicyReport.ps1
./scripts/Governance/Get-PPConnectorUsageReport.ps1 -PremiumOnly
./scripts/Governance/Get-PPTenantSettingsReport.ps1

# Preview a change before applying it
./scripts/Resources/Set-PPAppOwnerFromCsv.ps1 -Path ./samples/app-owner-changes.sample.csv -WhatIf

. ./scripts/Connect/Disconnect-M365Admin.ps1
Disconnect-M365Admin
```

## Repo map

```text
.github/workflows/pssa.yml  PSScriptAnalyzer CI on push and PR
docs/
  01-prerequisites-and-connect.md
  02-environments-and-capacity.md
  03-apps-flows-and-makers.md
  04-dlp-and-connectors.md
  05-tenant-settings-and-cleanup.md
samples/            app-owner-changes.sample.csv (fake GUIDs)
scripts/
  Connect/          Connect-M365Admin.ps1 (with the Power Platform API helpers), Disconnect-M365Admin.ps1
  Environments/     Get-PPEnvironmentInventory, Get-PPEnvironmentCapacityReport
  Resources/        Get-PPAppInventory, Get-PPFlowInventory, Get-PPMakerReport,
                    Get-PPOrphanedResourceReport, Set-PPAppOwnerFromCsv
  Governance/       Get-PPDlpPolicyReport, Get-PPConnectorUsageReport, Get-PPTenantSettingsReport
```

## Scripts and permissions

| Script | Needs | Changes? |
|---|---|---|
| Get-PPEnvironmentInventory | Power Platform Administrator | No |
| Get-PPEnvironmentCapacityReport | Power Platform Administrator | No |
| Get-PPAppInventory | Power Platform Administrator | No |
| Get-PPFlowInventory | Power Platform Administrator | No |
| Get-PPMakerReport | Power Platform Administrator (+ Graph User.Read.All with `-ResolveUsers`) | No |
| Get-PPOrphanedResourceReport | Power Platform Administrator + Graph User.Read.All | No |
| Get-PPDlpPolicyReport | Power Platform Administrator | No |
| Get-PPConnectorUsageReport | Power Platform Administrator | No |
| Get-PPTenantSettingsReport | Power Platform Administrator | No (the API is a POST, but it only reads) |
| Set-PPAppOwnerFromCsv | Power Platform Administrator | Yes, app owner (`-WhatIf`) |

## How the API helpers work

`Connect-M365Admin -Service PowerPlatform` signs in with `Connect-AzAccount`. After that:

- `Invoke-PowerPlatformApi -Uri <url> [-All]` gets a token for the right audience (`service.powerapps.com` or `service.flow.microsoft.com`), caches it, retries throttled calls and follows `nextLink` paging.
- `Get-PowerPlatformEnvironment [-Name] [-IncludeCapacity]` lists environments through the admin API.

You can use both helpers in your own scripts. The APIs used are the same ones the Power Platform admin center and the admin PowerShell module call. Commercial cloud endpoints only.

## Related

- [entra-id-powershell-toolkit](https://github.com/anthonybuhnerkemper/entra-id-powershell-toolkit): leavers, guests and sign-ins, the other half of the orphaned owner story
- [sharepoint-online-powershell-toolkit](https://github.com/anthonybuhnerkemper/sharepoint-online-powershell-toolkit): the sites many apps and flows store their data in
- [teams-powershell-toolkit](https://github.com/anthonybuhnerkemper/teams-powershell-toolkit): Teams and the Dataverse for Teams environments behind them
- [graph-powershell7-admin-toolkit](https://github.com/anthonybuhnerkemper/graph-powershell7-admin-toolkit): the shared connect pattern and Microsoft 365 reports

## License

[MIT](LICENSE) © 2026 Anthony Buhnerkemper
