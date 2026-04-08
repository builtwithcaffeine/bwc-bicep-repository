
#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Deployment scope: tenant, mg, or sub")]
    [ValidateSet('tenant', 'mg', 'sub')] [string] $targetScope,

    [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Azure Subscription Id (required for sub scope)")]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')] [string] $subscriptionId,

    [Parameter(Mandatory = $true, Position = 2, HelpMessage = "Environment Type is required")]
    [ValidateSet('dev', 'acc', 'prod')][string] $environmentType,

    [Parameter(Mandatory = $true, Position = 3, HelpMessage = "Customer Name")]
    [string] $customerName,

    [Parameter(Mandatory = $true, Position = 4, HelpMessage = "Azure Location is required")]
    [ValidateSet("eastus", "eastus2", "westus", "westus2", "westus3", "centralus", "northcentralus",
        "southcentralus", "westcentralus", "canadacentral", "canadaeast", "brazilsouth", "brazilsoutheast",
        "northeurope", "westeurope", "uksouth", "ukwest", "swedencentral", "francecentral", "francesouth",
        "germanywestcentral", "germanynorth", "switzerlandnorth", "switzerlandwest", "norwayeast", "norwaywest",
        "polandcentral", "spaincentral", "qatarcentral", "uaenorth", "uaecentral", "southafricanorth",
        "southafricawest", "eastasia", "southeastasia", "japaneast", "japanwest",
        "australiaeast", "australiasoutheast", "australiacentral", "australiacentral2", "centralindia",
        "southindia", "westindia", "koreacentral", "koreasouth", "indonesiacentral",
        "malaysiawest", "newzealandnorth", "chilecentral", "israelcentral", "mexicocentral",
        "austriaeast", "belgiumcentral", "denmarkeast", "italynorth")]
    [string] $location,

    [Parameter(Mandatory = $false, Position = 5, HelpMessage = "Execute Infrastructure Deployment")]
    [switch] $deploy,

    [Parameter(Mandatory = $false, Position = 6, HelpMessage = "Use Service Principal Authentication")]
    [switch] $servicePrincipalAuthentication,

    [Parameter(Mandatory = $false, Position = 7, HelpMessage = "Service Principal Authentication File")]
    [String] $spAuthCredentialFile,

    [Parameter(Mandatory = $false, Position = 8, HelpMessage = "Management Group Id (required for mg scope)")]
    [string] $managementGroupId,

    [Parameter(Mandatory = $false, Position = 9, HelpMessage = "Tenant Id (required for tenant scope)")]
    [string] $tenantId
)

# Enforce strict mode and stop on errors
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Validate scope-specific parameters
switch ($targetScope) {
    'sub' {
        if (-not $subscriptionId) {
            throw "subscriptionId is required when targetScope is 'sub'."
        }
    }
    'mg' {
        if (-not $managementGroupId) {
            throw "managementGroupId is required when targetScope is 'mg'."
        }
    }
    'tenant' {
        if (-not $tenantId) {
            throw "tenantId is required when targetScope is 'tenant'."
        }
    }
}

#
# PowerShell Functions
#

