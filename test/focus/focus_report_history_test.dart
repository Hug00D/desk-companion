import 'dart:convert';
import 'dart:io';

import 'package:desk_companion/focus/focus_report_history.dart';
import 'package:desk_companion/focus/focus_session_report.dart';
import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

FocusSessionReport reportAt(DateTime completedAt, {bool enoughData = true}) =>
    FocusSessionReport(
      completedAt: completedAt,
      plannedDuration: const Duration(minutes: 25),
      effectiveFocusDuration: Duration(seconds: enoughData ? 960 : 5),
      distractedDuration: Duration(seconds: enoughData ? 240 : 0),
      awayDuration: Duration(seconds: enoughData ? 60 : 0),
      eventCounts: const {
        CompanionStatus.distracted: 2,
        CompanionStatus.sleeping: 1,
      },
      causeEventCounts: const {
        CompanionCause.headTurned: 2,
        CompanionCause.postureDown: 1,
      },
    );

void main() {
  late Directory directory;
  late FocusReportHistoryRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'focus-report-history-test-',
    );
    repository = FocusReportHistoryRepository(
      directoryProvider: () async => directory,
    );
  });
  tearDown(() async {
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await directory.resolveSymbolicLinks();
    if (!target.toLowerCase().startsWith(
      '${root.toLowerCase()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unexpected temporary directory');
    }
    await directory.delete(recursive: true);
  });

  test(
    'a new repository restores each complete report after an app restart',
    () async {
      final original = reportAt(DateTime(2026, 11, 8, 18, 25));
      final startedAt = original.completedAt.subtract(
        const Duration(minutes: 25),
      );
      await repository.save(
        userId: 'user-a',
        record: FocusReportRecord(
          id: 'round-1',
          startedAt: startedAt,
          report: original,
        ),
      );
      final reopened = FocusReportHistoryRepository(
        directoryProvider: () async => directory,
      );
      final saved = (await reopened.list(userId: 'user-a')).single;
      expect(saved.id, 'round-1');
      expect(saved.startedAt, startedAt);
      expect(saved.report.toJson(), original.toJson());
      expect(saved.report.score, 60);
      expect(saved.report.grade, 'C');
      expect(saved.report.awayDuration, const Duration(minutes: 1));
      expect(saved.report.usesLegacyScoring, isFalse);
      expect(saved.report.causeEventCountFor(CompanionCause.postureDown), 1);
    },
  );

  test('saved evaluation is replayed rather than recalculated', () {
    final json = reportAt(DateTime(2026, 11, 8)).toJson();
    json.remove('awayMilliseconds');
    json['evaluation'] = {
      'version': 1,
      'score': 61,
      'grade': 'C',
      'feedback': '當時保存的評語',
    };
    final restored = FocusSessionReport.fromJson(
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
    );
    expect(restored.score, 61);
    expect(restored.grade, 'C');
    expect(restored.feedback, '當時保存的評語');
    expect(restored.awayDuration, isNull);
    expect(restored.usesLegacyScoring, isTrue);
    expect(restored.toJson()['evaluation']['version'], 1);
  });

  test('insufficient observations remain unscored in saved history', () async {
    await repository.save(
      userId: 'user-a',
      record: FocusReportRecord(
        id: 'insufficient',
        report: reportAt(DateTime(2026, 11, 8), enoughData: false),
      ),
    );
    final saved = (await repository.list(userId: 'user-a')).single.report;
    expect(saved.score, isNull);
    expect(saved.grade, '--');
    expect(saved.feedback, contains('資料不足'));
  });

  test(
    'accounts and guest history stay separate, including unusual account identifiers',
    () async {
      for (final owner in <String?>['user-a', '../使用者-b', null]) {
        await repository.save(
          userId: owner,
          record: FocusReportRecord(
            id: owner ?? 'guest',
            report: reportAt(DateTime(2026, 11, 8)),
          ),
        );
      }
      expect((await repository.list(userId: 'user-a')).single.id, 'user-a');
      expect((await repository.list(userId: '../使用者-b')).single.id, '../使用者-b');
      expect((await repository.list(userId: null)).single.id, 'guest');
      expect(await repository.list(userId: 'unrelated'), isEmpty);
      expect(await directory.list().length, 3);
    },
  );

  test(
    'concurrent saves keep all rounds, ordered newest first, without duplicate ids',
    () async {
      await Future.wait(
        List.generate(
          5,
          (index) => repository.save(
            userId: 'user-a',
            record: FocusReportRecord(
              id: 'round-$index',
              report: reportAt(DateTime(2026, 11, 8, index)),
            ),
          ),
        ),
      );
      final original = await repository.list(userId: 'user-a');
      expect(original.map((record) => record.id), [
        'round-4',
        'round-3',
        'round-2',
        'round-1',
        'round-0',
      ]);
      await repository.save(userId: 'user-a', record: original.first);
      expect(await repository.list(userId: 'user-a'), hasLength(5));
    },
  );

  test(
    'unreadable existing data is not overwritten on the next save',
    () async {
      await repository.save(
        userId: 'user-a',
        record: FocusReportRecord(
          id: 'round-1',
          report: reportAt(DateTime(2026, 11, 8)),
        ),
      );
      final file = (await directory.list().toList()).whereType<File>().single;
      await file.writeAsString('corrupted report data');
      await expectLater(
        repository.save(
          userId: 'user-a',
          record: FocusReportRecord(
            id: 'round-2',
            report: reportAt(DateTime(2026, 11, 9)),
          ),
        ),
        throwsFormatException,
      );
      expect(await file.readAsString(), 'corrupted report data');
    },
  );
}
