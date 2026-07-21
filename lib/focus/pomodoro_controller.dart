import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum PomodoroStatus { idle, running, paused, completed }

enum PomodoroPauseReason { manual, distracted, fatigue, sleeping, userMissing }

class PomodoroController extends ChangeNotifier {
  PomodoroController._();

  static final PomodoroController instance = PomodoroController._();

  factory PomodoroController() => instance;

  PomodoroStatus status = PomodoroStatus.idle;
  PomodoroPauseReason? pauseReason;
  Duration totalDuration = Duration.zero;
  Duration remaining = Duration.zero;

  Timer? _ticker;
  DateTime? _deadline;

  bool get isRunning => status == PomodoroStatus.running;
  bool get isActive =>
      status == PomodoroStatus.running || status == PomodoroStatus.paused;
  bool get isAutoPaused =>
      status == PomodoroStatus.paused &&
      pauseReason != null &&
      pauseReason != PomodoroPauseReason.manual;

  double get progress {
    if (totalDuration.inMilliseconds <= 0) return 0;
    final elapsed = totalDuration.inMilliseconds - remaining.inMilliseconds;
    return (elapsed / totalDuration.inMilliseconds).clamp(0.0, 1.0);
  }

  void start({required int durationMinutes}) {
    final safeMinutes = durationMinutes.clamp(1, 180);
    totalDuration = Duration(minutes: safeMinutes);
    remaining = totalDuration;
    status = PomodoroStatus.running;
    pauseReason = null;
    _deadline = DateTime.now().add(remaining);
    _startTicker();
    notifyListeners();
  }

  void pause({PomodoroPauseReason reason = PomodoroPauseReason.manual}) {
    if (status != PomodoroStatus.running) return;
    _refreshRemaining();
    status = PomodoroStatus.paused;
    pauseReason = reason;
    _deadline = null;
    _ticker?.cancel();
    notifyListeners();
  }

  void resume() {
    if (status != PomodoroStatus.paused || remaining <= Duration.zero) return;
    status = PomodoroStatus.running;
    pauseReason = null;
    _deadline = DateTime.now().add(remaining);
    _startTicker();
    notifyListeners();
  }

  void stop() {
    _ticker?.cancel();
    _deadline = null;
    status = PomodoroStatus.idle;
    pauseReason = null;
    totalDuration = Duration.zero;
    remaining = Duration.zero;
    notifyListeners();
  }

  void tick() {
    if (status != PomodoroStatus.running) return;
    _refreshRemaining();
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _refreshRemaining() {
    final deadline = _deadline;
    if (deadline == null) return;

    final milliseconds = deadline.difference(DateTime.now()).inMilliseconds;
    if (milliseconds <= 0) {
      remaining = Duration.zero;
      status = PomodoroStatus.completed;
      pauseReason = null;
      _deadline = null;
      _ticker?.cancel();
      return;
    }

    remaining = Duration(seconds: math.max(1, (milliseconds / 1000).ceil()));
  }

  String get formattedRemaining {
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = remaining.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
