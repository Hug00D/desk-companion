param(
    [string]$DeviceId = "emulator-5554",
    [int]$PollSeconds = 2,
    [switch]$Once
)

$visionProjectRoot = Split-Path -Parent $PSScriptRoot
$visionOutputDirectory = Join-Path $visionProjectRoot "vision_lab_out"
$visionDeviceDirectory = "/sdcard/Android/data/com.example.desk_companion/files"
$visionAdbCommand = Get-Command adb -ErrorAction SilentlyContinue

if ($null -ne $visionAdbCommand) {
    $visionAdbPath = $visionAdbCommand.Source
} else {
    $visionSdkAdbPath = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
    if (-not (Test-Path -LiteralPath $visionSdkAdbPath)) {
        throw "adb not found. Install Android platform-tools or add adb to PATH."
    }
    $visionAdbPath = $visionSdkAdbPath
}

New-Item -ItemType Directory -Path $visionOutputDirectory -Force | Out-Null

function Sync-VisionLabCsv {
    $visionDeviceFiles = @(
        & $visionAdbPath -s $DeviceId shell ls -1 $visionDeviceDirectory 2>$null |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^frame_features_[0-9]+\.csv$' }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot read Vision Lab output from Android device '$DeviceId'."
    }

    foreach ($visionFileName in $visionDeviceFiles) {
        $visionHostPath = Join-Path $visionOutputDirectory $visionFileName
        if (Test-Path -LiteralPath $visionHostPath) {
            continue
        }

        $visionDevicePath = "$visionDeviceDirectory/$visionFileName"
        & $visionAdbPath -s $DeviceId pull $visionDevicePath $visionHostPath
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to pull '$visionFileName' from Android device."
        }
        Write-Host "Vision Lab CSV saved: $visionHostPath"
    }
}

if ($Once) {
    Write-Host "Syncing Vision Lab CSV files from $DeviceId."
} else {
    Write-Host "Watching $DeviceId for Vision Lab CSV files. Press Ctrl+C to stop."
}
do {
    Sync-VisionLabCsv
    if ($Once) {
        break
    }
    Start-Sleep -Seconds ([Math]::Max(1, $PollSeconds))
} while ($true)
