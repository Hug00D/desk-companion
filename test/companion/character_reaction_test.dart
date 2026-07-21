import 'dart:convert';

import 'package:desk_companion/companion/character_reaction.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('moods map to the March 7th expression order', () {
    expect(CompanionCharacterMood.neutral.expressionIndex, 8);
    expect(CompanionCharacterMood.attentive.expressionIndex, 6);
    expect(CompanionCharacterMood.tired.expressionIndex, 0);
    expect(CompanionCharacterMood.distracted.expressionIndex, 4);
    expect(CompanionCharacterMood.sleeping.expressionIndex, 5);
    expect(CompanionCharacterMood.away.expressionIndex, 8);
  });

  test('short reactions use registered model motion groups', () {
    expect(CompanionCharacterReaction.welcome.motionGroup, 'Interaction');
    expect(CompanionCharacterReaction.reminder.motionGroup, 'Interaction');
    expect(CompanionCharacterReaction.success.motionGroup, 'Success');
    expect(CompanionCharacterReaction.focusCompleted.motionGroup, 'Success');
  });

  test('thinking and error reactions only change expression', () {
    expect(CompanionCharacterReaction.thinking.motionGroup, isNull);
    expect(CompanionCharacterReaction.thinking.expressionIndex, 6);
    expect(CompanionCharacterReaction.error.motionGroup, isNull);
    expect(CompanionCharacterReaction.error.expressionIndex, 5);
  });

  test(
    'March 7th model references are present in the Flutter asset bundle',
    () async {
      const modelRoot = 'assets/March 7th/';
      final source = await rootBundle.loadString(
        '${modelRoot}march 7th.model3.json',
      );
      final model = jsonDecode(source) as Map<String, dynamic>;
      final references = model['FileReferences'] as Map<String, dynamic>;
      final expressions = references['Expressions'] as List<dynamic>;
      final motionGroups = references['Motions'] as Map<String, dynamic>;

      final referencedFiles = <String>[
        references['Moc'] as String,
        ...(references['Textures'] as List<dynamic>).cast<String>(),
        references['Physics'] as String,
        references['DisplayInfo'] as String,
        ...expressions.map(
          (entry) => (entry as Map<String, dynamic>)['File'] as String,
        ),
        ...motionGroups.values.expand(
          (group) => (group as List<dynamic>).map(
            (entry) => (entry as Map<String, dynamic>)['File'] as String,
          ),
        ),
      ];

      expect(expressions, hasLength(9));
      expect(
        motionGroups.keys,
        containsAll(<String>['Idle', 'Interaction', 'Success']),
      );
      for (final path in referencedFiles) {
        final data = await rootBundle.load('$modelRoot$path');
        expect(data.lengthInBytes, greaterThan(0), reason: path);
      }
    },
  );

  test('March 7th idle motion loops and drives model physics', () async {
    const idlePath = 'assets/March 7th/motions/idle.motion3.json';
    final source = await rootBundle.loadString(idlePath);
    final motion = jsonDecode(source) as Map<String, dynamic>;
    final meta = motion['Meta'] as Map<String, dynamic>;
    final curves = (motion['Curves'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final parameterIds = curves
        .where((curve) => curve['Target'] == 'Parameter')
        .map((curve) => curve['Id'] as String)
        .toSet();

    expect(meta['Loop'], isTrue);
    expect(meta['Duration'] as num, greaterThan(0));
    expect(
      parameterIds,
      containsAll(<String>[
        'ParamAngleX',
        'ParamAngleY',
        'ParamAngleZ',
        'ParamBodyAngleY',
        'ParamBreath',
        'ParamEyeBallX',
      ]),
    );
  });

  test('March 7th expressions use smooth transitions', () async {
    const expressionRoot = 'assets/March 7th/exp/';

    for (final filename in <String>[
      '1.exp3.json',
      '2.exp3.json',
      '3.exp3.json',
      '4.exp3.json',
      '5.exp3.json',
      '6.exp3.json',
      '7.exp3.json',
      '8.exp3.json',
      'neutral.exp3.json',
    ]) {
      final source = await rootBundle.loadString('$expressionRoot$filename');
      final expression = jsonDecode(source) as Map<String, dynamic>;

      expect(expression['FadeInTime'] as num, greaterThan(0), reason: filename);
      expect(
        expression['FadeOutTime'] as num,
        greaterThan(0),
        reason: filename,
      );
    }
  });
}
