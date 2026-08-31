enum CompanionCharacterMood {
  neutral,
  attentive,
  tired,
  distracted,
  sleeping,
  away,
}

enum CompanionCharacterReaction {
  none,
  welcome,
  success,
  thinking,
  confirmation,
  error,
  reminder,
  focusCompleted,
}

extension CompanionCharacterMoodSpec on CompanionCharacterMood {
  int get expressionIndex {
    return switch (this) {
      CompanionCharacterMood.neutral => 8,
      CompanionCharacterMood.attentive => 6,
      CompanionCharacterMood.tired => 0,
      CompanionCharacterMood.distracted => 4,
      CompanionCharacterMood.sleeping => 5,
      CompanionCharacterMood.away => 8,
    };
  }
}

extension CompanionCharacterReactionSpec on CompanionCharacterReaction {
  int? get expressionIndex {
    return switch (this) {
      CompanionCharacterReaction.none => null,
      CompanionCharacterReaction.welcome => 7,
      CompanionCharacterReaction.success => 7,
      CompanionCharacterReaction.thinking => 6,
      CompanionCharacterReaction.confirmation => 3,
      CompanionCharacterReaction.error => 5,
      CompanionCharacterReaction.reminder => null,
      CompanionCharacterReaction.focusCompleted => 1,
    };
  }

  String? get motionGroup {
    return switch (this) {
      CompanionCharacterReaction.welcome ||
      CompanionCharacterReaction.confirmation ||
      CompanionCharacterReaction.reminder => 'Interaction',
      CompanionCharacterReaction.success ||
      CompanionCharacterReaction.focusCompleted => 'Success',
      CompanionCharacterReaction.none ||
      CompanionCharacterReaction.thinking ||
      CompanionCharacterReaction.error => null,
    };
  }

  Duration get holdDuration {
    return switch (this) {
      CompanionCharacterReaction.none => Duration.zero,
      CompanionCharacterReaction.thinking => const Duration(seconds: 8),
      CompanionCharacterReaction.error => const Duration(seconds: 4),
      CompanionCharacterReaction.confirmation => const Duration(seconds: 5),
      CompanionCharacterReaction.welcome ||
      CompanionCharacterReaction.success ||
      CompanionCharacterReaction.reminder ||
      CompanionCharacterReaction.focusCompleted => const Duration(seconds: 3),
    };
  }
}
