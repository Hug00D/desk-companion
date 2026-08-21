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

## DGX Spark / Docker

The teacher server uses an ARM64 NVIDIA DGX Spark. Its supported deployment
uses `nvcr.io/nvidia/pytorch:25.09-py3`, which was verified with CUDA 13.0 and
the NVIDIA GB10 GPU. The container is separate from the existing SGLang and
Spring Boot containers. The ARM64 NGC image does not bundle TorchAudio, so the
Docker build compiles TorchAudio `v2.9.0` against NVIDIA's installed Torch;
never add a normal `pip install torchaudio` that could replace the CUDA build.

Required host-only assets must exist before the first build:

```text
runtime/GPT-SoVITS/                         # commit bf81cdb14a38b674b6e9996dabc97340bc9978d2
runtime/GPT-SoVITS/GPT_SoVITS/pretrained_models/chinese-hubert-base/
runtime/GPT-SoVITS/GPT_SoVITS/pretrained_models/chinese-roberta-wwm-ext-large/
runtime/GPT-SoVITS/GPT_SoVITS/pretrained_models/fast_langdetect/
runtime/GPT-SoVITS/GPT_SoVITS/pretrained_models/sv/
runtime/GPT-SoVITS/GPT_SoVITS/text/G2PWModel/
runtime/open_jtalk_dic_utf_8-1.11/
models/staff_a/Staff_A_GPT-SoVITS_v2ProPlus/
```

Build and start from the voice service directory:

```bash
cd ~/desk-companion/backend/python_voice_service
free -h
nvidia-smi
docker compose -f compose.server.yaml build
docker compose -f compose.server.yaml up -d
docker compose -f compose.server.yaml logs -f
```

The published port is bound only to the server Tailscale address
`100.119.136.82`. Clients that receive the shared-node address use
`http://100.119.136.81:8001`.

Verify from the server:

```bash
curl http://100.119.136.82:8001/health
docker inspect --format '{{.State.Health.Status}}' desk-companion-voice
```

Normal Python/config updates do not rebuild the image because those files are
bind-mounted:

```bash
cd ~/desk-companion
git pull --ff-only
cd backend/python_voice_service
docker compose -f compose.server.yaml restart
```

Rebuild only after changing `requirements*.txt` or `Dockerfile.server`:

```bash
docker compose -f compose.server.yaml up -d --build
```

### Daily server operations

Run these commands from the voice service directory. Closing SSH does not stop
the container; it remains available until explicitly stopped.

```bash
cd ~/desk-companion/backend/python_voice_service
```

Start an existing container without rebuilding the image or reloading model
files from disk unnecessarily:

```bash
docker compose -f compose.server.yaml start
```

Stop only the Desk Companion voice service without touching the senior's
SGLang, Spring Boot, or other containers:

```bash
docker compose -f compose.server.yaml stop
```

Restart after pulling normal Python or configuration changes:

```bash
docker compose -f compose.server.yaml restart
```

Check status, recent logs, and available unified memory:

```bash
docker compose -f compose.server.yaml ps
docker compose -f compose.server.yaml logs --since=5m --tail=100
free -h
```

Use `up -d` instead of `start` only when the container has not been created yet
or the Compose definition changed:

```bash
docker compose -f compose.server.yaml up -d
```

Use `down` only when the container and its Compose network should be removed.
The bind-mounted models and runtime remain on the host, but normal temporary
shutdowns should use `stop`.

Models and runtime files are host bind mounts and survive container rebuilds
or removal. Before loading the model, check `free -h`; stop this voice service
if available unified memory approaches 10 GiB, swap rises quickly, or the
existing SGLang API slows down.

`gpt_sovits_config.yaml` is mounted as a read-only template. The container
copies it to `/tmp/gpt_sovits_config.runtime.yaml` on every start because
GPT-SoVITS writes normalized values back to its active config during model
initialization. This keeps the tracked host config clean.

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
