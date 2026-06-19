# Desk Companion Python Voice Service

Local voice service for testing the reminder-to-voice pipeline.

This first version does not run GPT-SoVITS yet. It receives reminder text,
prints it in the terminal, and writes a WAV file to
`backend/python_voice_service/output/`. On Windows it tries the local
System.Speech TTS voice first, then falls back to a small mock WAV.

Repeated reminder text is cached as `cached_voice_*.wav`, so the same sentence
is generated once and reused on later calls. The service keeps the newest 120
cached voice files.

## Run

From the project root:

```powershell
& "C:\Users\User\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" backend\python_voice_service\app\main.py --host 0.0.0.0 --port 8001
```

If you install Python locally later, this also works:

```powershell
python backend\python_voice_service\app\main.py --host 0.0.0.0 --port 8001
```

## Test

```powershell
Invoke-RestMethod -Method Post `
  -Uri http://127.0.0.1:8001/tts `
  -ContentType "application/json" `
  -Body '{"text":"先回來專注一下。","source":"manual-test","status":"distracted"}'
```

Android emulator should call the host machine through:

```text
http://10.0.2.2:8001
```

Physical phone should use your PC LAN IP instead, for example:

```powershell
flutter run --dart-define=VOICE_SERVICE_URL=http://192.168.1.23:8001
```

## GPT-SoVITS Later

Replace `_generate_speech_wav(...)` in `app/main.py` with the GPT-SoVITS
inference call. The HTTP contract can stay the same:

```text
POST /tts
{ "text": "...", "source": "vision", "status": "drowsy" }
```
