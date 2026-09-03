# Chạy MÁY TRẠM CÂN (máy nối cổng COM với đầu cân).
#
#   .\chay-tram-can.ps1              # dùng config.station.json
#   .\chay-tram-can.ps1 -GiaLap      # chạy thử với đầu cân giả lập
#   .\chay-tram-can.ps1 -Config config.kho02.json

param(
    [string] $Config = 'config.station.json',
    [switch] $GiaLap
)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Get-ProjectRoot
$dart = Get-SdkTool -Name dart
$serverDir = Join-Path $root 'packages\server'
$configPath = if ([System.IO.Path]::IsPathRooted($Config)) { $Config } else { Join-Path $serverDir $Config }

Assert-ConfigExists -ConfigPath $configPath -ExampleName 'config.station.example.json'

$arguments = @('run', 'bin/server.dart', '--config', $configPath)
if ($GiaLap) { $arguments += '--simulate' }

Push-Location $serverDir
try {
    & $dart @arguments
}
finally {
    Pop-Location
}
