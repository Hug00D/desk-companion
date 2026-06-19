param(
    [string]$OutputPath,
    [string]$TextPath,
    [string]$VoiceName,
    [string]$VoiceCulture
)
Add-Type -AssemblyName System.Speech
$text = Get-Content -LiteralPath $TextPath -Raw -Encoding UTF8
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
if (-not [string]::IsNullOrWhiteSpace($VoiceName)) {
    try {
        $synth.SelectVoice($VoiceName)
    } catch {
        # Fall back to culture / automatic selection below.
    }
}

if ($synth.Voice.Name -ne $VoiceName) {
    if (-not [string]::IsNullOrWhiteSpace($VoiceCulture)) {
        $voice = $synth.GetInstalledVoices() |
            Where-Object { $_.VoiceInfo.Culture.Name -eq $VoiceCulture } |
            Select-Object -First 1
        if ($voice -ne $null) {
            $synth.SelectVoice($voice.VoiceInfo.Name)
        }
    } elseif ($text -match '[\u3400-\u9FFF]') {
        $voice = $synth.GetInstalledVoices() |
            Where-Object { $_.VoiceInfo.Culture.Name -eq 'zh-TW' } |
            Select-Object -First 1
        if ($voice -ne $null) {
            $synth.SelectVoice($voice.VoiceInfo.Name)
        }
    }
}

if ($synth.Voice.Name -ne $VoiceName -and $text -match '[\u3400-\u9FFF]') {
    $voice = $synth.GetInstalledVoices() |
        Where-Object { $_.VoiceInfo.Culture.Name -eq 'zh-TW' } |
        Select-Object -First 1
    if ($voice -ne $null) {
        $synth.SelectVoice($voice.VoiceInfo.Name)
    }
}
$synth.Rate = 0
$synth.Volume = 100
$synth.SetOutputToWaveFile($OutputPath)
$synth.Speak($text)
$synth.Dispose()