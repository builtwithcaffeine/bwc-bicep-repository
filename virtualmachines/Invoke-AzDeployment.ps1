<#
.SYNOPSIS
    Script to deploy Azure resources using Bicep templates.

.DESCRIPTION
    This script facilitates the deployment of Azure resources using Bicep templates. It includes functions for generating random passwords, checking and updating the Bicep CLI version, and mapping Azure locations to shortcodes. The script also handles Azure login, subscription setting, and deployment tracking.

.PARAMETER targetScope
    The target scope for the deployment. Valid values are 'tenant', 'mgmt', and 'sub'.

.PARAMETER subscriptionId
    The subscription ID where the resources will be deployed.

.PARAMETER location
    The Azure region where the resources will be deployed. Valid values include various Azure regions like "eastus", "westus", "northeurope", etc.

.PARAMETER bicepFile
    The Bicep template file to be used for deployment. Valid values are '.\main-windows.bicep' and '.\main-linux.bicep'.

.PARAMETER deploy
    A switch to enable or disable the deployment. If specified, the deployment will be executed.

.FUNCTIONS
    New-RandomPassword
        Generates a random password with a specified length and number of non-alphanumeric characters.

    Get-BicepVersion
        Checks the installed version of the Bicep CLI and compares it with the latest release version from GitHub. Prompts the user to update if a newer version is available.

.NOTES
    Author: [Your Name]
    Date: [Date]
    Version: 1.0

.EXAMPLE
    .\Invoke-AzDeployment.ps1 -targetScope 'sub' -subscriptionId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -location 'eastus' -bicepFile '.\main-windows.bicep' -deploy

    This example deploys resources to the 'eastus' region using the 'main-windows.bicep' template file in the specified subscription.

#>


param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Deployment Guid is required")]
    [validateSet('tenant', 'mgmt', 'sub')] [string] $targetScope,

    [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Subscription ID is required.")]
    [string] $subscriptionId,

    [Parameter(Mandatory = $true, Position = 2, HelpMessage = "Location is required.")]
    [ValidateSet(
        "eastus", "eastus2", "eastus3", "westus", "westus2", "westus3",
        "northcentralus", "southcentralus", "centralus",
        "canadacentral", "canadaeast", "brazilsouth",
        "northeurope", "westeurope", "uksouth", "ukwest",
        "francecentral", "francesouth", "germanywestcentral",
        "germanynorth", "switzerlandnorth", "switzerlandwest",
        "norwayeast", "norwaywest", "swedencentral", "swedensouth",
        "polandcentral", "qatarcentral", "uaenorth", "uaecentral",
        "southafricanorth", "southafricawest", "eastasia", "southeastasia",
        "japaneast", "japanwest", "australiaeast", "australiasoutheast",
        "australiacentral", "australiacentral2", "centralindia", "southindia",
        "westindia", "koreacentral", "koreasouth",
        "chinaeast", "chinanorth", "chinaeast2", "chinanorth2",
        "usgovvirginia", "usgovarizona", "usgovtexas", "usgoviowa"
    )][string]$location,

    [Parameter(Mandatory = $true, Position = 3, HelpMessage = "Choose between 'Windows' or 'Linux'")]
    [ValidateSet('.\main-windows-machineOnly.bicep', '.\main-windows-vminsights.bicep',
                 '.\main-linux-machineOnly.bicep', '.\main-linux-vminsights.bicep'
    )]
    [string] $bicepFile,

    [Parameter(Mandatory = $false, Position = 4, HelpMessage = "Enabled Bicep Deployment")]
    [switch] $deploy
)

# PowerShell Functions

# Function - New-RandomPassword
function New-RandomPassword {
    param (
        [Parameter(Mandatory)]
        [int] $length,
        [int] $amountOfNonAlphanumeric = 2
    )

    $nonAlphaNumericChars = '!@$'
    $nonAlphaNumericPart = -join ((Get-Random -Count $amountOfNonAlphanumeric -InputObject $nonAlphaNumericChars.ToCharArray()))

    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $alphabetPart = -join ((Get-Random -Count ($length - $amountOfNonAlphanumeric) -InputObject $alphabet.ToCharArray()))

    $password = ($alphabetPart + $nonAlphaNumericPart).ToCharArray() | Sort-Object { Get-Random }

    return -join $password
}

