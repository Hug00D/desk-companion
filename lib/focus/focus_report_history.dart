import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'focus_session_report.dart';

class FocusReportRecord {
  const FocusReportRecord({
    required this.id,
    required this.report,
    this.startedAt,
  });

  final String id;
  final DateTime? startedAt;
  final FocusSessionReport report;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
    'report': report.toJson(),
  };

  factory FocusReportRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final report = json['report'];
    if (id is! String || id.isEmpty || report is! Map) {
      throw const FormatException('Invalid report record');
    }
    return FocusReportRecord(
      id: id,
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String).toLocal(),
      report: FocusSessionReport.fromJson(Map<String, dynamic>.from(report)),
    );
  }
}

/// Completed reports live in this device's app storage, isolated by account.
class FocusReportHistoryRepository {
  FocusReportHistoryRepository({
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static final instance = FocusReportHistoryRepository();

  final Future<Directory> Function() _directoryProvider;
  final Map<String, Future<void>> _writes = {};

  String _owner(String? userId) => userId == null ? 'guest' : 'user:$userId';

  Future<File> _file(String owner) async {
    final directory = await _directoryProvider();
    final key = base64Url.encode(utf8.encode(owner)).replaceAll('=', '');
    return File(
      '${directory.path}${Platform.pathSeparator}focus_reports_$key.json',
    );
  }

  Future<List<FocusReportRecord>> list({required String? userId}) async {
    final owner = _owner(userId);
    await _writes[owner];
    return _read(owner);
  }

  Future<List<FocusReportRecord>> _read(String owner) async {
    final file = await _file(owner);
    if (!await file.exists()) return [];
    final json = jsonDecode(await file.readAsString());
    if (json is! Map ||
        json['schemaVersion'] != 1 ||
        json['owner'] != owner ||
        json['reports'] is! List) {
      throw const FormatException('Invalid report history');
    }
    final result = <FocusReportRecord>[];
    for (final item in json['reports'] as List) {
      if (item is! Map) throw const FormatException('Invalid report record');
      result.add(FocusReportRecord.fromJson(Map<String, dynamic>.from(item)));
    }
    result.sort((a, b) => b.report.completedAt.compareTo(a.report.completedAt));
    return result;
  }

  Future<void> save({
    required String? userId,
    required FocusReportRecord record,
  }) async {
    final owner = _owner(userId);
    final previous = _writes[owner] ?? Future<void>.value();
    final write = previous.catchError((Object _) {}).then((_) async {
      // Never overwrite an unreadable history with an empty replacement.
      final records = await _read(owner);
      records.removeWhere((item) => item.id == record.id);
      records.add(record);
      records.sort(
        (a, b) => b.report.completedAt.compareTo(a.report.completedAt),
      );
      final file = await _file(owner);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'owner': owner,
          'reports': records.map((item) => item.toJson()).toList(),
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    });
    _writes[owner] = write;
    try {
      await write;
    } finally {
      if (identical(_writes[owner], write)) _writes.remove(owner);
    }
  }
}
