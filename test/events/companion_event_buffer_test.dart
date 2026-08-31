import 'package:desk_companion/events/companion_event.dart';
import 'package:desk_companion/events/companion_event_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps only the newest events up to the configured bound', () {
    final buffer = CompanionEventBuffer(maxPendingEvents: 3);

    for (var index = 0; index < 5; index++) {
      buffer.add(_event('event-$index'));
    }

    expect(buffer.length, 3);
    expect(buffer.pending.map((event) => event.clientEventId), [
      'event-2',
      'event-3',
      'event-4',
    ]);
  });

  test('deduplicates pending client event ids after trim and upload', () {
    final buffer = CompanionEventBuffer(maxPendingEvents: 2);

    buffer.add(_event('event-0'));
    buffer.add(_event('event-1'));
    buffer.add(_event('event-2'));
    buffer.add(_event('event-0'));
    buffer.add(_event('event-2'));

    expect(buffer.pending.map((event) => event.clientEventId), [
      'event-2',
      'event-0',
    ]);

    buffer.markUploaded(['event-2']);
    buffer.add(_event('event-2'));

    expect(buffer.pending.map((event) => event.clientEventId), [
      'event-0',
      'event-2',
    ]);
  });
}

CompanionEvent _event(String id) {
  return CompanionEvent.create(
    clientEventId: id,
    sessionId: 'session',
    source: CompanionEventSource.vision,
    eventType: 'test',
    occurredAt: DateTime(2026),
  );
}
