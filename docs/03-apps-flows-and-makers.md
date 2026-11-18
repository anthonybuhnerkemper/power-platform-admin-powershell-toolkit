# 03 - Apps, flows and makers

## 1. Every app
```powershell
./scripts/Resources/Get-PPAppInventory.ps1
./scripts/Resources/Get-PPAppInventory.ps1 -NotModifiedForDays 180
```
One row per app with the owner, sharing counts and connectors. `-NotModifiedForDays` finds apps nobody has touched in a long time. Those are good cleanup candidates.

`BypassConsent = True` means users are not asked to approve the app's connections. That is fine for trusted apps, but you should know which ones they are.

## 2. Every flow
```powershell
./scripts/Resources/Get-PPFlowInventory.ps1
./scripts/Resources/Get-PPFlowInventory.ps1 -State Suspended
```
`Suspended` flows were turned off by Power Automate, usually because of a DLP policy or a licensing problem. The `SuspensionReason` column tells you which.

## 3. Who builds what
```powershell
./scripts/Resources/Get-PPMakerReport.ps1
./scripts/Resources/Get-PPMakerReport.ps1 -ResolveUsers
```
One row per maker with app and flow counts and the environments they build in. With `-ResolveUsers`, the report adds the user principal name and department from Entra ID.

Use it to find your power users. They are great people to invite to a maker community, and the first people to ask before you change a policy.

## 4. Apps and flows with no owner
```powershell
./scripts/Resources/Get-PPOrphanedResourceReport.ps1
```
This one needs the Graph connection. It checks every owner in Entra ID:
- `Deleted` means the account is gone. The app or flow has no owner at all.
- `Disabled` means the account is turned off, usually a leaver.

Flows that run as a deleted user often fail quietly. Apps keep working until a connection expires. Send the list to the business so someone can take them over. See doc 05 for the fix.
