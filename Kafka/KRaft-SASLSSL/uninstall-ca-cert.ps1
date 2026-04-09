# ============================================================================
# Uninstall Kafka CA Certificate from Windows Certificate Store
# ============================================================================
# This script removes the Kafka CA certificate from the Windows Root Certificate Store
#
# IMPORTANT: Run this script as Administrator
# ============================================================================

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Kafka CA Certificate Uninstallation" -ForegroundColor Cyan
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
    Write-Host "  4. Run: .\uninstall-ca-cert.ps1" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Find certificates
$certificates = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { 
    $_.Subject -like "*KafkaCA*" -or $_.Issuer -like "*KafkaCA*" 
}

if (-not $certificates) {
    Write-Host "No Kafka CA certificates found in the Windows Certificate Store." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Host "Found $($certificates.Count) Kafka CA certificate(s):" -ForegroundColor Cyan
Write-Host ""

foreach ($cert in $certificates) {
    Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor White
    Write-Host "  Subject: $($cert.Subject)" -ForegroundColor White
    Write-Host "  Issuer: $($cert.Issuer)" -ForegroundColor White
    Write-Host ""
}

$response = Read-Host "Do you want to remove these certificates? (y/N)"

if ($response -ne 'y' -and $response -ne 'Y') {
    Write-Host "Uninstallation cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Removing certificates..." -ForegroundColor Cyan

try {
    foreach ($cert in $certificates) {
        Remove-Item -Path "Cert:\LocalMachine\Root\$($cert.Thumbprint)" -Force
        Write-Host "  Removed: $($cert.Thumbprint)" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host "  Uninstallation Complete!" -ForegroundColor Green
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host ""
    
} catch {
    Write-Host "ERROR: Failed to remove certificate!" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
