import 'companion_event.dart';

class CompanionEventBuffer {
  final List<CompanionEvent> _pending = <CompanionEvent>[];

  List<CompanionEvent> get pending =>
      List<CompanionEvent>.unmodifiable(_pending);
  bool get isEmpty => _pending.isEmpty;
  int get length => _pending.length;

  void add(CompanionEvent event) {
    if (_pending.any((item) => item.clientEventId == event.clientEventId)) {
      return;
    }
    _pending.add(event);
  }

  void addAll(Iterable<CompanionEvent> events) {
    for (final event in events) {
      add(event);
    }
  }

  List<CompanionEvent> takeBatch({int limit = 50}) {
    if (limit <= 0 || _pending.isEmpty) return const <CompanionEvent>[];
    final end = limit < _pending.length ? limit : _pending.length;
    return List<CompanionEvent>.unmodifiable(_pending.take(end));
  }

  Map<String, dynamic> buildBatchPayload({int limit = 50}) {
    return CompanionEvent.batchPayload(takeBatch(limit: limit));
  }

  void markUploaded(Iterable<String> clientEventIds) {
    final uploaded = clientEventIds.toSet();
    _pending.removeWhere((event) => uploaded.contains(event.clientEventId));
  }

  void clear() => _pending.clear();
}