function Get-AzCliVersion {

    # Check if Azure CLI is installed
    if (-not (Get-Command -Name 'az' -ErrorAction SilentlyContinue)) {
        throw "Azure CLI (az) is not installed. Please install it from https://aka.ms/azure-cli."
    }

    Write-Host "Checking for Azure CLI"

    # Get the installed version of Azure CLI
    $azVersionJson = az version --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to determine Azure CLI version."
        return
    }
    $installedVersion = ($azVersionJson | ConvertFrom-Json).'azure-cli'

    if (-not $installedVersion) {
        Write-Warning "Azure CLI version could not be determined."
        return
    }

    Write-Host "Installed Azure CLI version: $installedVersion"

    # Get the latest release version from GitHub
    try {
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Azure/azure-cli/releases/latest"
        $latestVersion = $latestRelease.tag_name.TrimStart('azure-cli-')
    } catch {
        Write-Warning "Unable to fetch the latest release. Ensure you have internet connectivity."
        return
    }

    # Compare versions using semantic versioning
    if ([version]$installedVersion -ge [version]$latestVersion) {
        Write-Host "Azure CLI is up to date."
    } else {
        Write-Host "A new version of Azure CLI is available. Latest Release is: $latestVersion."

        if (-not [Environment]::UserInteractive) {
            Write-Warning "Non-interactive session detected. Skipping Azure CLI update prompt."
            return
        }

        $response = Read-Host "Do you want to update? (Y/N)"

        switch ($response.ToUpper()) {
            "Y" {
                if ($IsWindows -and (Get-Command -Name 'winget' -ErrorAction SilentlyContinue)) {
                    Write-Host "Updating Azure CLI via WinGet, please wait"
                    winget upgrade --id Microsoft.AzureCLI --accept-source-agreements --accept-package-agreements 2>&1 | Out-Host
                } else {
                    Write-Host "Updating Azure CLI via az upgrade, please wait"
                    az upgrade --yes 2>&1 | Out-Host
                }
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Failed to update Azure CLI. Please try updating manually."
                } else {
                    Write-Host "Azure CLI has been updated to version $latestVersion."
                }
            }
            "N" {
                Write-Host "Update canceled."
            }
            default {
                Write-Host "Invalid response. Please answer with Y or N."
            }
        }
    }
}

# Function - Get-BicepVersion
function Get-BicepVersion {

    Write-Host "Checking for Bicep CLI"

    # Check if Bicep CLI is installed
    $bicepOutput = az bicep version --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Bicep CLI is not installed. Please install it using 'az bicep install'."
        return
    }
    $installedVersion = $bicepOutput | Select-String -Pattern 'Bicep CLI version (\d+\.\d+\.\d+)' | ForEach-Object { $_.Matches.Groups[1].Value }

    if (-not $installedVersion) {
        Write-Warning "Bicep CLI version could not be determined."
        return
    }

    Write-Host "Installed Bicep version: $installedVersion"

    # Get the latest release version from GitHub
    try {
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Azure/bicep/releases/latest"
        $latestVersion = $latestRelease.tag_name.TrimStart('v')
    } catch {
        Write-Warning "Unable to fetch the latest release. Ensure you have internet connectivity."
        return
    }

    # Compare versions using semantic versioning
    if ([version]$installedVersion -ge [version]$latestVersion) {
        Write-Host "Bicep CLI is up to date."
    } else {
        Write-Host "A new version of Bicep CLI is available. Latest Release: $latestVersion."

        if (-not [Environment]::UserInteractive) {
            Write-Warning "Non-interactive session detected. Skipping Bicep CLI update prompt."
            return
        }

        $response = Read-Host "Do you want to update? (Y/N)"

        switch ($response.ToUpper()) {
            "Y" {
                Write-Host "Updating Bicep CLI, please wait"
                az bicep upgrade 2>&1 | Out-Host
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Failed to update Bicep CLI. Please try updating manually."
                } else {
                    Write-Host "Bicep CLI has been updated to version $latestVersion."
                }
            }
            "N" {
                Write-Host "Update canceled."
            }
            default {
                Write-Host "Invalid response. Please answer with Y or N."
            }
        }
    }
}

