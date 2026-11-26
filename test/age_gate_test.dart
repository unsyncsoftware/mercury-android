import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unsync/screens/age_gate_screen.dart';
import 'package:unsync/services/age_confirmation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AgeConfirmation', () {
    test('is not confirmed on a fresh install', () async {
      expect(await AgeConfirmation.isConfirmed(), isFalse);
    });

    test('remembers a confirmation', () async {
      await AgeConfirmation.confirm();
      expect(await AgeConfirmation.isConfirmed(), isTrue);
    });
  });

  group('AgeGateScreen', () {
    Future<void> show(WidgetTester tester, {required VoidCallback onConfirmed}) {
      return tester.pumpWidget(
        MaterialApp(home: AgeGateScreen(onConfirmed: onConfirmed)),
      );
    }

    testWidgets('Continue is disabled until the box is ticked', (tester) async {
      await show(tester, onConfirmed: () {});
      final button = find.widgetWithText(FilledButton, 'Continue');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('confirming stores it and continues', (tester) async {
      var continued = false;
      await show(tester, onConfirmed: () => continued = true);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(continued, isTrue);
      expect(
        await tester.runAsync(AgeConfirmation.isConfirmed),
        isTrue,
      );
    });

    testWidgets('under 18 is blocked and nothing is stored', (tester) async {
      var continued = false;
      await show(tester, onConfirmed: () => continued = true);
      await tester.tap(find.text('I am under 18'));
      await tester.pump();
      expect(find.textContaining('only for adults'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continue'), findsNothing);
      expect(continued, isFalse);
      expect(await tester.runAsync(AgeConfirmation.isConfirmed), isFalse);
    });
  });
}
