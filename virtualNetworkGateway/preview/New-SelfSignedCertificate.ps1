# ======================================
#  Azure VPN Certificate Generator
#  Creates and Exports Root & Leaf Certs
#  Outbound Certs include Private Key
# ======================================
# Microsoft Docs: https://learn.microsoft.com/en-us/azure/vpn-gateway/site-to-site-certificate-authentication-gateway-portal#generatecert

param (
    [string]$ExportPath = "C:\Certs"
)

# Ensure the export directory exists
if (!(Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath | Out-Null
}

# Generate a random password for PFX export
$PfxPasswordPlain = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
$PfxPassword = $PfxPasswordPlain | ConvertTo-SecureString -AsPlainText -Force

# Save PFX password to a file
$AuthFilePath = "$ExportPath\auth_psk.txt"
$PfxPasswordPlain | Out-File -FilePath $AuthFilePath -Encoding UTF8

# Create Root Certificate
$rootCertParams = @{
    Type              = 'Custom'
    Subject           = 'CN=VPNRootCA01'
    KeySpec           = 'Signature'
    KeyExportPolicy   = 'Exportable'
    KeyUsage          = 'CertSign'
    KeyUsageProperty  = 'Sign'
    KeyLength         = 2048
    HashAlgorithm     = 'sha256'
    NotAfter          = (Get-Date).AddMonths(120)
    CertStoreLocation = 'Cert:\CurrentUser\My'
    TextExtension     = @('2.5.29.19={critical}{text}ca=1&pathlength=4')
}
$rootCert = New-SelfSignedCertificate @rootCertParams

# Function to create leaf certificates
function New-LeafCertificate {
    param (
        [string]$subject
    )
    $params = @{
        Type              = 'Custom'
        Subject           = "CN=$subject"
        KeySpec           = 'Signature'
        KeyExportPolicy   = 'Exportable'
        KeyLength         = 2048
        HashAlgorithm     = 'sha256'
        NotAfter          = (Get-Date).AddMonths(120)
        CertStoreLocation = 'Cert:\CurrentUser\My'
        Signer            = $rootCert
        TextExtension     = @('2.5.29.37={text}1.3.6.1.5.5.7.3.2,1.3.6.1.5.5.7.3.1')
    }
    return New-SelfSignedCertificate @params
}

# Create Outbound and Inbound Certificates
$outboundCert = New-LeafCertificate -subject "Outbound-certificate"
$inboundCert = New-LeafCertificate -subject "Inbound-certificate"

# Function to export certificates
function Export-Certificate {
    param (
        [Parameter(Mandatory)]
        [string]$certThumbprint,
        [string]$exportPath,
        [switch]$IncludePrivateKey
    )

    try {
        $cert = Get-Item "Cert:\CurrentUser\My\$certThumbprint"

        # Export private key as PFX if requested
        if ($IncludePrivateKey) {
            $pfxPath = "$exportPath.pfx"
            Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $PfxPassword | Out-Null
        }

        # Export as CER without private key (PEM format)
        $cerPath = "$exportPath.cer"

        # Format the PEM certificate content
        $content = @(
            '-----BEGIN CERTIFICATE-----',
            [System.Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks'),
            '-----END CERTIFICATE-----'
        )

        # Write the PEM certificate to the file
        [System.IO.File]::WriteAllText($cerPath, $content -join "`n")
    } catch {
        Write-Error "Failed to export certificate with thumbprint $certThumbprint: $_"
    }
}

Write-Output "-------------------------------------"
Write-Output " Azure Virtual Network Gateway Certs "
Write-Output "-------------------------------------"

# Export outbound certificate with private key
Export-Certificate -certThumbprint $outboundCert.Thumbprint -exportPath "$ExportPath\Outbound" -IncludePrivateKey
Write-Output "Outbound Certificate, Created and Exported with PFX"

# Export inbound and root certificates without private key
Export-Certificate -certThumbprint $inboundCert.Thumbprint -exportPath "$ExportPath\Inbound"
Write-Output "Inbound Certificate, Created and Exported as CER"

Export-Certificate -certThumbprint $rootCert.Thumbprint -exportPath "$ExportPath\Root"
Write-Output "Root Certificate, Created and Exported as CER"

Write-Output "Certificates have been created and exported to $ExportPath"
Write-Output "Inbound Certificate Subject Name: $($inboundCert.Subject)"