# Get Azure User/Service Principal Identity
function Get-AzIdentity {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('sub', 'mg', 'tenant')]
        [string] $TargetScope,

        [Parameter(Mandatory = $false)]
        [string] $SubscriptionId,

        [Parameter(Mandatory = $false)]
        [string] $ManagementGroupId,

        [Parameter(Mandatory = $false)]
        [string] $TenantId
    )

    try {
        # Get Identity Type
        $azAccountJson = az account show --output json 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Failed to retrieve Azure account information. Ensure you are logged in." }
        $azIdentity = $azAccountJson | ConvertFrom-Json
        $identityType = $azIdentity.user.type
        $signedInPrincipal = $azIdentity.user.name
        $azIdentityObjectId = $null

        if ($identityType -eq 'servicePrincipal') {
            $spJson = az ad sp show --id $signedInPrincipal --output json 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Failed to retrieve service principal details for '$signedInPrincipal'." }
            $spDetails = $spJson | ConvertFrom-Json
            $spDisplayName = $spDetails.displayName
            $azIdentityObjectId = $spDetails.id

            Write-Host "Azure Identity Type...: Service Principal"
            Write-Host "Service Principal.....: $spDisplayName"
            $azIdentityName = $spDisplayName

        } elseif ($identityType -eq 'user') {
            $userJson = az ad signed-in-user show --output json 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Failed to retrieve signed-in user details." }
            $userDetails = $userJson | ConvertFrom-Json
            $azUserAccountName = $signedInPrincipal
            $azIdentityObjectId = $userDetails.id
            $userDisplayName = if ($userDetails.displayName) { $userDetails.displayName } else { $azUserAccountName }
            Write-Host "Azure Identity Type...: User"
            Write-Host "User Account Email....: $azUserAccountName"
            Write-Host "Display Name..........: $userDisplayName"
            $azIdentityName = $azUserAccountName
        } else {
            Write-Warning "Unknown Azure Identity Type: $identityType"
            return $null
        }

        # Get Role Assignments
        $rbacJson = az role assignment list --assignee $signedInPrincipal --include-groups --include-inherited --output json 2>$null
        $rbacAssignments = if ($LASTEXITCODE -eq 0 -and $rbacJson) { $rbacJson | ConvertFrom-Json } else { $null }
        if ($rbacAssignments) {
            $roles = $rbacAssignments | Select-Object -ExpandProperty roleDefinitionName -Unique
            Write-Host "RBAC Assignments......: $($roles -join ', ')"
        } else {
            Write-Warning "No RBAC assignments found for the identity."
            return $azIdentityName
        }

        # Evaluate Owner/Contributor scoped group memberships
        $roleCheckScope = switch ($TargetScope) {
            'sub' { "/subscriptions/$SubscriptionId" }
            'mg' { "/providers/Microsoft.Management/managementGroups/$ManagementGroupId" }
            'tenant' { "/" }
        }
        $roleCheckScopeLabel = switch ($TargetScope) {
            'sub' { "subscription $SubscriptionId" }
            'mg' { "management group $ManagementGroupId" }
            'tenant' { "tenant root ($TenantId)" }
        }

        $rolesToCheck = @('Owner', 'Contributor')

        if ($identityType -eq 'user' -and $azIdentityObjectId) {
            foreach ($roleName in $rolesToCheck) {
                $roleJson = az role assignment list --role $roleName --scope $roleCheckScope --output json 2>$null
                $roleAssignments = if ($LASTEXITCODE -eq 0 -and $roleJson) { $roleJson | ConvertFrom-Json } else { $null }

                if ($roleAssignments) {
                    $directAssignments = $roleAssignments | Where-Object { $_.principalId -eq $azIdentityObjectId }
                    if ($directAssignments) {
                        Write-Host "Role Assignment.......: Direct $roleName assignment detected at: $roleCheckScopeLabel"
                    }

                    $roleGroups = $roleAssignments |
                    Where-Object { $_.principalType -eq 'Group' } |
                    Sort-Object -Property principalId -Unique

                    $membershipMatches = [System.Collections.Generic.List[string]]::new()
                    if ($roleGroups) {
                        foreach ($group in $roleGroups) {
                            $groupId = $group.principalId
                            if (-not $groupId) { continue }
                            $membershipResult = az ad group member check --group $groupId --member-id $azIdentityObjectId --query value -o tsv 2>$null
                            if ($membershipResult -and $membershipResult.Trim().ToLower() -eq 'true') {
                                $membershipMatches.Add($group.principalName)
                            }
                        }

                        if ($membershipMatches.Count -gt 0) {
                            Write-Host "$roleName Group Member.: $($membershipMatches -join ', ')"
                        }
                    }

                    if (-not $directAssignments -and $membershipMatches.Count -eq 0) {
                        if ($roleGroups) {
                            Write-Warning "Identity is not a member of any $roleName-scoped groups at $roleCheckScopeLabel."
                        }
                    }
                }
            }
        } elseif ($identityType -eq 'servicePrincipal') {
            Write-Host "Skipping role group membership check for service principals."
        }

        # Return Azure Identity Name
        return $azIdentityName

    } catch {
        throw "Failed to retrieve Azure identity information: $_"
    }
}


