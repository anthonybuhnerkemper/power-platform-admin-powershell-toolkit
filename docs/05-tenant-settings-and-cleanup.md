# 05 - Tenant settings and cleanup

## 1. Export and check tenant settings
```powershell
./scripts/Governance/Get-PPTenantSettingsReport.ps1
```
You get three files:
- A **JSON** export of every setting. Keep it. Compare it with next month's export to see what changed.
- A **CSV** with one row per setting.
- A **check CSV** that compares key settings with a suggested baseline.

The baseline asks questions like these:
- Can only admins create production, trial and developer environments?
- Can makers share an app with everyone?
- Can guests make apps?
- Are new makers routed to their own developer environment instead of the default one?

`Review` means your setting is different from the suggestion. That can be fine. The baseline is a starting point, not a rule. Edit `$baseline` in the script to match your own policy. `NotReturned` means the API did not return that setting for your tenant.

Change tenant settings in the Power Platform admin center under Settings.

## 2. Give orphaned apps a new owner
Start from the orphaned resource report in doc 03. Put the apps you want to move in a CSV:
```text
EnvironmentName,AppName,NewOwnerObjectId,RoleForOldOwner
Default-00000000-0000-0000-0000-000000000000,11111111-1111-1111-1111-111111111111,22222222-2222-2222-2222-222222222222,CanView
```
Preview first, then run it:
```powershell
./scripts/Resources/Set-PPAppOwnerFromCsv.ps1 -Path ./samples/app-owner-changes.sample.csv -WhatIf
./scripts/Resources/Set-PPAppOwnerFromCsv.ps1 -Path ./my-app-owners.csv
```
`RoleForOldOwner` can be `CanEdit` (the default), `CanView` or `None`. For a deleted account, it does not matter.

Tell the new owner before you move the app. They also need access to the data the app uses, like the SharePoint list or SQL database.

For flows, add a co-owner in the Power Automate portal, or use the flow's admin page in the Power Platform admin center.

## 3. A simple monthly routine
1. Run the environment inventory and clean up old trials.
2. Run the orphaned resource report and send it to the business.
3. Run the DLP coverage and connector usage reports.
4. Export tenant settings and compare with last month.

Keep the CSV files. They make a simple monthly governance report for audits.
