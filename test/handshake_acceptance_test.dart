import 'package:flutter_test/flutter_test.dart';
import 'package:unsync/services/pairing_window_service.dart';

void main() {
  setUp(PairingWindowService.reset);
  tearDown(PairingWindowService.reset);

  group('mayAcceptHandshake', () {
    test('a saved contact introducing itself is accepted', () {
      expect(
        PairingWindowService.mayAcceptHandshake(
          senderId: '1', claimedId: '1', isSavedContact: true),
        isTrue,
      );
    });

    test('a stranger is refused while no pairing is in progress', () {
      expect(
        PairingWindowService.mayAcceptHandshake(
          senderId: '2', claimedId: '2', isSavedContact: false),
        isFalse,
      );
    });

    test('a stranger is accepted while the QR screen is open', () {
      PairingWindowService.open();
      expect(
        PairingWindowService.mayAcceptHandshake(
          senderId: '2', claimedId: '2', isSavedContact: false),
        isTrue,
      );
    });

    test('a stranger is refused once the grace period has passed', () {
      var t = DateTime(2026, 1, 1, 12);
      PairingWindowService.now = () => t;
      PairingWindowService.open();
      PairingWindowService.close();
      t = t.add(PairingWindowService.grace + const Duration(seconds: 1));
      expect(
        PairingWindowService.mayAcceptHandshake(
          senderId: '2', claimedId: '2', isSavedContact: false),
        isFalse,
      );
    });

    test('a claimed id that differs from the real sender is refused, even for a saved contact', () {
      PairingWindowService.open();
      expect(
        PairingWindowService.mayAcceptHandshake(
          senderId: '2', claimedId: '1', isSavedContact: true),
        isFalse,
      );
    });
  });
}
