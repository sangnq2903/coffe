# Gỡ đăng ký tự khởi động của máy chủ cân xe. Cần quyền Administrator.

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Cần quyền Administrator. Mở PowerShell bằng 'Run as administrator' rồi chạy lại."
}

foreach ($name in 'CanXe-TrungTam', 'CanXe-TramCan') {
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
        Write-Host "  da go $name" -ForegroundColor Yellow
    }
}
Get-Process canxe-server -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host 'Xong.' -ForegroundColor Cyan