# Generate Cryptographically Secure Random Password
function New-RandomPassword {
    param (
        [Parameter(Mandatory)]
        [ValidateRange(8, 128)]
        [int] $length,

        [ValidateRange(0, 128)]
        [int] $amountOfNonAlphanumeric = 2
    )

    if ($amountOfNonAlphanumeric -gt $length) {
        throw "The number of non-alphanumeric characters cannot exceed the total password length."
    }

    $nonAlphaNumericChars = '!@$#%^&*()_-+=[{]};:<>|./?'.ToCharArray()
    $upperChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()
    $lowerChars = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()
    $digitChars = '0123456789'.ToCharArray()
    $allAlphaNumeric = $upperChars + $lowerChars + $digitChars

    # Helper: get a cryptographically secure random index
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        function Get-SecureRandomIndex([int]$maxExclusive) {
            $bytes = [byte[]]::new(4)
            $rng.GetBytes($bytes)
            $value = [System.BitConverter]::ToUInt32($bytes, 0)
            return [int]($value % $maxExclusive)
        }

        # Build password ensuring at least 1 uppercase, 1 lowercase, 1 digit
        $passwordChars = [char[]]::new($length)

        # Guarantee character class coverage in first positions
        $passwordChars[0] = $upperChars[(Get-SecureRandomIndex $upperChars.Length)]
        $passwordChars[1] = $lowerChars[(Get-SecureRandomIndex $lowerChars.Length)]
        $passwordChars[2] = $digitChars[(Get-SecureRandomIndex $digitChars.Length)]

        # Fill non-alphanumeric slots
        $nonAlphaStart = [Math]::Max(3, $length - $amountOfNonAlphanumeric)
        for ($i = $nonAlphaStart; $i -lt $length; $i++) {
            $passwordChars[$i] = $nonAlphaNumericChars[(Get-SecureRandomIndex $nonAlphaNumericChars.Length)]
        }

        # Fill remaining with random alphanumeric
        for ($i = 3; $i -lt $nonAlphaStart; $i++) {
            $passwordChars[$i] = $allAlphaNumeric[(Get-SecureRandomIndex $allAlphaNumeric.Length)]
        }

        # Fisher-Yates shuffle (cryptographically secure)
        for ($i = $length - 1; $i -gt 0; $i--) {
            $j = Get-SecureRandomIndex ($i + 1)
            $temp = $passwordChars[$i]
            $passwordChars[$i] = $passwordChars[$j]
            $passwordChars[$j] = $temp
        }

        return -join $passwordChars
    } finally {
        $rng.Dispose()
    }
}

