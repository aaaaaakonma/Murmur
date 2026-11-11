import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:bored_p2p_chat/crypto/triple_dh.dart';
import 'package:bored_p2p_chat/services/p2p_chat_service.dart';
import 'package:bored_p2p_chat/widgets/triple_dh_inspector_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Triple-DH (3DH) Telemetry & Latency Tests', () {
    test('TripleDH records hardware crypto execution durations for keygen and 3DH', () async {
      final x25519 = X25519();
      final aliceIK = await x25519.newKeyPair();
      final bobIK = await x25519.newKeyPair();

      final alice3DH = TripleDH(identityKeyPair: aliceIK);
      final bob3DH = TripleDH(identityKeyPair: bobIK);

      final aliceEKPub = await alice3DH.generateEphemeralKey();
      final bobEKPub = await bob3DH.generateEphemeralKey();

      expect(alice3DH.lastEphemeralGenDuration, isNotNull);
      expect(bob3DH.lastEphemeralGenDuration, isNotNull);

      final aliceIKPub = await aliceIK.extractPublicKey();
      final bobIKPub = await bobIK.extractPublicKey();

      final aliceSessionKey = await alice3DH.computeInitiatorSessionKey(
        remoteIdentityKey: bobIKPub,
        remoteEphemeralKey: bobEKPub,
      );

      final bobSessionKey = await bob3DH.computeResponderSessionKey(
        remoteIdentityKey: aliceIKPub,
        remoteEphemeralKey: aliceEKPub,
      );

      final aBytes = await aliceSessionKey.extractBytes();
      final bBytes = await bobSessionKey.extractBytes();
      expect(aBytes, equals(bBytes));

      // Verify Alice crypto timings
      expect(alice3DH.lastCryptoTimings, isNotNull);
      final aTimings = alice3DH.lastCryptoTimings!;
      expect(aTimings.dh1Duration.inMicroseconds, greaterThanOrEqualTo(0));
      expect(aTimings.dh2Duration.inMicroseconds, greaterThanOrEqualTo(0));
      expect(aTimings.dh3Duration.inMicroseconds, greaterThanOrEqualTo(0));
      expect(aTimings.hkdfDuration.inMicroseconds, greaterThanOrEqualTo(0));
      expect(aTimings.totalCryptoMs, greaterThan(0));

      // Verify Bob crypto timings
      expect(bob3DH.lastCryptoTimings, isNotNull);
      final bTimings = bob3DH.lastCryptoTimings!;
      expect(bTimings.dh1Duration.inMicroseconds, greaterThanOrEqualTo(0));
      expect(bTimings.dh2Duration.inMicroseconds, greaterThanOrEqualTo(0));
      expect(bTimings.dh3Duration.inMicroseconds, greaterThanOrEqualTo(0));
      expect(bTimings.hkdfDuration.inMicroseconds, greaterThanOrEqualTo(0));
      expect(bTimings.totalCryptoMs, greaterThan(0));
    });

    test('P2PChatService records 3DH connection logs and updates telemetry', () async {
      SharedPreferences.setMockInitialValues({});
      final chatService = P2PChatService();

      expect(chatService.tripleDhLogs, isEmpty);
      expect(chatService.tripleDhTelemetry, isNull);
      expect(chatService.tripleDhLatencyMs, isNull);

      await chatService.simulate3DhHandshakeForTesting(simulatedLatencyMs: 26.8);

      expect(chatService.tripleDhLogs, isNotEmpty);
      expect(chatService.tripleDhTelemetry, isNotNull);
      expect(chatService.tripleDhLatencyMs, closeTo(26.8, 0.01));

      final t = chatService.tripleDhTelemetry!;
      expect(t.isCompleted, isTrue);
      expect(t.cryptoComputeTimeMs, closeTo(3.45, 0.01));
      expect(t.wireTransitLatencyMs, closeTo(18.2, 0.01));
      expect(t.localEphemeralPubHex, isNotNull);
      expect(t.remoteEphemeralPubHex, isNotNull);

      final stages = chatService.tripleDhLogs.map((l) => l.stage).toList();
      expect(stages, contains('SCTP_OPEN'));
      expect(stages, contains('KEYGEN'));
      expect(stages, contains('TX_HANDSHAKE'));
      expect(stages, contains('RX_HANDSHAKE'));
      expect(stages, contains('DH_COMPUTE'));
      expect(stages, contains('VERIFIED'));
    });

    testWidgets('TripleDhInspectorDialog renders latency cards and terminal logs', (tester) async {
      final now = DateTime.now();
      final telemetry = TripleDhTelemetry(
        startedAt: now.subtract(const Duration(milliseconds: 25)),
        completedAt: now,
        totalHandshakeLatencyMs: 25.4,
        cryptoComputeTimeMs: 3.12,
        wireTransitLatencyMs: 19.5,
        ephemeralGenTimeMs: 0.95,
        dh1TimeMs: 1.05,
        dh2TimeMs: 1.02,
        dh3TimeMs: 1.00,
        hkdfTimeMs: 0.05,
        localEphemeralPubHex: '4a2fe7890b12cd56ef34a1b2c3d4e5f60718293a4b5c6d7e8f901a2b3c4d5e6f',
        remoteEphemeralPubHex: '1b4387d2ef0987654321fedcba0987654321fedcba0987654321fedcba098765',
        localIdentityPubHex: '8f1b2c3d4e5f60718293a4b5c6d7e8f901a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6',
        remoteIdentityPubHex: 'e29ab81c34ef7654321fedcba0987654321fedcba0987654321fedcba0987654',
        isInitiator: true,
        isCompleted: true,
      );

      final logs = [
        TripleDhLogEntry(
          timestamp: now,
          stage: 'SCTP_OPEN',
          message: 'WebRTC SCTP DataChannel opened. Initiating 3DH protocol.',
        ),
        TripleDhLogEntry(
          timestamp: now,
          stage: 'KEYGEN',
          message: 'Generated ephemeral X25519 keypair in 0.95 ms.',
          detail: 'ek_local: 0x4a2fe7890b12...',
          durationMs: 0.95,
        ),
        TripleDhLogEntry(
          timestamp: now,
          stage: 'VERIFIED',
          message: 'Triple-DH handshake verified & mutual presence activated!',
          durationMs: 25.4,
          level: TripleDhLogLevel.success,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TripleDhInspectorDialog(
              telemetry: telemetry,
              logs: logs,
              isSecure: true,
              isInRoom: true,
            ),
          ),
        ),
      );

      expect(find.text('Triple-DH (3DH) Handshake Telemetry'), findsOneWidget);
      expect(find.text('3DH TOTAL LATENCY'), findsOneWidget);
      expect(find.text('25.4 ms'), findsOneWidget);
      expect(find.text('3.12 ms'), findsOneWidget);
      expect(find.text('19.5 ms'), findsOneWidget);
      expect(find.text('Copy Logs'), findsOneWidget);
      expect(find.text('WebRTC SCTP DataChannel opened. Initiating 3DH protocol.'), findsOneWidget);
      expect(find.text('Triple-DH handshake verified & mutual presence activated!'), findsOneWidget);
    });
  });
}
