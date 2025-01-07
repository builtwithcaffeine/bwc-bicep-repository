param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Subscription ID is required.")]
    [string] $subscriptionId,

    [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Location is required.")]
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

    [Parameter(Mandatory = $true, Position = 2, HelpMessage = "Choose between 'Windows' or 'Linux'")]
    [ValidateSet('.\main-windows.bicep', '.\main-linux.bicep')]
    [string] $bicepFile,

    [Parameter(Mandatory = $false, Position = 3, HelpMessage = "Enabled Bicep Deployment")]
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

# Log into Azure
Write-Output "> Logging into Azure for $subscriptionId"
az config set core.login_experience_v2=off --only-show-errors

Write-Output "> Setting subscription to $subscriptionId"
az account set --subscription $subscriptionId

Write-Output `r "Pre Flight Variable Validation"
Write-Output "Deployment Guid......: $deployGuid"
Write-Output "Location.............: $location"
Write-Output "Location Shortcode...: $shortcode"

if ($deploy) {
    $deployStartTime = Get-Date -Format 'HH:mm:ss'

    # Deploy Bicep Template
    $azDeployGuidLink = "`e]8;;https://portal.azure.com/#view/HubsExtension/DeploymentDetailsBlade/~/overview/id/%2Fsubscriptions%2F$subscriptionId%2Fproviders%2FMicrosoft.Resources%2Fdeployments%2Fiac-bicep-$deployGuid`e\iac-bicep-$deployGuid`e]8;;`e\"
    Write-Output `r "> Deployment [$azDeployGuidLink] Started at $deployStartTime"

    az deployment sub create `
        --name iac-bicep-$deployGuid `
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
}

    $deployEndTime = Get-Date -Format 'HH:mm:ss'
    $timeDifference = New-TimeSpan -Start $deployStartTime -End $deployEndTime ; $deploymentDuration = "{0:hh\:mm\:ss}" -f $timeDifference
    Write-Output `r "> Deployment [iac-bicep-$deployGuid] Started at $deployEndTime - Deployment Duration: $deploymentDuration"
