# 02 - Environments and capacity

An environment is a container for apps, flows and data. Most tenants have more of them than anyone thinks.

## 1. The inventory
```powershell
./scripts/Environments/Get-PPEnvironmentInventory.ps1
./scripts/Environments/Get-PPEnvironmentInventory.ps1 -OldTrialDays 14
```
One row per environment with its type (Production, Sandbox, Trial, Developer, Default, Teams), region, Dataverse URL and who created it.

Check the `Flags` column:
- `NoSecurityGroup` means anyone with a license can get in to a Dataverse environment. Most production environments should be locked to a security group.
- `Older30Days` means a trial or developer environment that has been around a while. Ask the owner if it is still needed.
- `Managed = True` means the environment is a Managed Environment with the extra governance features turned on.

## 2. Storage
```powershell
./scripts/Environments/Get-PPEnvironmentCapacityReport.ps1
./scripts/Environments/Get-PPEnvironmentCapacityReport.ps1 -MinTotalMB 1024
```
Dataverse storage comes in three types: Database, File and Log. Your tenant gets a pool of each from its licenses. When the pool is full, new environments and copies are blocked.

The report sorts the biggest environments first. Look at the top few. Old audit logs, attachments and copies of production are the usual reasons.

The admin center refreshes these numbers about once a day, so small changes will not show right away.