# Function - Get-BicepVersion
function Get-BicepVersion {

    #
    Write-Output `r "Checking for Bicep CLI..."

    # Get the installed version of Bicep
    $installedVersion = az bicep version --only-show-errors | Select-String -Pattern 'Bicep CLI version (\d+\.\d+\.\d+)' | ForEach-Object { $_.Matches.Groups[1].Value }

    if (-not $installedVersion) {
        Write-Output "Bicep CLI is not installed or version couldn't be determined."
        return
    }

    Write-Output "Installed Bicep version: $installedVersion"

    # Get the latest release version from GitHub
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Azure/bicep/releases/latest"

    if (-not $latestRelease) {
        Write-Output "Unable to fetch the latest release."
        return
    }

    $latestVersion = $latestRelease.tag_name.TrimStart('v')  # GitHub version starts with 'v'

    # Compare versions
    if ($installedVersion -eq $latestVersion) {
        Write-Output "Bicep is up to date." `r
    }
    else {
        Write-Output "A new version of Bicep is available. Latest Release is: $latestVersion."
        # Prompt for user input (Yes/No)
        $response = Read-Host "Do you want to update? (Y/N)"

        if ($response -match '^[Yy]$') {
            Write-Output "" # Required for Verbose Spacing
            az bicep upgrade
            Write-Output "Bicep has been updated to version $latestVersion."
        }
        elseif ($response -match '^[Nn]$') {
            Write-Output "Update canceled."
        }
        else {
            Write-Output "Invalid response. Please answer with Y or N."
        }
    }
}

# PowerShell Location Shortcode Map
$LocationShortcodeMap = @{
    "eastus"             = "eus"
    "eastus2"            = "eus2"
    "eastus3"            = "eus3"
    "westus"             = "wus"
    "westus2"            = "wus2"
    "westus3"            = "wus3"
    "northcentralus"     = "ncus"
    "southcentralus"     = "scus"
    "centralus"          = "cus"
    "canadacentral"      = "canc"
    "canadaeast"         = "cane"
    "brazilsouth"        = "brs"
    "northeurope"        = "neu"
    "westeurope"         = "weu"
    "uksouth"            = "uks"
    "ukwest"             = "ukw"
    "francecentral"      = "frc"
    "francesouth"        = "frs"
    "germanywestcentral" = "gwc"
    "germanynorth"       = "gn"
    "switzerlandnorth"   = "chn"
    "switzerlandwest"    = "chw"
    "norwayeast"         = "noe"
    "norwaywest"         = "now"
    "swedencentral"      = "sec"
    "swedensouth"        = "ses"
    "polandcentral"      = "plc"
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
    "chinaeast"          = "ce"
    "chinanorth"         = "cn"
    "chinaeast2"         = "ce2"
    "chinanorth2"        = "cn2"
    "usgovvirginia"      = "usgv"
    "usgovarizona"       = "usga"
    "usgovtexas"         = "usgt"
    "usgoviowa"          = "usgi"
}

$shortcode = $LocationShortcodeMap[$location]

# Create Deployment Guid for Tracking in Azure
$deployGuid = (New-Guid).Guid

# Get User Public IP Address
$publicIp = (Invoke-RestMethod -Uri 'https://ifconfig.me')

# Virtual Machine Credentials
$vmUserName = 'azurevmuser'
$vmUserPassword = New-RandomPassword -length 16

# Check Azure Bicep Version
Get-BicepVersion

# Azure CLI Authentication
az login --output none --only-show-errors

# Configure Azure Cli User Experience
Write-Output "> Logging into Azure for $subscriptionId"
az config set core.login_experience_v2=off --only-show-errors

Write-Output "> Setting subscription to $subscriptionId"
az account set --subscription $subscriptionId

Write-Output `r "Pre Flight Variable Validation"
Write-Output "Bicep File............: $bicepFile"
Write-Output "Deployment Guid......: $deployGuid"
Write-Output "Location.............: $location"
Write-Output "Location Shortcode...: $shortcode"

if ($deploy) {
    $deployStartTime = Get-Date -Format 'HH:mm:ss'

    # Deploy Bicep Template
    $azDeployGuidLink = "`e]8;;https://portal.azure.com/#view/HubsExtension/DeploymentDetailsBlade/~/overview/id/%2Fsubscriptions%2F$subscriptionId%2Fproviders%2FMicrosoft.Resources%2Fdeployments%2Fiac-$deployGuid`e\iac-$deployGuid`e]8;;`e\"
    Write-Output `r "> Deployment [$azDeployGuidLink] Started at $deployStartTime"

    az deployment sub create `
        --name iac-$deployGuid `
        --location $location `
        --template-file $bicepFile `
        --parameters `
            location=$location `
            locationShortCode=$shortcode `
            publicIp=$publicIp `
            vmUserName=$vmUserName `
            vmUserPassword=$vmUserPassword `
        --confirm-with-what-if `
        --output none

    $deployEndTime = Get-Date -Format 'HH:mm:ss'
    $timeDifference = New-TimeSpan -Start $deployStartTime -End $deployEndTime ; $deploymentDuration = "{0:hh\:mm\:ss}" -f $timeDifference
    Write-Output `r "> Deployment [iac-$deployGuid] Started at $deployEndTime - Deployment Duration: $deploymentDuration"

    Write-Output `r "Credentials"
    Write-Output "VM Username: $vmUserName"
    Write-Output "VM Password: $vmUserPassword"
}