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
