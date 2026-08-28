import 'package:desk_companion/vision/vision_lab_comparison.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('3-of-5 removes a one-frame blink without reading future frames', () {
    final frames = _frames(<String>[
      'normal',
      'eye_closed',
      'normal',
      'normal',
      'normal',
      'normal',
    ]);

    expect(applyThreeOfFive(frames), <String>[
      'normal',
      'normal',
      'normal',
      'normal',
      'normal',
      'normal',
    ]);
  });

  test('3-of-5 asserts a sustained state on its third vote', () {
    final frames = _frames(<String>[
      'normal',
      'normal',
      'head_turned',
      'head_turned',
      'head_turned',
      'head_turned',
    ]);

    expect(applyThreeOfFive(frames), <String>[
      'normal',
      'normal',
      'normal',
      'normal',
      'head_turned',
      'head_turned',
    ]);
  });

  test('event collapse uses PTS boundaries', () {
    final frames = _frames(<String>[
      'normal',
      'normal',
      'head_turned',
      'head_turned',
      'normal',
    ]);

    final events = collapseVisionLabEvents(
      frames: frames,
      states: applySingleFrame(frames),
      videoEndMs: 166,
    );

    expect(events, hasLength(3));
    expect(events[0].state, 'normal');
    expect(events[0].startMs, 0);
    expect(events[0].endMs, 66);
    expect(events[1].state, 'head_turned');
    expect(events[1].startMs, 66);
    expect(events[1].endMs, 132);
  });

  test('event comparison reports first detection delay', () {
    final frames = _frames(<String>[
      'normal',
      'normal',
      'head_turned',
      'head_turned',
      'normal',
    ]);
    final states = applySingleFrame(frames);
    final predicted = collapseVisionLabEvents(
      frames: frames,
      states: states,
      videoEndMs: 166,
    );
    const truth = <VisionLabEvent>[
      VisionLabEvent(state: 'normal', startMs: 0, endMs: 33),
      VisionLabEvent(state: 'head_turned', startMs: 33, endMs: 132),
      VisionLabEvent(state: 'normal', startMs: 132, endMs: 166),
    ];

    final metrics = evaluateVisionLabStrategy(
      frames: frames,
      frameStates: states,
      predictedEvents: predicted,
      groundTruthEvents: truth,
    );

    expect(metrics.matchedEvents, 1);
    expect(metrics.missedEvents, 0);
    expect(metrics.falsePositiveEvents, 0);
    expect(metrics.averageDelayMs, 33);
  });
}

List<VisionLabFrame> _frames(List<String> states) {
  return <VisionLabFrame>[
    for (var index = 0; index < states.length; index++)
      VisionLabFrame(
        frameIndex: index,
        timestampMs: index * 33,
        rawState: states[index],
      ),
  ];
}
