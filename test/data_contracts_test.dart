import 'package:desk_companion/events/companion_event.dart';
import 'package:desk_companion/events/companion_event_buffer.dart';
import 'package:desk_companion/focus/study_session.dart';
import 'package:desk_companion/statistics/statistics_summary.dart';
import 'package:desk_companion/voice/voice_event_payload.dart';
import 'package:desk_companion/voice/voice_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('companion event serializes the backend contract', () {
    final event = CompanionEvent(
      clientEventId: 'event-1',
      sessionId: 'session-1',
      source: CompanionEventSource.vision,
      eventType: 'vision.fatigue_detected',
      occurredAt: DateTime.utc(2026, 6, 19, 10),
      severity: CompanionEventSeverity.warning,
      confidenceScore: 0.9,
      actionTriggered: 'start_break',
      signals: const <String, dynamic>{'leftEye': 0.1},
    );

    final json = event.toJson();
    expect(json['clientEventId'], 'event-1');
    expect(json['source'], 'vision');
    expect(json['eventType'], 'vision.fatigue_detected');
    expect(json['ts'], '2026-06-19T10:00:00.000Z');
    expect(json['severity'], 'warning');
    expect(json['signals'], <String, dynamic>{'leftEye': 0.1});
  });

  test('event buffer removes only acknowledged events', () {
    final buffer = CompanionEventBuffer();
    buffer.addAll(<CompanionEvent>[
      CompanionEvent.create(
        clientEventId: 'event-1',
        sessionId: 'session-1',
        source: CompanionEventSource.timer,
        eventType: 'pomodoro.started',
      ),
      CompanionEvent.create(
        clientEventId: 'event-2',
        sessionId: 'session-1',
        source: CompanionEventSource.timer,
        eventType: 'pomodoro.completed',
      ),
    ]);

    buffer.markUploaded(const <String>['event-1']);
    expect(buffer.pending.single.clientEventId, 'event-2');
  });

  test('study session update payload contains report durations', () {
    final snapshot = StudySessionSnapshot(
      clientSessionId: 'session-1',
      startedAt: DateTime.utc(2026, 6, 19, 9),
      status: StudySessionStatus.completed,
      timezone: 'Asia/Taipei',
      focusSeconds: 1200,
      attentionSeconds: 120,
      fatigueSeconds: 60,
      awaySeconds: 30,
      reminderShownCount: 2,
    );

    final json = snapshot.toUpdatePayload();
    expect(json['focusSeconds'], 1200);
    expect(json['attentionSeconds'], 120);
    expect(json['fatigueSeconds'], 60);
    expect(json['awaySeconds'], 30);
    expect(json['reminderCount'], 2);
  });

  test('voice event excludes transcript unless explicitly allowed', () {
    const recognition = VoiceRecognitionResult(
      sessionId: 'voice-1',
      eventType: VoiceEventType.finalResult,
      timestampMs: 1710000001000,
      transcript: '幫我開始番茄鐘',
      formattedTranscript: '幫我開始番茄鐘。',
      isFinal: true,
      candidates: <VoiceCandidate>[
        VoiceCandidate(text: '幫我開始番茄鐘', confidence: 0.91),
      ],
      recognitionParts: <VoiceRecognitionPart>[
        VoiceRecognitionPart(
          text: '幫我開始番茄鐘',
          formattedText: '幫我開始番茄鐘。',
          timestampMs: 120,
          confidence: 0.9,
        ),
      ],
      alternatives: <VoiceAlternativeSpan>[
        VoiceAlternativeSpan(
          startIndex: 0,
          endIndex: 8,
          texts: <String>['幫我啟動番茄鐘'],
        ),
      ],
    );

    final event = VoiceEventPayload.fromRecognition(
      studySessionId: 'session-1',
      recognition: recognition,
    );
    final recognitionJson =
        event.signals['recognition'] as Map<String, dynamic>;

    expect(recognitionJson.containsKey('transcript'), isFalse);
    expect(recognitionJson['candidates'], <Map<String, dynamic>>[
      <String, dynamic>{'confidence': 0.91},
    ]);
    expect(recognitionJson['recognitionParts'], <Map<String, dynamic>>[
      <String, dynamic>{'timestampMs': 120, 'confidence': 0.9},
    ]);
    expect(recognitionJson['alternatives'], <Map<String, dynamic>>[
      <String, dynamic>{'startIndex': 0, 'endIndex': 8},
    ]);
  });

  test('statistics response computes state ratios', () {
    final summary = StatisticsSummary.fromJson(<String, dynamic>{
      'today': <String, dynamic>{'focusSeconds': 600},
      'weeklyTrend': <Map<String, dynamic>>[],
      'stateDistribution': <String, dynamic>{
        'focusSeconds': 600,
        'attentionSeconds': 200,
        'fatigueSeconds': 100,
        'awaySeconds': 100,
      },
      'recentEvents': <Map<String, dynamic>>[],
    });

    expect(summary.stateDistribution.totalSeconds, 1000);
    expect(summary.stateDistribution.ratioFor(600), 0.6);
  });
}
