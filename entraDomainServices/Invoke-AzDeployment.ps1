<#
.SYNOPSIS
    Deploys Azure Bicep templates for Entra Domain Services with support for user or service principal authentication, pre-flight checks, and environment tagging.

.DESCRIPTION
    This script automates the deployment of Azure resources using Bicep templates. It performs pre-flight checks for Azure CLI and Bicep CLI versions, validates user or service principal authentication, ensures required Azure AD applications and groups exist, and deploys infrastructure based on provided parameters. It supports multiple Azure regions and environment types, and tags deployments with relevant metadata.

.PARAMETER targetScope
    The deployment scope. Accepts 'tenant', 'mgmt', or 'sub'.

.PARAMETER subscriptionId
    The Azure Subscription ID (GUID format, 36 characters).

.PARAMETER environmentType
    The environment type for deployment. Accepts 'dev', 'acc', or 'prod'.

.PARAMETER customerName
    The customer name for tagging and resource naming.

.PARAMETER location
    The Azure region/location for deployment. Must be one of the supported Azure locations.

.PARAMETER deploy
    Switch to execute the infrastructure deployment. If not specified, the script performs pre-flight checks only.

.PARAMETER servicePrincipalAuthentication
    Switch to use service principal authentication instead of user authentication.

.PARAMETER spAuthCredentialFile
    Path to a JSON file containing service principal credentials (spAppId, spAppSecret, spTenantId).

.FUNCTIONS
    Get-AzCliVersion
        Checks if Azure CLI is installed and up to date.

    Get-BicepVersion
        Checks if Bicep CLI is installed and up to date.

    Get-AzIdentity
        Retrieves the current Azure identity (user or service principal) and validates RBAC assignments.

    New-RandomPassword
        Generates a random password with configurable length and non-alphanumeric character count.

    New-EntraIdADDSEnterpriseApplication
        Ensures the required Entra ID Enterprise Application and 'AAD DC Administrators' group exist.

.NOTES
    - Requires Azure CLI and Bicep CLI.
    - Requires appropriate Azure RBAC permissions for deployment.
    - Supports both user and service principal authentication.
    - Designed for use in automated CI/CD or manual deployment scenarios.

.EXAMPLE
    .\Invoke-AzDeployment.ps1 -targetScope sub -subscriptionId <GUID> -environmentType dev -customerName Contoso -location eastus -deploy

    Deploys the Bicep template to the specified subscription and location for the 'dev' environment.

.EXAMPLE
    .\Invoke-AzDeployment.ps1 -targetScope sub -subscriptionId <GUID> -environmentType prod -customerName Fabrikam -location westeurope -deploy -servicePrincipalAuthentication -spAuthCredentialFile .\spAuth.json

    Deploys using service principal authentication with credentials from a JSON file.

#>

