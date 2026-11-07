import 'package:desk_companion/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login hides unfinished recovery and Google entry points', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Forgot Password?'), findsNothing);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('OR'), findsNothing);
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(
      find.textContaining('Create Account', findRichText: true),
      findsOneWidget,
    );
  });
}
