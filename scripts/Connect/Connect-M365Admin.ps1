#Requires -Version 7.4
<#
.SYNOPSIS
    Connects to the Microsoft 365 admin endpoints used by this toolkit.

.DESCRIPTION
    Dot-source this file, then call Connect-M365Admin. This follows the same pattern as
    graph-powershell7-admin-toolkit (https://github.com/anthonybuhnerkemper/graph-powershell7-admin-toolkit),
    extended with SharePoint Online, PnP, Teams, Azure and Power Platform endpoints.

    Power Platform: the Microsoft.PowerApps.Administration.PowerShell module only runs on
    Windows PowerShell 5.1. To stay on PowerShell 7, the PowerPlatform service signs in with
    Az.Accounts and the toolkit calls the Power Platform admin REST APIs directly through the
    helper functions in this file (Invoke-PowerPlatformApi, Get-PowerPlatformEnvironment).
    For app-only runs, the app registration must be registered as a Power Platform management
    app first (see docs/01-prerequisites-and-connect.md).

    Two modes:
      * Certificate (app-only, default): -TenantId, -ClientId and either -CertificateThumbprint
        (cert in CurrentUser\My on Windows) or -CertificatePath (PFX; password read from the
        M365_CERT_PASSWORD environment variable).
      * Interactive (delegated): -Interactive, optionally -UserPrincipalName.

    Values can also come from environment variables: M365_TENANT_ID, M365_CLIENT_ID,
    M365_CERT_THUMBPRINT, M365_ORGANIZATION, M365_SPO_ADMIN_URL, AZ_SUBSCRIPTION_ID.
    No secrets are stored in this repo.

.PARAMETER Service
    Services to connect: Graph, ExchangeOnline, Purview, SharePoint (SPO module), PnP, Teams, Azure,
    PowerPlatform (Az.Accounts sign-in used for the Power Platform admin APIs).

.PARAMETER SharePointAdminUrl
    SharePoint admin center URL, for example https://contoso-admin.sharepoint.com.

.PARAMETER GraphScopes
    Delegated Graph scopes requested in interactive mode.

.EXAMPLE
    . ./scripts/Connect/Connect-M365Admin.ps1
    Connect-M365Admin -Service Graph, PnP -Interactive -ClientId 00000000-0000-0000-0000-000000000000

.EXAMPLE
    Connect-M365Admin -Service PowerPlatform, Graph -Interactive

.EXAMPLE
    $env:M365_TENANT_ID = '00000000-0000-0000-0000-000000000000'
    $env:M365_CLIENT_ID = '00000000-0000-0000-0000-000000000000'
    $env:M365_CERT_THUMBPRINT = '0000000000000000000000000000000000000000'
    $env:M365_ORGANIZATION = 'contoso.onmicrosoft.com'
    Connect-M365Admin -Service Graph, ExchangeOnline

.NOTES
    Install only the modules for the services you use: Microsoft.Graph.Authentication,
    ExchangeOnlineManagement 3.x, Microsoft.Online.SharePoint.PowerShell, PnP.PowerShell 2.x/3.x,
    MicrosoftTeams 6.x, Az.Accounts (Azure and PowerPlatform).
#>

function Connect-M365Admin {
    [CmdletBinding()]
    param(
        [ValidateSet('Graph', 'ExchangeOnline', 'Purview', 'SharePoint', 'PnP', 'Teams', 'Azure', 'PowerPlatform')]
        [string[]]$Service = @('Graph'),

        [string]$TenantId = $env:M365_TENANT_ID,
        [string]$ClientId = $env:M365_CLIENT_ID,
        [string]$CertificateThumbprint = $env:M365_CERT_THUMBPRINT,
        [string]$CertificatePath,
        [string]$Organization = $env:M365_ORGANIZATION,
        [string]$SharePointAdminUrl = $env:M365_SPO_ADMIN_URL,
        [string]$SubscriptionId = $env:AZ_SUBSCRIPTION_ID,

        [switch]$Interactive,
        [string]$UserPrincipalName,
        [string[]]$GraphScopes = @('User.Read.All', 'Directory.Read.All', 'AuditLog.Read.All', 'Reports.Read.All')
    )

    $ErrorActionPreference = 'Stop'

    $certificate = $null
    if (-not $Interactive) {
        foreach ($name in 'TenantId', 'ClientId') {
            if (-not (Get-Variable -Name $name -ValueOnly)) {
                throw "Missing $name. Pass it as a parameter or set the matching M365_* environment variable."
            }
        }
        if ($CertificatePath) {
            $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                (Resolve-Path $CertificatePath).Path, $env:M365_CERT_PASSWORD)
        }
        elseif (-not $CertificateThumbprint) {
            throw 'Provide -CertificateThumbprint or -CertificatePath for app-only auth.'
        }
    }
    if ($Service -match 'SharePoint|PnP' -and -not $SharePointAdminUrl) {
        throw 'Provide -SharePointAdminUrl (or M365_SPO_ADMIN_URL), e.g. https://contoso-admin.sharepoint.com'
    }

    if ('Graph' -in $Service) {
        if ($Interactive) { Connect-MgGraph -Scopes $GraphScopes -NoWelcome }
        elseif ($certificate) { Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -Certificate $certificate -NoWelcome }
        else { Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome }
        $ctx = Get-MgContext
        Write-Information "Graph: $($ctx.AuthType) as $($ctx.Account ?? $ctx.AppName)" -InformationAction Continue
    }

    $exoParams = @{ ShowBanner = $false }
    if ($Interactive) {
        if ($UserPrincipalName) { $exoParams.UserPrincipalName = $UserPrincipalName }
    }
    elseif ($Service -match 'ExchangeOnline|Purview') {
        if (-not $Organization) { throw 'Provide -Organization (e.g. contoso.onmicrosoft.com) for app-only Exchange/Purview.' }
        $exoParams.AppId = $ClientId
        $exoParams.Organization = $Organization
        if ($certificate) { $exoParams.Certificate = $certificate } else { $exoParams.CertificateThumbprint = $CertificateThumbprint }
    }
    if ('ExchangeOnline' -in $Service) {
        Connect-ExchangeOnline @exoParams
        Write-Information 'Exchange Online: connected' -InformationAction Continue
    }
    if ('Purview' -in $Service) {
        $ippsParams = $exoParams.Clone()
        $ippsParams.Remove('ShowBanner')
        Connect-IPPSSession @ippsParams
        Write-Information 'Purview (IPPS): connected' -InformationAction Continue
    }

    if ('SharePoint' -in $Service) {
        if ($Interactive) { Connect-SPOService -Url $SharePointAdminUrl }
        else {
            # App-only SPO requires a recent Microsoft.Online.SharePoint.PowerShell build and a thumbprint.
            Connect-SPOService -Url $SharePointAdminUrl -ClientId $ClientId -Tenant $TenantId -CertificateThumbprint $CertificateThumbprint
        }
        Write-Information "SharePoint Online (SPO): connected to $SharePointAdminUrl" -InformationAction Continue
    }

    if ('PnP' -in $Service) {
        # PnP.PowerShell needs your own Entra app registration (ClientId), even for interactive sign-in.
        if (-not $ClientId) { throw 'PnP.PowerShell requires -ClientId (your own app registration).' }
        if ($Interactive) { Connect-PnPOnline -Url $SharePointAdminUrl -Interactive -ClientId $ClientId }
        elseif ($CertificatePath) {
            $securePassword = [securestring]::new()
            foreach ($ch in ([string]$env:M365_CERT_PASSWORD).ToCharArray()) { $securePassword.AppendChar($ch) }
            Connect-PnPOnline -Url $SharePointAdminUrl -ClientId $ClientId -Tenant $Organization -CertificatePath $CertificatePath -CertificatePassword $securePassword
        }
        else { Connect-PnPOnline -Url $SharePointAdminUrl -ClientId $ClientId -Tenant $Organization -Thumbprint $CertificateThumbprint }
        Write-Information "PnP: connected to $SharePointAdminUrl" -InformationAction Continue
    }

    if ('Teams' -in $Service) {
        if ($Interactive) { Connect-MicrosoftTeams | Out-Null }
        elseif ($certificate) { Connect-MicrosoftTeams -TenantId $TenantId -ApplicationId $ClientId -Certificate $certificate | Out-Null }
        else { Connect-MicrosoftTeams -TenantId $TenantId -ApplicationId $ClientId -CertificateThumbprint $CertificateThumbprint | Out-Null }
        Write-Information 'Microsoft Teams: connected' -InformationAction Continue
    }

    if ('Azure' -in $Service -or 'PowerPlatform' -in $Service) {
        $azParams = @{}
        if ($TenantId) { $azParams.TenantId = $TenantId }
        if ($SubscriptionId) { $azParams.Subscription = $SubscriptionId }
        if (-not $Interactive) {
            $azParams.ServicePrincipal = $true
            $azParams.ApplicationId = $ClientId
            $azParams.CertificateThumbprint = $CertificateThumbprint
        }
        Connect-AzAccount @azParams -WarningAction SilentlyContinue | Out-Null
        if ('Azure' -in $Service) { Write-Information "Azure: connected ($((Get-AzContext).Subscription.Name))" -InformationAction Continue }
        if ('PowerPlatform' -in $Service) {
            $script:PowerPlatformTokenCache = @{}
            [void](Get-PowerPlatformAccessToken -ResourceUrl 'https://service.powerapps.com/')
            Write-Information "Power Platform: connected as $((Get-AzContext).Account.Id)" -InformationAction Continue
        }
    }
}

