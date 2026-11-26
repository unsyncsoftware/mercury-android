import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unsync/screens/choose_handle_screen.dart';
import 'package:unsync/services/handle_service.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    required Future<HandleClaimResult> Function(String) claim,
    required void Function(String) onDone,
    VoidCallback? onLater,
  }) {
    return tester.pumpWidget(MaterialApp(
      home: ChooseHandleScreen(
        initial: '@batman',
        claim: claim,
        onDone: onDone,
        onLater: onLater,
      ),
    ));
  }

  testWidgets('starts with the suggested handle filled in', (tester) async {
    await show(tester, claim: (_) async => const HandleClaimResult(ok: true), onDone: (_) {});
    expect(find.widgetWithText(TextField, 'batman'), findsOneWidget);
  });

  testWidgets('a malformed handle is caught before asking the server', (tester) async {
    var asked = false;
    await show(tester, claim: (_) async {
      asked = true;
      return const HandleClaimResult(ok: true);
    }, onDone: (_) {});
    await tester.enterText(find.byType(TextField), 'bad handle');
    await tester.tap(find.text('Save handle'));
    await tester.pump();
    expect(asked, isFalse);
    expect(find.textContaining('letters, numbers'), findsOneWidget);
  });

  testWidgets('a taken handle shows the reason and stays on the screen', (tester) async {
    String? done;
    await show(
      tester,
      claim: (_) async => const HandleClaimResult(ok: false, reason: 'taken'),
      onDone: (h) => done = h,
    );
    await tester.tap(find.text('Save handle'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already taken'), findsOneWidget);
    expect(done, isNull);
  });

  testWidgets('a successful claim reports the handle the server confirmed', (tester) async {
    String? claimed;
    String? done;
    await show(
      tester,
      claim: (h) async {
        claimed = h;
        return const HandleClaimResult(ok: true, handle: '@bat.man');
      },
      onDone: (h) => done = h,
    );
    await tester.enterText(find.byType(TextField), 'Bat.Man');
    await tester.tap(find.text('Save handle'));
    await tester.pumpAndSettle();
    expect(claimed, '@bat.man');
    expect(done, '@bat.man');
  });

  testWidgets('Later is offered only when allowed', (tester) async {
    var later = false;
    await show(
      tester,
      claim: (_) async => const HandleClaimResult(ok: true),
      onDone: (_) {},
      onLater: () => later = true,
    );
    await tester.tap(find.text('Later'));
    expect(later, isTrue);

    await show(tester, claim: (_) async => const HandleClaimResult(ok: true), onDone: (_) {});
    expect(find.text('Later'), findsNothing);
  });
}
