import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unsync/services/identity_service.dart';
import 'package:unsync/services/relay_service.dart';

// A relay running with ENFORCE_RELAY_SENDER_AUTH=1 rejects `register` from a
// connection that has not authenticated (AUTH_REQUIRED_FOR_RELAY), and the app
// never retried, so the device was never registered and received nothing. The
// app must therefore register only after the relay answers auth_ok.
void main() {
  late List<Map<String, dynamic>> sent;
  late RelayService relay;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'peer_id': 'mercury-peer'});
    sent = [];
    relay = RelayService(
      identityService: IdentityService(),
      sendOverride: sent.add,
      registerFallbackDelay: const Duration(milliseconds: 50),
    );
  });

  tearDown(() => relay.dispose());

  Future<void> receive(Map<String, dynamic> message) =>
      relay.handleMessageForTest(jsonEncode(message));

  const challenge = {
    'type': 'auth_challenge',
    'version': 'cloaknet-auth-v1',
    'nonce': 'relay-nonce',
    'server_time': 1234567890,
  };

  List<String> types() => sent.map((m) => m['type'] as String).toList();

  test('registers only after the relay accepts the auth response', () async {
    relay.beginRegistrationForTest('mercury-peer', 'fcm-token');
    expect(sent, isEmpty, reason: 'nothing may be sent before the challenge');

    await receive(challenge);
    expect(types(), ['auth_response'], reason: 'answer the challenge first');

    await receive({'type': 'auth_ok', 'peer_id': 'mercury-peer'});
    expect(types(), ['auth_response', 'register']);
    expect(sent.last['id'], 'mercury-peer');
    expect(sent.last['fcmToken'], 'fcm-token');
  });

  test('registers once even if auth_ok is repeated', () async {
    relay.beginRegistrationForTest('mercury-peer', null);
    await receive(challenge);
    await receive({'type': 'auth_ok'});
    await receive({'type': 'auth_ok'});
    expect(types().where((t) => t == 'register'), hasLength(1));
  });

  test('registers directly with a relay that never sends a challenge', () async {
    relay.beginRegistrationForTest('mercury-peer', null);
    expect(sent, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(types(), ['register']);
  });

  test('registers directly when the challenge is malformed', () async {
    relay.beginRegistrationForTest('mercury-peer', null);
    await receive({'type': 'auth_challenge'});
    expect(types(), ['register']);
  });

  test('registers directly when the relay rejects the auth response', () async {
    relay.beginRegistrationForTest('mercury-peer', null);
    await receive(challenge);
    await receive({'type': 'auth_failed', 'error': 'AUTH_INVALID'});
    expect(types(), ['auth_response', 'register']);
  });
}
