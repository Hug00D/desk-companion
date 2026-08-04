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
.\backend\python_voice_service\start.ps1 -DisableGptSoVits
```

The normal launch starts GPT-SoVITS on `127.0.0.1:9880` and starts the app
voice API on port `8001`. Fixed reminder clips are bundled with the Flutter
app, so this service only generates one-shot audio for dynamic text. Each WAV
is deleted 30 seconds after `GET /audio/<filename>` finishes so the app can
retry a dropped download. Files left by interrupted downloads are removed after
ten minutes or at the next service startup.

Android emulator URL:

```text
http://10.0.2.2:8001
```

Physical phone example:

```powershell
flutter run --dart-define=VOICE_SERVICE_URL=http://192.168.1.23:8001
```

Dynamic AI replies are opt-in in Flutter. Enable them only when this service
is reachable:

```powershell
flutter run `
  --dart-define=API_BASE_URL=http://100.119.136.81:8080/api/v1 `
  --dart-define=VOICE_SERVICE_URL=http://100.119.136.81:8001 `
  --dart-define=DYNAMIC_ASSISTANT_VOICE_ENABLED=true
```

## Linux / systemd

The service can use a bundled Linux Conda runtime or paths supplied through
environment variables. The model and runtime directories remain local-only
and must be copied to the server separately.

1. Copy `desk-companion-voice.env.example` to
   `/etc/desk-companion/voice.env` and update its user, paths, and Tailscale
   address.
2. Verify the service interactively with `bash start.sh`.
3. Copy `desk-companion-voice.service.example` to
   `/etc/systemd/system/desk-companion-voice.service` and update the Linux
   user and project directory if necessary.
4. Start it with:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now desk-companion-voice
sudo systemctl status desk-companion-voice
journalctl -u desk-companion-voice -f
```

Port `9880` stays bound to localhost for GPT-SoVITS. Port `8001` should bind
to the teacher server's Tailscale address and does not need to be exposed to
the public internet.

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
