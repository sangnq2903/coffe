# Hàm dùng chung cho các script: tìm Flutter/Dart SDK và xác định thư mục dự án.

$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

# Tìm dart.bat / flutter.bat theo thứ tự: PATH, rồi các vị trí cài đặt thường gặp.
function Get-SdkTool {
    param([ValidateSet('dart', 'flutter')] [string] $Name)

    $fromPath = Get-Command "$Name" -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }

    $candidates = @(
        "C:\src\flutter\bin\$Name.bat",
        "D:\src\flutter\bin\$Name.bat",
        "C:\flutter\bin\$Name.bat",
        "$env:LOCALAPPDATA\flutter\bin\$Name.bat"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    throw "Không tìm thấy $Name. Hãy cài Flutter SDK và thêm thư mục bin vào PATH."
}

function Assert-ConfigExists {
    param([string] $ConfigPath, [string] $ExampleName)

    if (Test-Path $ConfigPath) { return }

    $example = Join-Path (Split-Path $ConfigPath -Parent) $ExampleName
    throw @"
Chưa có file cấu hình: $ConfigPath

Hãy chép file mẫu rồi sửa lại cho đúng máy này:
    Copy-Item "$example" "$ConfigPath"
"@
}
