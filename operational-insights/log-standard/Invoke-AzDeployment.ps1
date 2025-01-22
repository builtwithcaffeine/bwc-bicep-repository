<#
.SYNOPSIS
    This script deploys Azure resources using Bicep templates.

.DESCRIPTION
    The script performs the following tasks:
    - Validates input parameters.
    - Checks if Azure CLI is installed.
    - Authenticates the user with Azure CLI.
    - Sets the Azure subscription context.
    - Generates a deployment GUID.
    - Maps Azure location to short codes.
    - Optionally deploys the Bicep template if the deploy switch is provided.

.PARAMETER targetScope
    The scope of the deployment. Valid values are 'tenant', 'mg', 'sub'.

.PARAMETER subscriptionId
    The Azure Subscription ID where the deployment will take place.

.PARAMETER environmentType
    The environment type for the deployment. Valid values are 'dev', 'acc', 'prod'.

.PARAMETER location
    The Azure location for the deployment. Valid values are various Azure regions.

.PARAMETER deploy
    A switch to execute the infrastructure deployment.

.EXAMPLE
    .\Invoke-Deployment.ps1 -targetScope 'sub' -subscriptionId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -environmentType 'dev' -location 'eastus' -deploy

.NOTES
    Ensure that Azure CLI is installed and you are logged in before running this script.
#>

param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Deployment Guid is required")]
    [validateSet('tenant', 'mgmt', 'sub')] [string] $targetScope,

    [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Azure Subscription Id is required")]
    [string] $subscriptionId,

    [Parameter(Mandatory = $true, Position = 2, HelpMessage = "Environment Type is required")]
    [validateSet('dev', 'acc', 'prod')][string] $environmentType,

    [Parameter(Mandatory = $true, Position = 3, HelpMessage = "Azure Location is required")]
    [validateSet("eastus", "eastus2", "westus", "westus2", "centralus", "northcentralus", "southcentralus", 
        "westcentralus", "westus3", "eastus3", "northeurope", "westeurope", "swedencentral", "swedensouth",
        "southeastasia", "eastasia", "japaneast", "japanwest", "australiaeast", "australiasoutheast", 
        "australiacentral", "australiacentral2", "brazilsouth", "southindia", "centralindia", "westindia", 
        "canadacentral", "canadaeast", "uksouth", "ukwest", "koreacentral", "koreasouth", "francecentral", 
        "francesouth", "uaecentral", "uaenorth", "southafricanorth", "southafricawest", "southafricaeast",
        "norwayeast", "norwaywest", "germanynorth", "germanywestcentral", "switzerlandnorth", "switzerlandwest",
        "polandcentral", "spaincentral", "qatarcentral", "chinanorth3", "chinaeast3", "indonesiacentral", 
        "malaysiawest", "newzealandnorth", "taiwannorth", "israelcentral", "mexicocentral", "greececentral", 
        "finlandcentral", "austriaeast", "belgiumcentral", "denmarkeast", "norwaysouth", "italynorth")]
    [string] $location,

    [Parameter(Mandatory = $false, Position = 5, HelpMessage = "Execute Infrastructure Deployment")]
    [switch] $deploy
)

# Check if Azure CLI is installed
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI (az) is not installed. Please install it from https://aka.ms/azure-cli."
    exit 1
}

# Azure CLI Authentication
az login --output none --only-show-errors

# Change Azure Subscription
Write-Output "Updating Azure Subscription context to $subscriptionId"
az account set --subscription $subscriptionId --output none

# Check if user is logged in to Azure CLI
$azAccount = az account show --output json | ConvertFrom-Json
if (-not $azAccount) {
    Write-Error "You are not logged in to Azure CLI. Please run 'az login' to login."
    exit 1
}

# Retrieve the current Azure user account ID
$azUserAccountName = $azAccount.user.name

# Generate a deployment GUID
$deployGuid = [guid]::NewGuid().ToString()

# Define location short codes
$locationShortCodes = @{
    "eastus"             = "eus"
    "eastus2"            = "eus2"
    "westus"             = "wus"
    "westus2"            = "wus2"
    "centralus"          = "cus"
    "northcentralus"     = "ncus"
    "southcentralus"     = "scus"
    "westcentralus"      = "wcus"
    "westus3"            = "wus3"
    "eastus3"            = "eus3"
    "northeurope"        = "neu"
    "westeurope"         = "weu"
    "swedencentral"      = "sec"
    "swedensouth"        = "ses"
    "southeastasia"      = "sea"
    "eastasia"           = "eas"
    "japaneast"          = "jpe"
    "japanwest"          = "jpw"
    "australiaeast"      = "aue"
    "australiasoutheast" = "ause"
    "australiacentral"   = "auc"
    "australiacentral2"  = "auc2"
    "brazilsouth"        = "brs"
    "southindia"         = "sai"
    "centralindia"       = "cin"
    "westindia"          = "win"
    "canadacentral"      = "cac"
    "canadaeast"         = "cae"
    "uksouth"            = "uks"
    "ukwest"             = "ukw"
    "koreacentral"       = "krc"
    "koreasouth"         = "krs"
    "francecentral"      = "frc"
    "francesouth"        = "frs"
    "uaecentral"         = "uaec"
    "uaenorth"           = "uaen"
    "southafricanorth"   = "safn"
    "southafricawest"    = "safw"
    "southafricaeast"    = "safe"
    "switzerlandnorth"   = "chn"
    "switzerlandwest"    = "chw"
    "germanynorth"       = "gen"
    "germanywestcentral" = "gewc"
    "norwayeast"         = "noe"
    "norwaywest"         = "now"
    "norwaysouth"        = "nos"
    "polandcentral"      = "plc"
    "spaincentral"       = "spc"
    "qatarcentral"       = "qtc"
    "chinanorth3"        = "chn3"
    "chinaeast3"         = "che3"
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
}

Write-Output `r "Pre Flight Variable Validation:" `r
Write-Output "Deployment Guid......: $deployGuid"
Write-Output "Location.............: $location"
Write-Output "Location Short Code..: $($locationShortCodes.$location)"
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
        --parameters `
        location=$location `
        locationShortCode=$($locationShortCodes.$location) `
        environmentType=$environmentType `
        deployedBy=$azUserAccountName `
        --confirm-with-what-if `
        --output none

    $deployEndTime = Get-Date -Format 'HH:mm:ss'
    $timeDifference = New-TimeSpan -Start $deployStartTime -End $deployEndTime ; $deploymentDuration = "{0:hh\:mm\:ss}" -f $timeDifference
    Write-Output `r "> Deployment [iac-$deployGuid] Started at $deployEndTime - Deployment Duration: $deploymentDuration"
}
