# Desk Companion Voice Service

Local reminder voice service used by the Flutter app. The public API remains
`POST /tts`; the service now prefers the licensed Staff A GPT-SoVITS
v2ProPlus model and falls back to Windows System.Speech when GPT-SoVITS is not
available.

## Local-only files

The following directories are intentionally ignored by Git because they hold
large runtime files, generated audio, or a model that cannot be redistributed:

```text
models/
runtime/
output/
```

Expected Staff A model layout:

```text
models/staff_a/Staff_A_GPT-SoVITS_v2ProPlus/
  Staff_A+hlw-e15.ckpt
  Staff_A+hlw_e8_s392.pth
  rec257_normal.opus
  emo039_low01.opus
  emo052_whisper.opus
  emo069_high.opus
```

The model license permits commercial and non-commercial use without credit,
but prohibits redistribution of the model files.

## Run

From the project root:

```powershell
.\backend\python_voice_service\start.ps1
```

Useful options:

```powershell
.\backend\python_voice_service\start.ps1 -SkipPrewarm
.\backend\python_voice_service\start.ps1 -DisableGptSoVits
```

The first normal launch starts GPT-SoVITS on `127.0.0.1:9880`, starts the app
voice API on port `8001`, and pre-generates three fixed reminders for each
supported vision status. Later launches reuse cached WAV files.

Android emulator URL:

```text
http://10.0.2.2:8001
```

Physical phone example:

```powershell
flutter run --dart-define=VOICE_SERVICE_URL=http://192.168.1.23:8001
```

## API

```text
GET  /health
GET  /voices
POST /tts
GET  /audio/<filename>
```

Example:

```powershell
$body = @{
  text = "Focus reminder"
  source = "vision"
  status = "distracted"
  eventType = "vision.distracted"
} | ConvertTo-Json

Invoke-RestMethod -Method Post `
  -Uri http://127.0.0.1:8001/tts `
  -ContentType "application/json" `
  -Body $body
```

For `source=vision`, the service chooses one of three fixed messages for the
status and avoids repeating the immediately previous message. Dynamic LLM
responses keep the supplied `text` unchanged.
