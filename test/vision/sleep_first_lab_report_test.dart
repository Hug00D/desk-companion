import 'package:desk_companion/vision/sleep_first_lab_report.dart';
import 'package:desk_companion/vision/vision_lab_comparison.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scores sleep events without requiring a reading prediction', () {
    final report = buildSleepFirstLabReport(
      frames: [
        for (var i = 0; i < 6; i++)
          VisionLabFrame(
            frameIndex: i,
            timestampMs: i * 1000,
            rawState: 'unused',
          ),
      ],
      states: const [
        'other',
        'uncertain_low_head',
        'sleeping',
        'uncertain_low_head',
        'sleeping',
        'other',
      ],
      truth: const [
        VisionLabEvent(state: 'normal', startMs: 0, endMs: 1000),
        VisionLabEvent(state: 'sleeping', startMs: 1000, endMs: 5000),
        VisionLabEvent(state: 'reading', startMs: 5000, endMs: 6000),
      ],
      windowMs: 2000,
    );

    expect(report.metrics['tp_frames'], '2');
    expect(report.metrics['fn_frames'], '2');
    expect(report.metrics['fp_frames'], '0');
    expect(report.metrics['detected_sleep_events'], '1');
    expect(report.metrics['missed_sleep_events'], '0');
    expect(report.metrics['sleep_interruptions'], '1');
    expect(report.metrics['onset_delays_ms'], '1000');
    expect(report.metrics['uncertain_during_sleep_frames'], '2');
    expect(report.events.map((event) => event.state).toSet(), {
      'other',
      'uncertain_low_head',
      'sleeping',
    });
  });

  test('counts sleeping outside truth as a false sleep event', () {
    final report = buildSleepFirstLabReport(
      frames: const [
        VisionLabFrame(frameIndex: 0, timestampMs: 0, rawState: 'unused'),
        VisionLabFrame(frameIndex: 1, timestampMs: 1000, rawState: 'unused'),
      ],
      states: const ['sleeping', 'other'],
      truth: const [VisionLabEvent(state: 'normal', startMs: 0, endMs: 2000)],
      windowMs: 2000,
    );

    expect(report.metrics['false_sleep_events'], '1');
    expect(report.metrics['event_precision'], '0.000000');
    expect(report.metrics['event_recall'], '0.000000');
  });

  test('rejects behavior labels outside the sleep-first contract', () {
    expect(
      () => buildSleepFirstLabReport(
        frames: const [
          VisionLabFrame(frameIndex: 0, timestampMs: 0, rawState: 'unused'),
        ],
        states: const ['reading_like'],
        truth: const [VisionLabEvent(state: 'normal', startMs: 0, endMs: 1000)],
        windowMs: 2000,
      ),
      throwsFormatException,
    );
  });
}