function Get-PowerPlatformAccessToken {
    <#
    .SYNOPSIS
        Returns a bearer token for a Power Platform API audience, cached until close to expiry.
    .PARAMETER ResourceUrl
        https://service.powerapps.com/ (BAP and Power Apps) or https://service.flow.microsoft.com/ (Power Automate).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$ResourceUrl)

    if (-not (Get-AzContext)) { throw 'Not connected. Run Connect-M365Admin -Service PowerPlatform first.' }
    if (-not $script:PowerPlatformTokenCache) { $script:PowerPlatformTokenCache = @{} }
    $cached = $script:PowerPlatformTokenCache[$ResourceUrl]
    if ($cached -and $cached.ExpiresOn -gt [datetimeoffset]::UtcNow.AddMinutes(5)) { return $cached.Token }

    $result = Get-AzAccessToken -ResourceUrl $ResourceUrl -WarningAction SilentlyContinue
    $token = if ($result.Token -is [securestring]) { ConvertFrom-SecureString -SecureString $result.Token -AsPlainText } else { [string]$result.Token }
    $script:PowerPlatformTokenCache[$ResourceUrl] = @{ Token = $token; ExpiresOn = [datetimeoffset]$result.ExpiresOn }
    $token
}

function Invoke-PowerPlatformApi {
    <#
    .SYNOPSIS
        Calls a Power Platform admin REST API (api.bap.microsoft.com, api.powerapps.com, api.flow.microsoft.com).
    .PARAMETER Uri
        Full request URI including api-version.
    .PARAMETER Method
        Get (default) or Post. Only list and read style POST calls are used by the report scripts.
    .PARAMETER Body
        Object sent as JSON for POST requests.
    .PARAMETER All
        Follow nextLink paging and return the items in 'value' instead of the raw response.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('Get', 'Post')][string]$Method = 'Get',
        [object]$Body,
        [switch]$All
    )

    $resource = if (([uri]$Uri).Host -like '*flow.microsoft.com') { 'https://service.flow.microsoft.com/' } else { 'https://service.powerapps.com/' }
    $request = @{
        Method             = $Method
        Headers            = @{ Authorization = "Bearer $(Get-PowerPlatformAccessToken -ResourceUrl $resource)"; Accept = 'application/json' }
        MaximumRetryCount  = 2
        RetryIntervalSec   = 5
        ErrorAction        = 'Stop'
    }
    if ($null -ne $Body) {
        $request.Body = $Body | ConvertTo-Json -Depth 20
        $request.ContentType = 'application/json'
    }
    if (-not $All) { return Invoke-RestMethod -Uri $Uri @request }

    $next = $Uri
    while ($next) {
        $page = Invoke-RestMethod -Uri $next @request
        if ($page.PSObject.Properties['value']) { foreach ($item in $page.value) { $item } }
        $next = if ($page.PSObject.Properties['nextLink']) { $page.nextLink } elseif ($page.PSObject.Properties['@odata.nextLink']) { $page.'@odata.nextLink' } else { $null }
    }
}

function Get-PowerPlatformEnvironment {
    <#
    .SYNOPSIS
        Lists Power Platform environments as an admin (BAP admin API).
    .PARAMETER Name
        Environment names (GUIDs) or display names to keep. All environments when omitted.
    .PARAMETER IncludeCapacity
        Expand properties.capacity (Dataverse database, file and log usage).
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [switch]$IncludeCapacity
    )
    $uri = 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01'
    if ($IncludeCapacity) { $uri += '&$expand=properties.capacity' }
    $environments = @(Invoke-PowerPlatformApi -Uri $uri -All)
    if ($Name) { $environments = @($environments | Where-Object { $_.name -in $Name -or $_.properties.displayName -in $Name }) }
    $environments
}