# PowerShell Location Shortcode Map
$locationShortCodeMap = @{
    "eastus"             = "eus"
    "eastus2"            = "eus2"
    "westus"             = "wus"
    "westus2"            = "wus2"
    "westus3"            = "wus3"
    "centralus"          = "cus"
    "northcentralus"     = "ncus"
    "southcentralus"     = "scus"
    "westcentralus"      = "wcus"
    "canadacentral"      = "canc"
    "canadaeast"         = "cane"
    "brazilsouth"        = "brs"
    "brazilsoutheast"    = "brse"
    "northeurope"        = "neu"
    "westeurope"         = "weu"
    "uksouth"            = "uks"
    "ukwest"             = "ukw"
    "swedencentral"      = "sec"
    "francecentral"      = "frc"
    "francesouth"        = "frs"
    "germanywestcentral" = "gwc"
    "germanynorth"       = "gn"
    "switzerlandnorth"   = "chn"
    "switzerlandwest"    = "chw"
    "norwayeast"         = "noe"
    "norwaywest"         = "now"
    "polandcentral"      = "plc"
    "spaincentral"       = "spc"
    "qatarcentral"       = "qtc"
    "uaenorth"           = "uan"
    "uaecentral"         = "uac"
    "southafricanorth"   = "san"
    "southafricawest"    = "saw"
    "eastasia"           = "ea"
    "southeastasia"      = "sea"
    "japaneast"          = "jpe"
    "japanwest"          = "jpw"
    "australiaeast"      = "aue"
    "australiasoutheast" = "ause"
    "australiacentral"   = "auc"
    "australiacentral2"  = "auc2"
    "centralindia"       = "cin"
    "southindia"         = "sin"
    "westindia"          = "win"
    "koreacentral"       = "korc"
    "koreasouth"         = "kors"
    "indonesiacentral"   = "idc"
    "malaysiawest"       = "myw"
    "newzealandnorth"    = "nzn"
    "chilecentral"       = "clc"
    "israelcentral"      = "ilc"
    "mexicocentral"      = "mxc"
    "austriaeast"        = "ate"
    "belgiumcentral"     = "bec"
    "denmarkeast"        = "dke"
    "italynorth"         = "itn"
}

# Create Deployment Guid for Tracking in Azure
$deployGuid = (New-Guid).Guid

# Check Azure CLI
Get-AzCliVersion

Write-Host ""

# Check Azure Bicep Version
Get-BicepVersion

Write-Host ""

# Service Principal Authentication
if ($servicePrincipalAuthentication) {
    if (-not $spAuthCredentialFile) {
        Write-Host "Enter Service Principal Details:"
        $spAppId = Read-Host "Service Principal App Id"
        $spAppSecretSecure = Read-Host "Service Principal App Secret" -AsSecureString
        $spAppSecret = ConvertFrom-SecureString -SecureString $spAppSecretSecure -AsPlainText
        $spTenantId = Read-Host "Service Principal Tenant Id"
    } else {
        try {
            $spAuthCredential = Get-Content -Path $spAuthCredentialFile | ConvertFrom-Json
            $spAppId = $spAuthCredential.spAppId
            $spAppSecret = $spAuthCredential.spAppSecret
            $spTenantId = $spAuthCredential.spTenantId
        } catch {
            throw "Failed to parse Service Principal authentication file: $_"
        }
    }

    # Authenticate using Service Principal
    Write-Host "Authenticating with Azure - Service Principal"
    $env:AZURE_CLIENT_SECRET = $spAppSecret
    try {
        az login --service-principal -u $spAppId -p $env:AZURE_CLIENT_SECRET --tenant $spTenantId --output none
        if ($LASTEXITCODE -ne 0) { throw "Azure CLI login failed for service principal '$spAppId'." }
    } finally {
        $env:AZURE_CLIENT_SECRET = $null
        $spAppSecret = $null
    }

    # Validate Role Assignments
    $spRoleAssignments = az role assignment list --assignee $spAppId --output json 2>$null | ConvertFrom-Json
    if (-not $spRoleAssignments) {
        throw "Service Principal lacks role assignments. Assign appropriate roles before proceeding."
    }
} else {
    # Authenticate using Azure CLI
    Write-Host "Authenticating with Azure - User Authentication"
    az login --output none --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI login failed." }
}

Write-Host ""

# Set Azure Subscription (required for sub scope, optional context for mg/tenant)
if ($subscriptionId) {
    Write-Host "Setting Azure Subscription context: $subscriptionId"
    az account set --subscription $subscriptionId --output none
    if ($LASTEXITCODE -ne 0) { throw "Failed to set Azure subscription context to '$subscriptionId'." }
}

Write-Host ""

