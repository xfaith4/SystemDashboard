#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generate self-signed SSL certificate for SystemDashboard HTTPS.

.DESCRIPTION
    Creates a self-signed certificate for development and testing.
    For production use, obtain a certificate from a trusted CA like Let's Encrypt.

.PARAMETER DnsNames
    DNS names to include in certificate (e.g., localhost, hostname, IP).

.PARAMETER OutputPath
    Directory where certificate files will be saved. Default is current directory.

.PARAMETER ValidityYears
    How many years the certificate should be valid. Default is 1.

.PARAMETER Format
    Certificate format: 'pem' for Linux/OpenSSL, 'pfx' for Windows/IIS. Default is 'pem'.

.PARAMETER Password
    Password for PFX export (only used with -Format pfx).

.EXAMPLE
    .\generate-ssl-cert.ps1
    # Creates cert.pem and key.pem for localhost

.EXAMPLE
    .\generate-ssl-cert.ps1 -DnsNames "localhost","dashboard.local","192.168.1.100"
    # Creates certificate valid for multiple names

.EXAMPLE
    .\generate-ssl-cert.ps1 -Format pfx -Password "MyPassword123!"
    # Creates dashboard.pfx for Windows

.NOTES
    Requires: OpenSSL (for PEM format) or Windows PowerShell 5.1+ (for PFX format)
#>

