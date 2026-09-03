# Chạy toàn bộ kiểm thử và phân tích mã của cả ba package.

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Get-ProjectRoot
$dart = Get-SdkTool -Name dart
$flutter = Get-SdkTool -Name flutter
$failed = @()

function Invoke-Step {
    param([string] $Title, [string] $Directory, [string] $Tool, [string[]] $Arguments)

    Write-Host "==> $Title" -ForegroundColor Cyan
    Push-Location $Directory
    try {
        & $Tool @Arguments
        if ($LASTEXITCODE -ne 0) { $script:failed += $Title }
    }
    finally {
        Pop-Location
    }
}

Invoke-Step 'Phân tích canxe_shared' (Join-Path $root 'packages\shared') $dart @('analyze')
Invoke-Step 'Kiểm thử canxe_shared'  (Join-Path $root 'packages\shared') $dart @('test')
Invoke-Step 'Phân tích canxe_server' (Join-Path $root 'packages\server') $dart @('analyze')
Invoke-Step 'Kiểm thử canxe_server'  (Join-Path $root 'packages\server') $dart @('test')
Invoke-Step 'Phân tích canxe_app'    (Join-Path $root 'packages\app')    $flutter @('analyze')
Invoke-Step 'Kiểm thử canxe_app'     (Join-Path $root 'packages\app')    $flutter @('test')

Write-Host ''
if ($failed.Count -eq 0) {
    Write-Host 'Tất cả bước đều đạt.' -ForegroundColor Green
}
else {
    Write-Host "Các bước chưa đạt: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