# Get Azure Identity, Required for Deployment Tags (DeployedBy:)
$azIdentityName = Get-AzIdentity -TargetScope $targetScope -SubscriptionId $subscriptionId -ManagementGroupId $managementGroupId -TenantId $tenantId
if (-not $azIdentityName) {
    throw "Unable to determine Azure identity and/or insufficient RBAC permissions."
}

Write-Host ""
Write-Host "Pre Flight Variable Validation:"
Write-Host "Deployment Guid......: $deployGuid"
Write-Host "Target Scope.........: $targetScope"
Write-Host "Customer Name........: $customerName"
Write-Host "Location.............: $location"
Write-Host "Location Short Code..: $($locationShortCodeMap.$location)"
Write-Host "Environment..........: $environmentType"
if ($targetScope -eq 'mg') { Write-Host "Management Group Id..: $managementGroupId" }
if ($targetScope -eq 'tenant') { Write-Host "Tenant Id............: $tenantId" }

if ($deploy) {
    $scopeTarget = switch ($targetScope) {
        'sub' { "Subscription '$subscriptionId'" }
        'mg' { "Management Group '$managementGroupId'" }
        'tenant' { "Tenant '$tenantId'" }
    }
    if ($PSCmdlet.ShouldProcess($scopeTarget, "Deploy Bicep template 'main.bicep' to $location")) {
        $deployStartTime = Get-Date

        Write-Host ""

        # Deploy Bicep Template - Build scope-aware portal link
        $portalDeployPath = switch ($targetScope) {
            'sub' { "/subscriptions/$subscriptionId/providers/Microsoft.Resources/deployments/iac-$deployGuid" }
            'mg' { "/providers/Microsoft.Management/managementGroups/$managementGroupId/providers/Microsoft.Resources/deployments/iac-$deployGuid" }
            'tenant' { "/providers/Microsoft.Resources/deployments/iac-$deployGuid" }
        }
        $encodedPath = $portalDeployPath -replace '/', '%2F'
        $azDeployGuidLink = "`e]8;;https://portal.azure.com/#view/HubsExtension/DeploymentDetailsBlade/~/overview/id/$encodedPath`e\iac-$deployGuid`e]8;;`e\"

        $deployParams = @(
            '--name', "iac-$deployGuid",
            '--location', $location,
            '--template-file', './main.bicep',
            '--parameters',
            "location=$location",
            "locationShortCode=$($locationShortCodeMap.$location)",
            "customerName=$customerName",
            "environmentType=$environmentType",
            "deployedBy=$azIdentityName"
        )

        # Add scope-specific arguments
        switch ($targetScope) {
            'sub' {
                $deployParams += '--subscription', $subscriptionId
            }
            'mg' {
                $deployParams += '--management-group-id', $managementGroupId
            }
            'tenant' {
                # Tenant scope requires no additional arguments
                # Tenant context is determined by the authenticated session
            }
        }

        # Run what-if preview
        Write-Host "> Planned Infrastructure Changes:"
        az deployment $targetScope what-if @deployParams

        if ($LASTEXITCODE -ne 0) { throw "What-If validation failed for 'iac-$deployGuid'." }

        Write-Host ""
        $confirmDeploy = Read-Host "Proceed with deployment? (Y/N)"
        if ($confirmDeploy.ToUpper() -ne 'Y') {
            Write-Host "Deployment canceled by user."
            return
        }

        Write-Host ""
        Write-Host "> Deployment [$azDeployGuidLink] Started at $($deployStartTime.ToString('HH:mm:ss'))"

        # Execute deployment
        az deployment $targetScope create @deployParams --output none

        if ($LASTEXITCODE -ne 0) { throw "Bicep deployment 'iac-$deployGuid' failed with exit code $LASTEXITCODE." }

        $deployEndTime = Get-Date
        $deploymentDuration = $deployEndTime - $deployStartTime
        Write-Host "> Deployment [$azDeployGuidLink] Completed at $($deployEndTime.ToString('HH:mm:ss')) - Duration: $($deploymentDuration.ToString('hh\:mm\:ss'))"
    }
}
