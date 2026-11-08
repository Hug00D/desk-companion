import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../focus/focus_report_history.dart';
import '../widgets/focus_session_report_dialog.dart';

class FocusReportHistoryScreen extends StatefulWidget {
  const FocusReportHistoryScreen({
    super.key,
    this.repository,
    this.authSession,
  });

  final FocusReportHistoryRepository? repository;
  final AuthSession? authSession;

  @override
  State<FocusReportHistoryScreen> createState() =>
      _FocusReportHistoryScreenState();
}

class _FocusReportHistoryScreenState extends State<FocusReportHistoryScreen> {
  late final FocusReportHistoryRepository _repository;
  late final AuthSession _auth;
  String? _owner;
  late Future<List<FocusReportRecord>> _reports;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FocusReportHistoryRepository.instance;
    _auth = widget.authSession ?? AuthSession.instance;
    _owner = _auth.userId;
    _reports = _repository.list(userId: _owner);
    _auth.addListener(_accountChanged);
  }

  void _accountChanged() {
    if (_owner == _auth.userId) return;
    _owner = _auth.userId;
    setState(() {
      _reports = _repository.list(userId: _owner);
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _reports = _repository.list(userId: _owner);
    });
    try {
      await _reports;
    } catch (_) {
      // The page presents a read error without replacing the stored file.
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_accountChanged);
    super.dispose();
  }

  String _time(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _duration(Duration value) => value.inMinutes > 0
      ? '${value.inMinutes} 分 ${value.inSeconds.remainder(60)} 秒'
      : '${value.inSeconds} 秒';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10283D),
      appBar: AppBar(
        title: const Text('專注紀錄'),
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF10283D),
        actions: [
          IconButton(
            tooltip: '重新整理',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<FocusReportRecord>>(
        future: _reports,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '暫時無法讀取本機專注紀錄，請重新整理。',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('重新整理'),
                    ),
                  ],
                ),
              ),
            );
          }
          final records = snapshot.data ?? [];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
              itemCount: records.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '每一輪的評分表',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _owner == null ? '此裝置的訪客紀錄' : '此裝置・目前帳號的已完成場次',
                          style: const TextStyle(color: Color(0xCCFFFFFF)),
                        ),
                        if (records.isEmpty) ...[
                          const SizedBox(height: 32),
                          const Text(
                            '還沒有保存的評分表。完成一輪專注後，報告會自動保存在這裡，重開 App 也能查看。',
                            style: TextStyle(color: Colors.white, height: 1.6),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                final record = records[index - 1];
                final report = record.report;
                return Card(
                  color: const Color(0xFF193B52),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    title: Text(
                      _time(report.completedAt),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '計畫 ${_duration(report.plannedDuration)}\n有效專注 ${_duration(report.effectiveFocusDuration)}・事件 ${report.totalEventCount} 次',
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        height: 1.5,
                      ),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          report.score == null ? '資料不足' : '${report.score} 分',
                          style: const TextStyle(
                            color: Color(0xFF9FF3D0),
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          report.usesLegacyScoring ? '舊版評分 ›' : '查看評分表 ›',
                          style: const TextStyle(
                            color: Color(0xFF9FDFFF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    onTap: () => showFocusSessionReportDialog(
                      context: context,
                      report: report,
                      startedAt: record.startedAt,
                      isHistory: true,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
