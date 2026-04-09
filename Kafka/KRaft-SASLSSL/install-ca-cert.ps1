# ============================================================================
# Install Kafka CA Certificate to Windows Certificate Store
# ============================================================================
# This script installs the Kafka CA certificate to the Windows Root Certificate Store
# allowing SSL/TLS connections without certificate verification errors.
#
# IMPORTANT: Run this script as Administrator
# ============================================================================

param(
    [string]$CertPath = "$PSScriptRoot\secrets\ca-cert.pem"
)

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Kafka CA Certificate Installation" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host ""
    Write-Host "To run as Administrator:" -ForegroundColor Yellow
    Write-Host "  1. Right-click on PowerShell" -ForegroundColor Yellow
    Write-Host "  2. Select 'Run as Administrator'" -ForegroundColor Yellow
    Write-Host "  3. Navigate to: $PSScriptRoot" -ForegroundColor Yellow
    Write-Host "  4. Run: .\install-ca-cert.ps1" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Check if certificate file exists
if (-not (Test-Path $CertPath)) {
    Write-Host "ERROR: Certificate file not found at: $CertPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Make sure you have generated the certificates first:" -ForegroundColor Yellow
    Write-Host "  cd scripts" -ForegroundColor Yellow
    Write-Host "  ./generate_ssl_certs.sh" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host "Certificate file found: $CertPath" -ForegroundColor Green
Write-Host ""

# Read certificate content
$certContent = Get-Content $CertPath -Raw

# Check if certificate is already installed
$existingCert = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { 
    $_.Subject -like "*KafkaCA*" -or $_.Issuer -like "*KafkaCA*" 
}

if ($existingCert) {
    Write-Host "Certificate already installed in Windows Certificate Store!" -ForegroundColor Yellow
    Write-Host "Thumbprint: $($existingCert.Thumbprint)" -ForegroundColor Yellow
    Write-Host "Subject: $($existingCert.Subject)" -ForegroundColor Yellow
    Write-Host ""
    
    $response = Read-Host "Do you want to reinstall? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "Installation cancelled." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "Removing existing certificate..." -ForegroundColor Yellow
    $existingCert | Remove-Item -Force
    Write-Host "Existing certificate removed." -ForegroundColor Green
    Write-Host ""
}

# Import certificate to Root store
try {
    Write-Host "Installing certificate to Windows Root Certificate Store..." -ForegroundColor Cyan
    
    # Use certutil to import
    $certutilResult = certutil -addstore "Root" $CertPath 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Certificate installed successfully!" -ForegroundColor Green
        Write-Host ""
        
        # Verify installation
        $installedCert = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { 
            $_.Subject -like "*KafkaCA*" -or $_.Issuer -like "*KafkaCA*" 
        } | Select-Object -First 1
        
        if ($installedCert) {
            Write-Host "Verification successful!" -ForegroundColor Green
            Write-Host "  Thumbprint: $($installedCert.Thumbprint)" -ForegroundColor White
            Write-Host "  Subject: $($installedCert.Subject)" -ForegroundColor White
            Write-Host "  Issuer: $($installedCert.Issuer)" -ForegroundColor White
            Write-Host "  Valid From: $($installedCert.NotBefore)" -ForegroundColor White
            Write-Host "  Valid To: $($installedCert.NotAfter)" -ForegroundColor White
            Write-Host ""
        }
        
        Write-Host "==================================================================" -ForegroundColor Green
        Write-Host "  Installation Complete!" -ForegroundColor Green
        Write-Host "==================================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "You can now run the SASL/SSL tests:" -ForegroundColor Cyan
        Write-Host "  dotnet test --filter ""Auth05_SaslSsl_ShouldSucceed""" -ForegroundColor White
        Write-Host ""
        
    } else {
        Write-Host "ERROR: Failed to install certificate!" -ForegroundColor Red
        Write-Host "certutil output: $certutilResult" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "ERROR: Failed to install certificate!" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

# Instructions for uninstalling
Write-Host "To uninstall this certificate later, run:" -ForegroundColor Yellow
Write-Host "  .\uninstall-ca-cert.ps1" -ForegroundColor White
Write-Host ""
