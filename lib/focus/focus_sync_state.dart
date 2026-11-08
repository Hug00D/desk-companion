enum FocusSyncPhase { localOnly, syncing, pending, failed, synced }

class FocusSyncState {
  const FocusSyncState({
    this.phase = FocusSyncPhase.localOnly,
    this.pendingEvents = 0,
    this.pendingRounds = 0,
    this.lastSyncedAt,
    this.message,
  });

  final FocusSyncPhase phase;
  final int pendingEvents;
  final int pendingRounds;
  final DateTime? lastSyncedAt;
  final String? message;

  String get label => switch (phase) {
    FocusSyncPhase.localOnly => '未登入：本機紀錄不會同步',
    FocusSyncPhase.syncing => '正在同步專注紀錄…',
    FocusSyncPhase.pending => '有紀錄等待同步',
    FocusSyncPhase.failed => '專注紀錄同步失敗',
    FocusSyncPhase.synced => '專注紀錄已同步',
  };
}
