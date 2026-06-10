# desk_buddy

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
# desk-companion
iecs_final_project

## Voice recognition result format

The `voice-test` branch includes the Android/Kotlin JSON output layer for
future speech recognition work. After a speech recognizer produces a transcript,
call the Flutter wrapper in `lib/voice/voice_channel.dart`:

```dart
final json = await VoiceChannel.formatVoiceResult(
  transcript: '我感覺我好容易分心，你能幫我設置番茄鐘嗎',
  formattedTranscript: '我感覺我好容易分心，你能幫我設置番茄鐘嗎？',
  caseId: 'demo_start_pomodoro',
  sessionId: 'demo-voice-session-001',
  confidence: 0.91,
);
```

Kotlin formats the result through
`android/app/src/main/kotlin/com/example/desk_companion/VoiceResultJsonFormatter.kt`.
The JSON shape matches `demo_voice_result.json`.

This formatter does not transcribe MP3 files by itself. Android's built-in
speech recognizer is designed for live microphone input, so arbitrary MP3 file
transcription still needs a separate recognition engine later, such as an
offline model, a cloud recognizer, or a custom model integration.

### Local Whisper MP3 test

For closed MP3 transcription tests, use the local Whisper helper:

```powershell
python -m pip install -r tools\voice\requirements.txt
python tools\voice\transcribe_with_whisper.py --model base --language zh
```

The helper uses `faster-whisper` and writes the same JSON result shape. The
first run downloads the selected Whisper model into the local model cache; after
that, the cached model can run without a transcription API.

The default input folder is `tools/voice/input/`. Put one or more `.mp3` files
there, then run the command above. The default output folder is `output/voice/`;
for example, `tools/voice/input/test-voice.mp3` writes
`output/voice/test-voice_result.json`.

You can also transcribe a single MP3 by passing a file path. This command writes
`output/test_voice_result.json`:

```powershell
python tools\voice\transcribe_with_whisper.py C:\Users\陳景琳\Downloads\test-voice.mp3 `
  -o output\test_voice_result.json `
  --model base `
  --language zh `
  --case-id test_voice
```

The `output/` folder and audio files under `tools/voice/input/` are ignored by
Git because they contain generated test results and local test audio. Keep using
`base` for the current test flow; smaller models are faster but less accurate,
and larger models are slower but usually more stable.
