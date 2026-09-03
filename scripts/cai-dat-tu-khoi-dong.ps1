# Đăng ký máy chủ cân xe chạy tự động cùng Windows.
#
# Cần chạy với quyền Administrator. Sau khi cài, máy ở kho chỉ việc bật điện là
# hệ thống lên — không ai phải mở cửa sổ lệnh.
#
# Tác vụ gọi THẲNG canxe-server.exe, không qua powershell.exe — bớt một lớp
# trung gian và không phải bật -ExecutionPolicy Bypass cho một tiến trình chạy
# dưới SYSTEM. Server tự ghi nhật ký qua tham số --log-file.
#
# LƯU Ý: tác vụ chạy dưới SYSTEM chỉ đọc được từ PowerShell có quyền
# Administrator. Chạy Get-ScheduledTask ở cửa sổ thường sẽ trả về rỗng dù tác vụ
# vẫn đang chạy — đừng vội tưởng là nó bị xoá.
#
#   .\cai-dat-tu-khoi-dong.ps1                 # cài cả trung tâm và trạm cân
#   .\cai-dat-tu-khoi-dong.ps1 -ChiTramCan     # máy ở kho: chỉ trạm cân
#   .\cai-dat-tu-khoi-dong.ps1 -ChiTrungTam    # máy văn phòng: chỉ trung tâm

param(
    [switch] $ChiTramCan,
    [switch] $ChiTrungTam
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Can quyen Administrator. Mo PowerShell bang 'Run as administrator' roi chay lai."
}

$root = Split-Path $PSScriptRoot -Parent
$serverDir = Join-Path $root 'packages\server'
$exe = Join-Path $serverDir 'build\canxe-server.exe'
$logDir = Join-Path $root 'logs'

if (-not (Test-Path $exe)) {
    throw "Chua co $exe. Chay scripts\build-web.ps1 truoc de bien dich."
}
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

$jobs = @()
if (-not $ChiTramCan)  { $jobs += @{ Name = 'CanXe-TrungTam'; Config = 'config.central.json'; Log = 'trung-tam.log'; Mo = 'May chu trung tam can xe' } }
if (-not $ChiTrungTam) { $jobs += @{ Name = 'CanXe-TramCan';  Config = 'config.station.json'; Log = 'tram-can.log';  Mo = 'Tram can xe (doc cong COM)' } }

foreach ($job in $jobs) {
    if (-not (Test-Path (Join-Path $serverDir $job.Config))) {
        Write-Warning "Bo qua $($job.Name): chua co $($job.Config)"
        continue
    }

    $action = New-ScheduledTaskAction -Execute $exe `
        -Argument "--config $($job.Config) --log-file `"$(Join-Path $logDir $job.Log)`"" `
        -WorkingDirectory $serverDir

    # Chạy dưới SYSTEM để dịch vụ lên ngay khi máy khởi động, không cần ai đăng nhập.
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    # Tự khởi động lại khi lỗi: rút cáp đầu cân hay mất điện chớp nhoáng không
    # được phép làm chết dịch vụ tới sáng hôm sau.
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $job.Name -Description $job.Mo `
        -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) `
        -Principal $principal -Settings $settings -Force | Out-Null

    Write-Output "da dang ky $($job.Name) -> $($job.Config)"
}

# Dừng tiến trình đang chạy tay để tác vụ tiếp quản, tránh hai bản cùng giữ cổng COM.
Get-Process canxe-server -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

foreach ($job in $jobs) {
    if (Get-ScheduledTask -TaskName $job.Name -ErrorAction SilentlyContinue) {
        Start-ScheduledTask -TaskName $job.Name
        Write-Output "da khoi dong $($job.Name)"
        Start-Sleep -Seconds 5
    }
}

Write-Output ''
Write-Output "Kiem tra: Get-ScheduledTask CanXe-* | Select TaskName,State"
Write-Output "Nhat ky: $logDir"