[CmdletBinding()]
param(
    [string[]]$DnsNames = @("localhost", "127.0.0.1"),
    [string]$OutputPath = ".",
    [int]$ValidityYears = 1,
    [ValidateSet('pem', 'pfx')]
    [string]$Format = 'pem',
    [string]$Password = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$OutputPath = Resolve-Path $OutputPath

Write-Host "Generating self-signed certificate for SystemDashboard..." -ForegroundColor Cyan
Write-Host "DNS Names: $($DnsNames -join ', ')" -ForegroundColor Gray
Write-Host "Validity: $ValidityYears year(s)" -ForegroundColor Gray
Write-Host "Format: $Format" -ForegroundColor Gray
Write-Host ""

if ($Format -eq 'pem') {
    # Generate PEM format using OpenSSL
    $certFile = Join-Path $OutputPath "cert.pem"
    $keyFile = Join-Path $OutputPath "key.pem"
    
    # Check if OpenSSL is available
    $opensslCmd = Get-Command openssl -ErrorAction SilentlyContinue
    if (-not $opensslCmd) {
        Write-Error @"
OpenSSL is required to generate PEM certificates.

Install options:
  - Windows: choco install openssl  (via Chocolatey)
  - Linux: apt-get install openssl or yum install openssl
  - macOS: brew install openssl

Or use -Format pfx for Windows-native certificate.
"@
        exit 1
    }
    
    # Create OpenSSL config with SAN
    $configFile = Join-Path $env:TEMP "openssl-san.cnf"
    $sanEntries = ($DnsNames | ForEach-Object { 
        if ($_ -match '^\d+\.\d+\.\d+\.\d+$') {
            "IP:$_"
        } else {
            "DNS:$_"
        }
    }) -join ','
    
    $opensslConfig = @"
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=State
L=City
O=SystemDashboard
OU=IT
CN=$($DnsNames[0])

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = $sanEntries
"@
    
    Set-Content -Path $configFile -Value $opensslConfig
    
    try {
        Write-Host "Generating private key and certificate..." -ForegroundColor Yellow
        
        # Generate certificate
        $opensslArgs = @(
            'req', '-x509', '-newkey', 'rsa:4096', '-nodes',
            '-keyout', $keyFile,
            '-out', $certFile,
            '-days', ($ValidityYears * 365).ToString(),
            '-config', $configFile,
            '-extensions', 'v3_req'
        )
        
        & openssl @opensslArgs 2>&1 | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "OpenSSL certificate generation failed"
            exit 1
        }
        
        Write-Host ""
        Write-Host "✓ Certificate generated successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Certificate file: $certFile" -ForegroundColor Green
        Write-Host "Private key file: $keyFile" -ForegroundColor Green
        Write-Host ""
        Write-Host "To use with Flask:" -ForegroundColor Cyan
        Write-Host "  python app.py --cert $certFile --key $keyFile" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To use with Gunicorn:" -ForegroundColor Cyan
        Write-Host "  gunicorn --certfile $certFile --keyfile $keyFile app:app" -ForegroundColor Gray
        Write-Host ""
        
        # Display certificate info
        Write-Host "Certificate Information:" -ForegroundColor Cyan
        & openssl x509 -in $certFile -noout -text | Select-String -Pattern "Subject:|Issuer:|Not Before|Not After|DNS:|IP Address:"
        
    }
    finally {
        # Clean up temp config
        if (Test-Path $configFile) {
            Remove-Item $configFile -Force
        }
    }
    
} elseif ($Format -eq 'pfx') {
    # Generate PFX format using Windows PowerShell
    
    if ($PSVersionTable.PSVersion.Major -lt 5 -or -not $IsWindows) {
        Write-Error "PFX format requires Windows PowerShell 5.1 or later"
        exit 1
    }
    
    $pfxFile = Join-Path $OutputPath "dashboard.pfx"
    $cerFile = Join-Path $OutputPath "dashboard.cer"
    
    # Prompt for password if not provided
    if (-not $Password) {
        $securePassword = Read-Host "Enter password for PFX file" -AsSecureString
    } else {
        $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    }
    
    Write-Host "Creating self-signed certificate..." -ForegroundColor Yellow
    
    # Calculate expiration date
    $notAfter = (Get-Date).AddYears($ValidityYears)
    
    # Create certificate
    $cert = New-SelfSignedCertificate `
        -DnsName $DnsNames `
        -CertStoreLocation "cert:\CurrentUser\My" `
        -NotAfter $notAfter `
        -KeyExportPolicy Exportable `
        -KeySpec KeyExchange `
        -KeyLength 4096 `
        -KeyAlgorithm RSA `
        -HashAlgorithm SHA256 `
        -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
    
    # Export with private key (PFX)
    Write-Host "Exporting PFX file..." -ForegroundColor Yellow
    Export-PfxCertificate -Cert $cert -FilePath $pfxFile -Password $securePassword | Out-Null
    
    # Export without private key (CER) for client import
    Write-Host "Exporting CER file..." -ForegroundColor Yellow
    Export-Certificate -Cert $cert -FilePath $cerFile | Out-Null
    
    # Remove from certificate store (optional - keep if you want it in store)
    # Remove-Item "cert:\CurrentUser\My\$($cert.Thumbprint)" -Force
    
    Write-Host ""
    Write-Host "✓ Certificate generated successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Certificate files:" -ForegroundColor Green
    Write-Host "  PFX (with private key): $pfxFile" -ForegroundColor Green
    Write-Host "  CER (public only):      $cerFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "Certificate Details:" -ForegroundColor Cyan
    Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
    Write-Host "  Subject:    $($cert.Subject)" -ForegroundColor Gray
    Write-Host "  Valid From: $($cert.NotBefore)" -ForegroundColor Gray
    Write-Host "  Valid To:   $($cert.NotAfter)" -ForegroundColor Gray
    Write-Host "  DNS Names:  $($cert.DnsNameList.Unicode -join ', ')" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To use with IIS:" -ForegroundColor Cyan
    Write-Host "  1. Import $pfxFile into Local Machine\Personal store" -ForegroundColor Gray
    Write-Host "  2. Configure HTTPS binding with this certificate" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To trust this certificate (development only):" -ForegroundColor Cyan
    Write-Host "  Import $cerFile into 'Trusted Root Certification Authorities'" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "⚠️  Warning: This is a self-signed certificate suitable for development only." -ForegroundColor Yellow
Write-Host "   For production, obtain a certificate from a trusted CA like Let's Encrypt." -ForegroundColor Yellow
Write-Host ""