param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Deployment Guid is required")]
    [validateSet('tenant', 'mgmt', 'sub')] [string] $targetScope,

    [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Azure Subscription Id is required")]
    [ValidateLength(36, 36)] [string] $subscriptionId,

    [Parameter(Mandatory = $true, Position = 2, HelpMessage = "Environment Type is required")]
    [validateSet('dev', 'acc', 'prod')][string] $environmentType,

    [Parameter(Mandatory = $true, Position = 3, HelpMessage = "Customer Name")]
    [string] $customerName,

    [Parameter(Mandatory = $true, Position = 4, HelpMessage = "Azure Location is required")]
    [validateSet("eastus", "eastus2", "eastus3", "westus", "westus2", "westus3", "centralus", "northcentralus",
        "southcentralus", "westcentralus", "canadacentral", "canadaeast", "brazilsouth", "brazilseast",
        "northeurope", "westeurope", "swedencentral", "swedensouth", "francecentral", "francesouth",
        "germanywestcentral", "germanynorth", "switzerlandnorth", "switzerlandwest", "norwayeast", "norwaywest",
        "polandcentral", "spaincentral", "qatarcentral", "uaenorth", "uaecentral", "southafricanorth",
        "southafricawest", "southafricaeast", "eastasia", "southeastasia", "japaneast", "japanwest",
        "australiaeast", "australiasoutheast", "australiacentral", "australiacentral2", "centralindia",
        "southindia", "westindia", "koreacentral", "koreasouth", "chinaeast3", "chinanorth3", "indonesiacentral",
        "malaysiawest", "newzealandnorth", "taiwannorth", "israelcentral", "mexicocentral", "greececentral",
        "finlandcentral", "austriaeast", "belgiumcentral", "denmarkeast", "norwaysouth", "italynorth",
        "usgovvirginia", "usgovarizona", "usgovtexas", "usgoviowa", "switzerlandeast", "germanysouth",
        "francewest", "japancentral", "koreacentral2", "australiawest", "brazilwest", "canadawest")]
    [string] $location,

    [Parameter(Mandatory = $false, Position = 5, HelpMessage = "Execute Infrastructure Deployment")]
    [switch] $deploy,

    [Parameter(Mandatory = $false, Position = 6, HelpMessage = "Use Service Principal Authentication")]
    [switch] $servicePrincipalAuthentication,

    [Parameter(Mandatory = $false, Position = 7, HelpMessage = "Service Principal Authentication File")]
    [String] $spAuthCredentialFile
)

#
# PowerShell Functions
#

function Get-AzCliVersion {

    # Check if Azure CLI is installed
    if (-not (Get-Command -Name 'az' -ErrorAction SilentlyContinue)) {
        Write-Warning "Azure CLI (az) is not installed. Please install it from https://aka.ms/azure-cli."
        exit 1
    }

    Write-Output "Checking for Azure CLI..."

    # Get the installed version of Azure CLI
    $installedVersion = az version --output json | ConvertFrom-Json | Select-Object -ExpandProperty azure-cli

    if (-not $installedVersion) {
        Write-Output "Azure CLI is not installed or version couldn't be determined."
        return
    }

    Write-Output "Installed Azure CLI version: $installedVersion"

    # Get the latest release version from GitHub
    try {
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Azure/azure-cli/releases/latest"
        $latestVersion = $latestRelease.tag_name.TrimStart('azure-cli-')  # GitHub version starts with 'azure-cli-'
    }
    catch {
        Write-Warning "Unable to fetch the latest release. Ensure you have internet connectivity."
        return
    }

    # Compare versions
    if ($installedVersion -eq $latestVersion) {
        Write-Output "Azure CLI is up to date."
    }
    else {
        Write-Output "A new version of Azure CLI is available. Latest Release is: $latestVersion."
        $response = Read-Host "Do you want to update? (Y/N)"

        switch ($response.ToUpper()) {
            "Y" {
                Write-Output "Updating Azure CLI..."
                try {
                    az upgrade
                    Write-Output "Azure CLI has been updated to version $latestVersion."
                }
                catch {
                    Write-Error "Failed to update Azure CLI. Please try updating manually."
                }
            }
            "N" {
                Write-Output "Update canceled."
            }
            default {
                Write-Output "Invalid response. Please answer with Y or N."
            }
        }
    }
}

