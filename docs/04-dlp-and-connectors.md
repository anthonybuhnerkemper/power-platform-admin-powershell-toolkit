# 04 - DLP policies and connectors

A DLP (data loss prevention) policy puts connectors in groups. An app or flow can only mix connectors from the same group. So you can stop people from copying SharePoint data to a personal service.

## 1. The DLP report
```powershell
./scripts/Governance/Get-PPDlpPolicyReport.ps1
```
You get three CSV files:
- **Policies**: each policy, its scope and how many connectors are Business, NonBusiness or Blocked.
- **Connectors**: every connector in every policy and its group.
- **Coverage**: every environment and the policies that apply to it.

Look at the Coverage file first. `NoDlpPolicy` means any connector can be used with any other there. A good start is one tenant policy for all environments, then stricter or looser policies for special cases.

`DefaultGroup` is where new connectors land. Most admins keep it as NonBusiness so new connectors cannot touch business data by default.

## 2. Connector usage
```powershell
./scripts/Governance/Get-PPConnectorUsageReport.ps1
./scripts/Governance/Get-PPConnectorUsageReport.ps1 -PremiumOnly
```
A connection is a signed-in use of a connector. The summary CSV shows each connector with how many connections and makers use it.

Check the `Tier` column:
- `Premium` connectors (SQL Server, HTTP, Dataverse and many more) need a premium license for every user of the app or flow.
- `Custom` connectors are built in house. Make sure someone owns them.

Before you block a connector in DLP, run this report. It tells you who will be affected so you can warn them first.
