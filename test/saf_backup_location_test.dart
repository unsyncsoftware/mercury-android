import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unsync/services/android_backup_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? reply;

  setUp(() {
    calls.clear();
    reply = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidBackupChannel.channel, (call) async {
      calls.add(call);
      return reply?.call(call);
    });
  });

  test('writing sends the folder, file name and bytes', () async {
    final loc = SafBackupLocation('content://tree/abc');
    await loc.write('Mercury.mercurybackup', Uint8List.fromList([1, 2, 3]));
    expect(calls.single.method, 'write');
    expect(calls.single.arguments['uri'], 'content://tree/abc');
    expect(calls.single.arguments['name'], 'Mercury.mercurybackup');
    expect(calls.single.arguments['bytes'], [1, 2, 3]);
  });

  test('availability comes from the platform, and an error means unavailable', () async {
    reply = (_) => true;
    expect(await SafBackupLocation('content://tree/abc').isAvailable(), isTrue);
    reply = (_) => throw PlatformException(code: 'backup_failed');
    expect(await SafBackupLocation('content://tree/abc').isAvailable(), isFalse);
    expect(await SafBackupLocation('').isAvailable(), isFalse);
  });

  test('a write failure surfaces as an error the backup can record', () async {
    reply = (_) => throw PlatformException(code: 'backup_failed', message: 'disk full');
    expect(
      () => SafBackupLocation('content://tree/abc').write('a', Uint8List(1)),
      throwsA(isA<PlatformException>()),
    );
  });

  test('picking a folder returns its address and name, or null when cancelled', () async {
    reply = (_) => {'uri': 'content://tree/abc', 'name': 'Download'};
    final picked = await AndroidBackupChannel.pickFolder();
    expect(picked?.uri, 'content://tree/abc');
    expect(picked?.name, 'Download');
    reply = (_) => null;
    expect(await AndroidBackupChannel.pickFolder(), isNull);
  });

  test('picking a file returns its bytes, or null when cancelled', () async {
    reply = (_) => {'name': 'Mercury.mercurybackup', 'bytes': Uint8List.fromList([9, 8])};
    final file = await AndroidBackupChannel.pickFile();
    expect(file?.name, 'Mercury.mercurybackup');
    expect(file?.bytes, [9, 8]);
    reply = (_) => null;
    expect(await AndroidBackupChannel.pickFile(), isNull);
  });
}
