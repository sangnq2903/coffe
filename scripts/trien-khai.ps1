# Thay máy chủ đang chạy bằng bản mới. Cần quyền Administrator.
#
# Hai task CanXe-TrungTam / CanXe-TramCan chạy dưới quyền SYSTEM nên file
# canxe-server.exe luôn bị khoá — biên dịch đè lên sẽ thất bại với errno 32.
# Script này dừng task, biên dịch, rồi chạy lại; phần cân xe bị ngắt vài giây.
#
# Không build giao diện web ở đây: chạy scripts\build-web.ps1 (không cần admin)
# trước, hoặc để nguyên nếu chỉ sửa phía máy chủ.

param(
    # Ghi nhật ký ra file để chạy từ cửa sổ UAC vẫn đọc lại được kết quả.
    [string] $LogFile
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if ($LogFile) { Start-Transcript -Path $LogFile -Force | Out-Null }

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Cần quyền Administrator. Mở PowerShell bằng 'Run as administrator' rồi chạy lại."
    }

    $tasks = @('CanXe-TrungTam', 'CanXe-TramCan') | Where-Object {
        Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue
    }

    Write-Host "==> Dung may chu..." -ForegroundColor Cyan
    foreach ($name in $tasks) {
        Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        Write-Host "  da dung $name"
    }
    Get-Process canxe-server -ErrorAction SilentlyContinue | Stop-Process -Force
    # Tien trinh tat khong phai tuc thi; cho toi khi file het bi khoa.
    $exe = Join-Path (Get-ProjectRoot) 'packages\server\build\canxe-server.exe'
    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Get-Process canxe-server -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 500
    }

    Write-Host "==> Bien dich may chu..." -ForegroundColor Cyan
    $dart = Get-SdkTool -Name dart
    Push-Location (Join-Path (Get-ProjectRoot) 'packages\server')
    try {
        New-Item -ItemType Directory -Force -Path 'build' | Out-Null
        & $dart compile exe bin/server.dart -o build/canxe-server.exe
        if ($LASTEXITCODE -ne 0) { throw "Bien dich that bai (ma loi $LASTEXITCODE)." }
    }
    finally {
        Pop-Location
    }
    Write-Host "  $exe  $((Get-Item $exe).LastWriteTime)"
}
finally {
    # Du bien dich hong cung phai bat lai may chu, khong thi kho dung can.
    Write-Host "==> Chay lai may chu..." -ForegroundColor Cyan
    foreach ($name in @('CanXe-TrungTam', 'CanXe-TramCan')) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Start-ScheduledTask -TaskName $name
            Write-Host "  da chay $name"
        }
    }
    if ($LogFile) { Stop-Transcript | Out-Null }
}
Write-Host 'Xong.' -ForegroundColor Green
