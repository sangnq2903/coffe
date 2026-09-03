# Build giao diện Flutter web và đặt vào thư mục mà server sẽ phục vụ.
#
# Chạy lại script này mỗi khi sửa code trong packages/app.

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Get-ProjectRoot
$flutter = Get-SdkTool -Name flutter
$appDir = Join-Path $root 'packages\app'
$webOut = Join-Path $root 'packages\server\web'

Write-Host "==> Build Flutter web..." -ForegroundColor Cyan
Push-Location $appDir
try {
    & $flutter build web --release
    if ($LASTEXITCODE -ne 0) { throw "Build web thất bại (mã lỗi $LASTEXITCODE)." }
}
finally {
    Pop-Location
}

Write-Host "==> Chép bản build sang server..." -ForegroundColor Cyan
if (Test-Path $webOut) { Remove-Item $webOut -Recurse -Force }
Copy-Item (Join-Path $appDir 'build\web') $webOut -Recurse

$count = (Get-ChildItem $webOut -Recurse -File).Count
Write-Host "Xong. $count file đã sẵn sàng tại $webOut" -ForegroundColor Green

Write-Host "==> Bien dich may chu thanh file exe..." -ForegroundColor Cyan
$dart = Get-SdkTool -Name dart
$serverDir = Join-Path $root 'packages\server'
Push-Location $serverDir
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $serverDir 'build') | Out-Null
    & $dart compile exe bin/server.dart -o build/canxe-server.exe
    if ($LASTEXITCODE -ne 0) { throw "Bien dich may chu that bai (ma loi $LASTEXITCODE)." }
}
finally {
    Pop-Location
}
Write-Host "Xong. May chu: $(Join-Path $serverDir 'build\canxe-server.exe')" -ForegroundColor Green
