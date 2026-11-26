import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:unsync/services/handle_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('normalize', () {
    test('adds @ and lower-cases', () {
      expect(HandleService.normalize(' Batman '), '@batman');
      expect(HandleService.normalize('@Bat.Man'), '@bat.man');
    });
  });

  group('validate', () {
    test('accepts good handles with or without @', () {
      for (final h in ['@batman', 'batman', '@bat.man', '@b', '@bat_man-2', '@Ab']) {
        expect(HandleService.validate(h), isNull, reason: h);
      }
    });

    test('rejects bad handles', () {
      for (final h in ['', '@', '@-x', '@x-', '@has space', '@émile', '@${'a' * 65}', '@bat!']) {
        expect(HandleService.validate(h), isNotNull, reason: h);
      }
    });

    test('64 characters is the longest allowed', () {
      expect(HandleService.validate('@${'a' * 64}'), isNull);
    });
  });

  group('suggestFrom', () {
    test('builds a handle from the display name', () {
      expect(HandleService.suggestFrom('Bat Man!'), '@bat.man');
      expect(HandleService.suggestFrom('  batman  '), '@batman');
      expect(HandleService.suggestFrom('Mr. -- Wayne'), '@mr.wayne');
    });

    test('falls back to user plus four digits', () {
      final s = HandleService.suggestFrom('!!!', random: Random(1));
      expect(s, matches(RegExp(r'^@user\d{4}$')));
      expect(HandleService.validate(s), isNull);
    });

    test('suggestions are always valid and short enough', () {
      final s = HandleService.suggestFrom('a' * 100);
      expect(HandleService.validate(s), isNull);
    });
  });

  group('saved handle', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('starts empty and remembers a saved handle', () async {
      expect(await HandleService.savedHandle(), isNull);
      await HandleService.save('@Batman');
      expect(await HandleService.savedHandle(), '@batman');
    });
  });

  group('handle is the shown name', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('display drops the @', () {
      expect(HandleService.display('@batman'), 'batman');
      expect(HandleService.display('batman'), 'batman');
      expect(HandleService.display('@Bat.Man'), 'bat.man');
    });

    test('adopting a handle saves it and makes it the shown name', () async {
      String? shown;
      await HandleService.adopt('@Batman', (name) async => shown = name);
      expect(shown, 'batman');
      expect(await HandleService.savedHandle(), '@batman');
    });
  });

  test('messages explain each server reason in plain words', () {
    for (final r in ['taken', 'held', 'reserved', 'invalid', 'rate_limited', 'timeout', 'peer_id_taken', 'not_authenticated']) {
      expect(HandleService.reasonText(r), isNotEmpty, reason: r);
    }
  });
}
