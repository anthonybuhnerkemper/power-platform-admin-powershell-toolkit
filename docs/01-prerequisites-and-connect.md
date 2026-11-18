# 01 - Prerequisites and connecting

## 1. Install the modules
```powershell
Install-Module Az.Accounts, Microsoft.Graph.Authentication -Scope CurrentUser
```
- `Az.Accounts` signs you in and gets tokens for the Power Platform admin APIs.
- `Microsoft.Graph.Authentication` checks app and flow owners in Entra ID.

Why not the Power Apps admin module? `Microsoft.PowerApps.Administration.PowerShell` only runs on Windows PowerShell 5.1. These scripts call the same admin APIs from PowerShell 7, so they also run on macOS and Linux.

## 2. Pick the right role
- **Power Platform Administrator** (an Entra ID role) can run every report and change app owners.
- A **Dynamics 365 Administrator** sees only the environments they are an admin of.
- Graph **User.Read.All** is needed for the orphaned resource report.

Give the account the smallest role that does the job. Use Privileged Identity Management to turn the role on only when you need it.

## 3. Connect
```powershell
. ./scripts/Connect/Connect-M365Admin.ps1

# Interactive
Connect-M365Admin -Service PowerPlatform, Graph -Interactive

# App-only with a certificate (for scheduled runs)
$env:M365_TENANT_ID       = '00000000-0000-0000-0000-000000000000'
$env:M365_CLIENT_ID       = '00000000-0000-0000-0000-000000000000'
$env:M365_CERT_THUMBPRINT = '0000000000000000000000000000000000000000'
Connect-M365Admin -Service PowerPlatform, Graph
```

## 4. App-only needs one extra step
A service principal can only call the Power Platform admin APIs after it is registered as a **management app**. Do this once, from Windows PowerShell 5.1, as a Power Platform Administrator:
```powershell
Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
Add-PowerAppsAccount
New-PowerAppManagementApp -ApplicationId 00000000-0000-0000-0000-000000000000
```
For the orphaned resource report, the same app also needs the Graph application permission `User.Read.All` with admin consent.

Never put a secret or a certificate in the repo. The `.gitignore` already blocks `*.pfx`, `*.cer` and `output/`.

When you are done:
```powershell
. ./scripts/Connect/Disconnect-M365Admin.ps1
Disconnect-M365Admin
```
