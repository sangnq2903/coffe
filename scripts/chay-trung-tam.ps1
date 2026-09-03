# Chạy MÁY CHỦ TRUNG TÂM (máy 100.76.81.118).
#
# Đây là nơi gom dữ liệu của mọi kho. Máy này phải bật trước và bật liên tục.

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Get-ProjectRoot
$dart = Get-SdkTool -Name dart
$serverDir = Join-Path $root 'packages\server'
$config = Join-Path $serverDir 'config.central.json'

Assert-ConfigExists -ConfigPath $config -ExampleName 'config.central.example.json'

Push-Location $serverDir
try {
    & $dart run bin/server.dart --config $config
}
finally {
    Pop-Location
}
