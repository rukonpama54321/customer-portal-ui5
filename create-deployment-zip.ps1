# Create deployment ZIP for SAP ERP Fiori Launchpad
# This script creates a ZIP file of the dist folder contents

$distPath = "E:\Customer Portal\dist"
$zipName = "ZCUSTINDENT_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
$zipPath = "E:\Customer Portal\$zipName"

Write-Host "Creating deployment package..." -ForegroundColor Green
Write-Host "Source: $distPath" -ForegroundColor Cyan
Write-Host "Output: $zipPath" -ForegroundColor Cyan

# Check if dist folder exists
if (-not (Test-Path $distPath)) {
    Write-Host "ERROR: dist folder not found. Run 'npm run build' first!" -ForegroundColor Red
    exit 1
}

# Remove old zip if exists
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

# Create ZIP file (compress contents, not the folder itself)
Compress-Archive -Path "$distPath\*" -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host "`nDeployment package created successfully!" -ForegroundColor Green
Write-Host "ZIP file: $zipPath" -ForegroundColor Yellow
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Login to SAP ERP: https://eccdev.nrl.com:8001" -ForegroundColor White
Write-Host "2. Go to transaction: /UI2/FLPD_CUST" -ForegroundColor White
Write-Host "3. Transport -> Import -> Upload the ZIP file" -ForegroundColor White
Write-Host "4. BSP Application Name: ZCUSTINDENT" -ForegroundColor White
Write-Host "5. Package: ZCUST_PORTAL" -ForegroundColor White
Write-Host "`nSee DEPLOYMENT_GUIDE.md for detailed instructions" -ForegroundColor Cyan
