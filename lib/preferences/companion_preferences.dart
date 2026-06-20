enum ReminderSensitivity { low, normal, high }

enum AiResponseTone { supportive, encouraging, strict }

class CompanionPreferences {
  const CompanionPreferences({
    this.quietMode = false,
    this.reminderSensitivity = ReminderSensitivity.normal,
    this.aiResponseTone = AiResponseTone.supportive,
    this.timezone = 'Asia/Taipei',
    this.syncEnabled = true,
    this.storeTranscript = false,
    this.storeDebugSnapshot = false,
    this.schemaVersion = 1,
  });

  final bool quietMode;
  final ReminderSensitivity reminderSensitivity;
  final AiResponseTone aiResponseTone;
  final String timezone;
  final bool syncEnabled;
  final bool storeTranscript;
  final bool storeDebugSnapshot;
  final int schemaVersion;

  factory CompanionPreferences.fromJson(Map<String, dynamic> json) {
    return CompanionPreferences(
      quietMode: json['quietMode'] == true,
      reminderSensitivity: ReminderSensitivity.values.firstWhere(
        (value) => value.name == json['reminderSensitivity'],
        orElse: () => ReminderSensitivity.normal,
      ),
      aiResponseTone: AiResponseTone.values.firstWhere(
        (value) => value.name == json['aiResponseTone'],
        orElse: () => AiResponseTone.supportive,
      ),
      timezone: json['timezone']?.toString() ?? 'Asia/Taipei',
      syncEnabled: json['syncEnabled'] != false,
      storeTranscript: json['storeTranscript'] == true,
      storeDebugSnapshot: json['storeDebugSnapshot'] == true,
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'quietMode': quietMode,
      'reminderSensitivity': reminderSensitivity.name,
      'aiResponseTone': aiResponseTone.name,
      'timezone': timezone,
      'syncEnabled': syncEnabled,
      'storeTranscript': storeTranscript,
      'storeDebugSnapshot': storeDebugSnapshot,
      'schemaVersion': schemaVersion,
    };
  }

  CompanionPreferences copyWith({
    bool? quietMode,
    ReminderSensitivity? reminderSensitivity,
    AiResponseTone? aiResponseTone,
    String? timezone,
    bool? syncEnabled,
    bool? storeTranscript,
    bool? storeDebugSnapshot,
  }) {
    return CompanionPreferences(
      quietMode: quietMode ?? this.quietMode,
      reminderSensitivity: reminderSensitivity ?? this.reminderSensitivity,
      aiResponseTone: aiResponseTone ?? this.aiResponseTone,
      timezone: timezone ?? this.timezone,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      storeTranscript: storeTranscript ?? this.storeTranscript,
      storeDebugSnapshot: storeDebugSnapshot ?? this.storeDebugSnapshot,
      schemaVersion: schemaVersion,
    );
  }
}
