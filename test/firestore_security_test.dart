import 'package:flutter_test/flutter_test.dart';
import 'package:bored_p2p_chat/services/firestore_security.dart';

void main() {
  group('Firestore Anti-Bot Proof of Work Tests', () {
    test('AntiBotProofOfWork solves and verifies a 12-bit challenge', () async {
      const testChallenge = 'bored_test_address_1234';
      final pow = await AntiBotProofOfWork.solve(challengeId: testChallenge, difficultyBits: 12);

      expect(pow.nonce, isNonNegative);
      expect(pow.hashHex.startsWith('000'), isTrue);

      final isValid = AntiBotProofOfWork.verify(
        challengeId: testChallenge,
        nonce: pow.nonce,
        timestamp: pow.timestamp,
        hashHex: pow.hashHex,
        difficultyBits: 12,
      );
      expect(isValid, isTrue);
    });

    test('AntiBotProofOfWork rejects tampered nonce or expired challenge', () async {
      const testChallenge = 'bored_tampered';
      final pow = await AntiBotProofOfWork.solve(challengeId: testChallenge, difficultyBits: 8);

      // Tampered nonce
      final isTamperedValid = AntiBotProofOfWork.verify(
        challengeId: testChallenge,
        nonce: pow.nonce + 1,
        timestamp: pow.timestamp,
        hashHex: pow.hashHex,
        difficultyBits: 8,
      );
      expect(isTamperedValid, isFalse);

      // Expired timestamp (older than 300 seconds)
      final isExpiredValid = AntiBotProofOfWork.verify(
        challengeId: testChallenge,
        nonce: pow.nonce,
        timestamp: pow.timestamp - 400000,
        hashHex: pow.hashHex,
        difficultyBits: 8,
      );
      expect(isExpiredValid, isFalse);
    });
  });

  group('Firestore Rate Limiter Tests', () {
    setUp(() {
      FirestoreRateLimiter().reset();
    });

    test('Allows operations within token bucket capacity', () {
      final limiter = FirestoreRateLimiter();
      expect(() => limiter.enforce('call_address'), returnsNormally);
      expect(() => limiter.enforce('call_address'), returnsNormally);
      expect(() => limiter.enforce('call_address'), returnsNormally);
    });

    test('Throws RateLimitException when capacity exhausted', () {
      final limiter = FirestoreRateLimiter();
      // 'call_address' has capacity of 3
      limiter.enforce('call_address');
      limiter.enforce('call_address');
      limiter.enforce('call_address');

      expect(
        () => limiter.enforce('call_address'),
        throwsA(isA<RateLimitException>()),
      );
    });
  });

  group('Firestore Payload Validator Tests', () {
    test('Validates compliant IDs', () {
      expect(() => FirestorePayloadValidator.validateId('bored_8f3a-9e1c-b4d2-e7a1'), returnsNormally);
      expect(() => FirestorePayloadValidator.validateId('node:4b7e'), returnsNormally);
    });

    test('Rejects invalid IDs with illegal chars or bad lengths', () {
      expect(() => FirestorePayloadValidator.validateId('short'), throwsArgumentError);
      expect(() => FirestorePayloadValidator.validateId('invalid space id 123'), throwsArgumentError);
      expect(() => FirestorePayloadValidator.validateId('malicious<script>'), throwsArgumentError);
    });

    test('Validates SDP size limits', () {
      expect(() => FirestorePayloadValidator.validateSdp('v=0\r\no=alice 123 456...'), returnsNormally);
      final oversized = 'a' * 20000;
      expect(() => FirestorePayloadValidator.validateSdp(oversized), throwsArgumentError);
    });
  });
}
