import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'companion_preferences.dart';

abstract interface class CompanionPreferencesStore {
  Future<CompanionPreferences?> load();

  Future<void> save(CompanionPreferences preferences);
}

class FileCompanionPreferencesStore implements CompanionPreferencesStore {
  FileCompanionPreferencesStore({
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const String fileName = 'companion_preferences.json';

  final Future<Directory> Function() _directoryProvider;

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<CompanionPreferences?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return CompanionPreferences.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('Local preferences load failed; using defaults: $error');
      return null;
    }
  }

  @override
  Future<void> save(CompanionPreferences preferences) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final localPreferences = <String, dynamic>{
      'schemaVersion': preferences.schemaVersion,
      'quietMode': preferences.quietMode,
      'aiResponseTone': preferences.aiResponseTone.name,
      'voiceReplyEnabled': preferences.voiceReplyEnabled,
    };
    await file.writeAsString(jsonEncode(localPreferences), flush: true);
  }
}
