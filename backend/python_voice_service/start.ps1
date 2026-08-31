param(
    [string]$HostAddress = "0.0.0.0",
    [int]$Port = 8001,
    [switch]$DisableGptSoVits
)

$ErrorActionPreference = "Stop"
$serviceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = Join-Path $serviceRoot "runtime\miniconda\python.exe"

try {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2
    if ($health.ok -and $health.service -eq "desk_companion_voice_service") {
        Write-Host "[voice-service] already running on port $Port (PID $($health.processId))"
        exit 0
    }
} catch {
    # No healthy service is listening; continue with startup.
}

if (-not (Test-Path -LiteralPath $python)) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $pythonCommand) {
        throw "Python runtime not found. Set up backend/python_voice_service/runtime/miniconda first."
    }
    $python = $pythonCommand.Source
}

$arguments = @(
    (Join-Path $serviceRoot "app\main.py"),
    "--host",
    $HostAddress,
    "--port",
    $Port
)
if ($DisableGptSoVits) {
    $arguments += "--disable-gpt-sovits"
}

$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
& $python @arguments
