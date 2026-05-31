enum PomodoroStatus { idle, running, paused, completed }

class PomodoroController {
  PomodoroStatus status = PomodoroStatus.idle;
  Duration totalDuration = Duration.zero;
  Duration remaining = Duration.zero;

  bool get isRunning => status == PomodoroStatus.running;
  bool get isActive =>
      status == PomodoroStatus.running || status == PomodoroStatus.paused;

  void start({required int durationMinutes}) {
    totalDuration = Duration(minutes: durationMinutes);
    remaining = totalDuration;
    status = PomodoroStatus.running;
  }

  void pause() {
    if (status == PomodoroStatus.running) {
      status = PomodoroStatus.paused;
    }
  }

  void resume() {
    if (status == PomodoroStatus.paused) {
      status = PomodoroStatus.running;
    }
  }

  void stop() {
    status = PomodoroStatus.idle;
    totalDuration = Duration.zero;
    remaining = Duration.zero;
  }

  void tick() {
    if (status != PomodoroStatus.running) return;

    final nextRemaining = remaining - const Duration(seconds: 1);
    if (nextRemaining <= Duration.zero) {
      remaining = Duration.zero;
      status = PomodoroStatus.completed;
      return;
    }

    remaining = nextRemaining;
  }

  String get formattedRemaining {
    final minutes = remaining.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = remaining.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
