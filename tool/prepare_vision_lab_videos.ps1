param(
    [string]$FfmpegPath,
    [string[]]$VideoNames = @('dev_dual_track_01.mp4', 'dev_dual_track_02.mp4')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $FfmpegPath) {
    $FfmpegPath = Get-ChildItem -LiteralPath "$projectRoot\vision_lab_out\tools\ffmpeg" `
        -Recurse -File -Filter ffmpeg.exe | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $FfmpegPath -or -not (Test-Path -LiteralPath $FfmpegPath)) {
    throw 'Supply -FfmpegPath with a portable FFmpeg executable.'
}
$probePath = Join-Path (Split-Path -Parent $FfmpegPath) 'ffprobe.exe'
if (-not (Test-Path -LiteralPath $probePath)) { throw 'ffprobe.exe is required.' }
$sourceDirectory = Join-Path $projectRoot 'assets\testVideos'
$outputDirectory = Join-Path $sourceDirectory 'playback'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

function Read-VideoMetadata([string]$Path) {
    $json = & $probePath -v error -select_streams v:0 `
        -show_entries stream=codec_name,width,height,pix_fmt,color_transfer,time_base,nb_frames,duration `
        -of json $Path
    if ($LASTEXITCODE -ne 0) { throw "Cannot probe $Path" }
    return ($json -join "`n" | ConvertFrom-Json).streams[0]
}

function Read-PresentationTimes([string]$Path) {
    $json = & $probePath -v error -select_streams v:0 -show_packets `
        -show_entries packet=pts_time -of json $Path
    if ($LASTEXITCODE -ne 0) { throw "Cannot read timestamps from $Path" }
    return (($json -join "`n" | ConvertFrom-Json).packets.pts_time | Sort-Object { [decimal]$_ })
}

foreach ($name in $VideoNames) {
    if ([IO.Path]::GetFileName($name) -ne $name -or [IO.Path]::GetExtension($name) -ine '.mp4') {
        throw 'VideoNames must be MP4 filenames without directories.'
    }
    $inputPath = Join-Path $sourceDirectory $name
    $outputPath = Join-Path $outputDirectory $name
    $stagingPath = Join-Path $outputDirectory "$name.partial.mp4"
    $manifestPath = Join-Path $outputDirectory "$name.conversion.json"
    if ((Test-Path -LiteralPath $outputPath) -or (Test-Path -LiteralPath $stagingPath) -or
        (Test-Path -LiteralPath $manifestPath)) {
        throw "Refusing to overwrite existing conversion: $name"
    }
    $source = Read-VideoMetadata $inputPath
    $filter = 'scale=1920:1080:force_original_aspect_ratio=decrease:force_divisible_by=2'
    if ($source.color_transfer -in @('arib-std-b67', 'smpte2084')) {
        $filter += ',zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709'
        $filter += ',tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv'
    }
    $filter += ',format=yuv420p'
    $encodeArguments = @(
        '-hide_banner', '-nostdin', '-n', '-loglevel', 'warning', '-stats_period', '15',
        '-progress', 'pipe:1', '-copyts', '-i', $inputPath,
        '-map', '0:v:0', '-map', '0:a?', '-vf', $filter,
        '-c:v', 'libx264', '-preset', 'fast', '-crf', '20', '-profile:v', 'high', '-level:v', '4.1',
        '-pix_fmt', 'yuv420p', '-fps_mode:v', 'passthrough', '-enc_time_base:v', 'demux',
        '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
        '-c:a', 'aac', '-b:a', '128k', '-map_metadata', '-1', '-movflags', '+faststart', $stagingPath
    )
    Write-Output "Converting $name"
    & $FfmpegPath @encodeArguments
    if ($LASTEXITCODE -ne 0) { throw "Conversion failed; incomplete copy is $stagingPath" }
    $converted = Read-VideoMetadata $stagingPath
    $sourceTimes = @(Read-PresentationTimes $inputPath)
    $convertedTimes = @(Read-PresentationTimes $stagingPath)
    if ($sourceTimes.Count -ne $convertedTimes.Count -or $source.nb_frames -ne $converted.nb_frames) {
        throw 'Converted video frame count differs from the original.'
    }
    for ($index = 0; $index -lt $sourceTimes.Count; $index++) {
        if ($sourceTimes[$index] -ne $convertedTimes[$index]) {
            throw "Presentation timestamp differs at frame $index."
        }
    }
    Move-Item -LiteralPath $stagingPath -Destination $outputPath
    [ordered]@{
        source = $inputPath
        source_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $inputPath).Hash
        output = $outputPath
        output_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash
        source_video = $source
        output_video = $converted
        presentation_timestamps_equal = $true
        verified_video_frames = $sourceTimes.Count
        ffmpeg_arguments = $encodeArguments
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Write-Output "Verified $name : $($sourceTimes.Count) frames, original PTS retained."
}