# Function - Get-BicepVersion
function Get-BicepVersion {

    Write-Output `r "Checking for Bicep CLI..."

    # Check if Bicep CLI is installed
    try {
        $installedVersion = az bicep version --only-show-errors | Select-String -Pattern 'Bicep CLI version (\d+\.\d+\.\d+)' | ForEach-Object { $_.Matches.Groups[1].Value }
    }
    catch {
        Write-Warning "Bicep CLI is not installed. Please install it using 'az bicep install'."
        return
    }

    Write-Output "Installed Bicep version: $installedVersion"

    # Get the latest release version from GitHub
    try {
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Azure/bicep/releases/latest"
        $latestVersion = $latestRelease.tag_name.TrimStart('v')  # GitHub version starts with 'v'
    }
    catch {
        Write-Warning "Unable to fetch the latest release. Ensure you have internet connectivity."
        return
    }

    # Compare versions
    if ($installedVersion -eq $latestVersion) {
        Write-Output "Bicep CLI is up to date."
    }
    else {
        Write-Output "A new version of Bicep CLI is available. Latest Release: $latestVersion."
        $response = Read-Host "Do you want to update? (Y/N)"

        switch ($response.ToUpper()) {
            "Y" {
                Write-Output "Updating Bicep CLI..."
                try {
                    az bicep upgrade
                    Write-Output "Bicep CLI has been updated to version $latestVersion."
                }
                catch {
                    Write-Error "Failed to update Bicep CLI. Please try updating manually."
                }
            }
            "N" {
                Write-Output "Update canceled."
            }
            default {
                Write-Output "Invalid response. Please answer with Y or N."
            }
        }
    }
}

# Get Azure User/Service Principal Identity
function Get-AzIdentity {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SubscriptionId
    )

    try {
        # Get Identity Type
        $azIdentity = az account show --output json | ConvertFrom-Json
        $identityType = $azIdentity.user.type
        $signedInPrincipal = $azIdentity.user.name
        $azIdentityObjectId = $null

        if ($identityType -eq 'servicePrincipal') {
            $spDetails = az ad sp show --id $signedInPrincipal --output json | ConvertFrom-Json
            $spDisplayName = $spDetails.displayName
            $azIdentityObjectId = $spDetails.id

            Write-Host "Azure Identity Type...: Service Principal"
            Write-Host "Service Principal.....: $spDisplayName"
            $azIdentityName = $spDisplayName

        }
        elseif ($identityType -eq 'user') {
            $userDetails = az ad signed-in-user show --output json | ConvertFrom-Json
            $azUserAccountName = $signedInPrincipal
            $azIdentityObjectId = $userDetails.id
            $userDisplayName = if ($userDetails.displayName) { $userDetails.displayName } else { $azUserAccountName }
            Write-Host "Azure Identity Type...: User"
            Write-Host "User Account Email....: $azUserAccountName"
            Write-Host "Display Name..........: $userDisplayName"
            $azIdentityName = $azUserAccountName
        }
        else {
            Write-Warning "Unknown Azure Identity Type: $identityType"
            return $null
        }

        # Get Role Assignments
        $rbacAssignments = az role assignment list --assignee $signedInPrincipal --include-groups --include-inherited --output json 2>$null | ConvertFrom-Json
        if ($rbacAssignments) {
            $roles = $rbacAssignments | Select-Object -ExpandProperty roleDefinitionName -Unique
            Write-Host "RBAC Assignments......: $($roles -join ', ')"
        }
        else {
            Write-Warning "No RBAC assignments found for the identity."
            return $azIdentityName
        }

        # Evaluate Owner-scoped group memberships (subscription level only)
        if ($identityType -eq 'user' -and $azIdentityObjectId) {
            $subscriptionScope = "/subscriptions/$SubscriptionId"
            $ownerAssignments = az role assignment list --role "Owner" --scope $subscriptionScope --output json 2>$null | ConvertFrom-Json

            if ($ownerAssignments) {
                $directOwnerAssignments = $ownerAssignments | Where-Object { $_.principalId -eq $azIdentityObjectId }
                if ($directOwnerAssignments) {
                    Write-Host "Role Assignment.......: Direct assignment detected at: $subscriptionScope"
                }

                $ownerGroups = $ownerAssignments |
                Where-Object { $_.principalType -eq 'Group' } |
                Sort-Object -Property principalId -Unique

                $membershipMatches = @()
                if ($ownerGroups) {
                    foreach ($group in $ownerGroups) {
                        $groupId = $group.principalId
                        if (-not $groupId) { continue }
                        $membershipResult = az ad group member check --group $groupId --member-id $azIdentityObjectId --query value -o tsv 2>$null
                        if ($membershipResult -and $membershipResult.Trim().ToLower() -eq 'true') {
                            $membershipMatches += $group.principalName
                        }
                    }

                    if ($membershipMatches.Count -gt 0) {
                        Write-Host "Group Membership: $($membershipMatches -join ', ')"
                    }
                }

                if (-not $directOwnerAssignments -and $membershipMatches.Count -eq 0) {
                    if ($ownerGroups) {
                        Write-Warning "Identity is not a member of any Owner-scoped groups at $subscriptionScope."
                    }
                    else {
                        Write-Warning "No Owner role assignments backed by groups were found at $subscriptionScope."
                    }
                }
            }
            else {
                Write-Warning "Unable to retrieve Owner role assignments at $subscriptionScope."
            }
        }
        elseif ($identityType -eq 'servicePrincipal') {
            Write-Host "Skipping Owner group membership check for service principals."
        }

        # Return Azure Identity Name
        return $azIdentityName

    }
    catch {
        Write-Error "Failed to retrieve Azure identity information: $_"
        return $null
    }
}


# Generate Random Password
function New-RandomPassword {
    param (
        [Parameter(Mandatory)]
        [ValidateRange(8, 128)] # Ensure password length is within a reasonable range
        [int] $length,

        [ValidateRange(0, 128)] # Ensure non-alphanumeric count is valid
        [int] $amountOfNonAlphanumeric = 2
    )

    if ($amountOfNonAlphanumeric -gt $length) {
        throw "The number of non-alphanumeric characters cannot exceed the total password length."
    }

    $nonAlphaNumericChars = '!@$#%^&*()_-+=[{]};:<>|./?'
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'

    # Generate non-alphanumeric and alphanumeric parts
    $nonAlphaNumericPart = -join ((1..$amountOfNonAlphanumeric | ForEach-Object { $nonAlphaNumericChars | Get-Random }))
    $alphabetPart = -join ((1..($length - $amountOfNonAlphanumeric) | ForEach-Object { $alphabet | Get-Random }))

    # Combine and shuffle the password
    $password = ($alphabetPart + $nonAlphaNumericPart).ToCharArray() | Sort-Object { Get-Random }

    return -join $password
}

# Generate Random Password
function New-RandomPassword {
    param (
        [Parameter(Mandatory)]
        [int] $length,
        [int] $amountOfNonAlphanumeric = 2
    )

    $nonAlphaNumericChars = '!@$#%^&*()_-+=[{]};:<>|./?'
    $nonAlphaNumericPart = -join ((Get-Random -Count $amountOfNonAlphanumeric -InputObject $nonAlphaNumericChars.ToCharArray()))

    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $alphabetPart = -join ((Get-Random -Count ($length - $amountOfNonAlphanumeric) -InputObject $alphabet.ToCharArray()))

    $password = ($alphabetPart + $nonAlphaNumericPart).ToCharArray() | Sort-Object { Get-Random }

    return -join $password
}

function New-EntraIdADDSEnterpriseApplication {
    # Create Enterprise Application - 'Domain Controller Services'
    Write-Host "Checking for 'ADDS Domain Controller Services' Enterprise Application..."

    # Check if the Enterprise App exists
    $appId = "2565bd9d-da50-47d4-8b85-4c97f669dc36"
    $existingApp = az ad sp list --filter "appId eq '$appId'" --query "[].appId" -o tsv

    if (!($existingApp)) {
        # If the app does not exist, create it
        $newApp = az ad sp create --id $appId
        if ($newApp) {
            Write-Host "Enterprise App created successfully with App ID: $appId."
        }
        else {
            Write-Host "Failed to create Enterprise App."
        }
    }

    # Create Security Group - 'AAD DC Administrators'
    Write-Host "Checking for 'AAD DC Administrators' Security Group..."
    $GroupObject = az ad group show --group "AAD DC Administrators" --query "id" -o tsv
    if (!($GroupObject)) {
        az ad group create --display-name "AAD DC Administrators" --description "Delegated group to administer Microsoft Entra Domain Services" --mail-nickname "AADDCAdministrators" --output none
        Write-Host "'AAD DC Administrators' group created."
    }
    else {
        Write-Host "Admin group already exists."
        # Check if the signed-in user is a member of the group
        $currentUser = az ad signed-in-user show --query "id" -o tsv
        if ($currentUser) {
            $isMember = az ad group member check --group "AAD DC Administrators" --member-id $currentUser --query "value" -o tsv
            if ($isMember -eq "true") {
                Write-Host "Signed-in user ($azIdentityName) is a member of 'AAD DC Administrators'."
            }
            else {
                Write-Warning "Signed-in user ($azIdentityName) is NOT a member of 'AAD DC Administrators'."
            }
        }
        else {
            Write-Warning "Could not determine Signed-in user ($azIdentityName)."
        }
    }

}

# PowerShell Location Shortcode Map
$locationShortCodeMap = @{
    "eastus"             = "eus"
    "eastus2"            = "eus2"
    "eastus3"            = "eus3"
    "westus"             = "wus"
    "westus2"            = "wus2"
    "westus3"            = "wus3"
    "northcentralus"     = "ncus"
    "southcentralus"     = "scus"
    "centralus"          = "cus"
    "westcentralus"      = "wcus"
    "canadacentral"      = "canc"
    "canadaeast"         = "cane"
    "brazilsouth"        = "brs"
    "brazilseast"        = "bre"
    "brazilwest"         = "brw"
    "northeurope"        = "neu"
    "westeurope"         = "weu"
    "swedencentral"      = "sec"
    "swedensouth"        = "ses"
    "francecentral"      = "frc"
    "francesouth"        = "frs"
    "francewest"         = "frw"
    "germanywestcentral" = "gwc"
    "germanynorth"       = "gn"
    "germanysouth"       = "gs"
    "switzerlandnorth"   = "chn"
    "switzerlandwest"    = "chw"
    "switzerlandeast"    = "che"
    "norwayeast"         = "noe"
    "norwaywest"         = "now"
    "norwaysouth"        = "nos"
    "polandcentral"      = "plc"
    "spaincentral"       = "spc"
    "qatarcentral"       = "qtc"
    "uaenorth"           = "uan"
    "uaecentral"         = "uac"
    "southafricanorth"   = "san"
    "southafricawest"    = "saw"
    "southafricaeast"    = "sae"
    "eastasia"           = "ea"
    "southeastasia"      = "sea"
    "japaneast"          = "jpe"
    "japanwest"          = "jpw"
    "japancentral"       = "jpc"
    "australiaeast"      = "aue"
    "australiasoutheast" = "ause"
    "australiacentral"   = "auc"
    "australiacentral2"  = "auc2"
    "australiawest"      = "auw"
    "centralindia"       = "cin"
    "southindia"         = "sin"
    "westindia"          = "win"
    "koreacentral"       = "korc"
    "koreasouth"         = "kors"
    "koreacentral2"      = "korc2"
    "chinaeast3"         = "ce3"
    "chinanorth3"        = "cn3"
    "indonesiacentral"   = "idc"
    "malaysiawest"       = "myw"
    "newzealandnorth"    = "nzn"
    "taiwannorth"        = "twn"
    "israelcentral"      = "ilc"
    "mexicocentral"      = "mxc"
    "greececentral"      = "grc"
    "finlandcentral"     = "fic"
    "austriaeast"        = "ate"
    "belgiumcentral"     = "bec"
    "denmarkeast"        = "dke"
    "italynorth"         = "itn"
    "usgovvirginia"      = "usgv"
    "usgovarizona"       = "usga"
    "usgovtexas"         = "usgt"
    "usgoviowa"          = "usgi"
}

# Create Deployment Guid for Tracking in Azure
$deployGuid = (New-Guid).Guid

# Check Azure CLI
Get-AzCliVersion

# Check Azure Bicep Version
Get-BicepVersion

# Service Principal Authentication
if ($servicePrincipalAuthentication) {
    if (-not $spAuthCredentialFile) {
        Write-Output `r "Enter Service Principal Details:"
        $spAppId = Read-Host "Service Principal App Id"
        $spAppSecret = Read-Host "Service Principal App Secret" -AsSecureString
        $spTenantId = Read-Host "Service Principal Tenant Id"
    }
    else {
        try {
            $spAuthCredential = Get-Content -Path $spAuthCredentialFile | ConvertFrom-Json
            $spAppId = $spAuthCredential.spAppId
            $spAppSecret = $spAuthCredential.spAppSecret
            $spTenantId = $spAuthCredential.spTenantId
        }
        catch {
            Write-Error "Failed to parse Service Principal authentication file: $_"
            exit 1
        }
    }

    # Authenticate using Service Principal
    Write-Output `r "Authenticating with Azure - Service Principal..." `r
    az login --service-principal -u $spAppId -p $spAppSecret --tenant $spTenantId --output none

    # Validate Role Assignments
    $spRoleAssignments = az role assignment list --assignee $spAppId --output json 2>$null | ConvertFrom-Json
    if (-not $spRoleAssignments) {
        Write-Warning "Service Principal lacks role assignments. Assign appropriate roles before proceeding."
        exit 1
    }
}

if (!$servicePrincipalAuthentication) {
    # Authenticate using Azure CLI
    Write-Output `r "Authenticating with Azure - User Authentication..."
    az login --output none --only-show-errors
}

# Get Azure Identity, Required for Deployment Tags (DeployedBy:)
$azIdentityName = Get-AzIdentity -SubscriptionId $subscriptionId
if (-not $azIdentityName) {
    Write-Error "Unable to determine Azure identity and/or insufficient RBAC permissions. Exiting."
    exit 1
}

# Change Azure Subscription
Write-Output `r "Updating Azure Subscription context to $subscriptionId"
az account set --subscription $subscriptionId --output none

# Check and Create Domain Controller Services
New-EntraIdADDSEnterpriseApplication


Write-Output `r "Pre Flight Variable Validation:"
Write-Output "Deployment Guid......: $deployGuid"
Write-Output "Location.............: $location"
Write-Output "Location Short Code..: $($locationShortCodeMap.$location)"
Write-Output "Environment..........: $environmentType"

if ($deploy) {
    $deployStartTime = Get-Date -Format 'HH:mm:ss'

    # Deploy Bicep Template
    $azDeployGuidLink = "`e]8;;https://portal.azure.com/#view/HubsExtension/DeploymentDetailsBlade/~/overview/id/%2Fsubscriptions%2F$subscriptionId%2Fproviders%2FMicrosoft.Resources%2Fdeployments%2Fiac-$deployGuid`e\iac-$deployGuid`e]8;;`e\"
    Write-Output `r "> Deployment [$azDeployGuidLink] Started at $deployStartTime"

    az deployment $targetScope create `
        --name iac-$deployGuid `
        --location $location `
        --template-file ./main.bicep `
        --parameters ./main.bicepparam `
        --parameters `
        location=$location `
        locationShortCode=$($locationShortCodeMap.$location) `
        customerName=$customerName `
        environmentType=$environmentType `
        deployedBy=$azIdentityName `
        --confirm-with-what-if `
        --output none

    $deployEndTime = Get-Date -Format 'HH:mm:ss'
    $timeDifference = New-TimeSpan -Start $deployStartTime -End $deployEndTime ; $deploymentDuration = "{0:hh\:mm\:ss}" -f $timeDifference
    Write-Output `r "> Deployment [$azDeployGuidLink] Started at $deployEndTime - Deployment Duration: $deploymentDuration"

}
