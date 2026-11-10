import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bored_p2p_chat/crypto/diffie_hellman.dart';
import 'package:bored_p2p_chat/crypto/cipher.dart';

void main() {
  group('Diffie-Hellman RFC 3526 2048-bit Key Exchange Tests', () {
    test('Alice and Bob compute identical shared secret and AES key', () {
      // 1. Alice generates keypair
      final alice = DiffieHellman.generate();
      expect(alice.privateKey > BigInt.zero, isTrue);
      expect(alice.publicKey > BigInt.zero, isTrue);

      // 2. Bob generates keypair
      final bob = DiffieHellman.generate();
      expect(bob.privateKey > BigInt.zero, isTrue);
      expect(bob.publicKey > BigInt.zero, isTrue);

      // Verify public keys are different
      expect(alice.publicKey, isNot(equals(bob.publicKey)));

      // 3. Key handoff: Alice computes secret with Bob's public key
      final Uint8List aliceKey = alice.computeSharedSecret(bob.publicKey);

      // 4. Bob computes secret with Alice's public key
      final Uint8List bobKey = bob.computeSharedSecret(alice.publicKey);

      // 5. Verify the mathematical shared secrets are identical: S = (g^b)^a = (g^a)^b mod p
      expect(alice.sharedSecret, equals(bob.sharedSecret));

      // 6. Verify derived AES-256 keys are identical
      expect(aliceKey, equals(bobKey));
      expect(aliceKey.length, equals(32)); // 256 bits

      // 7. Verify human-verifiable safety numbers match
      expect(alice.safetyNumber, equals(bob.safetyNumber));
      expect(alice.safetyNumber, isNotNull);
      // Safety number format should be "xxxxx - xxxxx - xxxxx - xxxxx"
      expect(alice.safetyNumber!.split(' - ').length, equals(4));
    });

    test('Invalid public key is rejected (p - 1 or <= 1)', () {
      final alice = DiffieHellman.generate();
      expect(() => alice.computeSharedSecret(BigInt.zero), throwsArgumentError);
      expect(() => alice.computeSharedSecret(BigInt.one), throwsArgumentError);
      expect(() => alice.computeSharedSecret(DiffieHellman.prime), throwsArgumentError);
    });

    test('Public key serialization and deserialization in hex', () {
      final alice = DiffieHellman.generate();
      final hex = alice.publicKeyHex;
      final restored = DiffieHellman.parsePublicKey(hex);
      expect(restored, equals(alice.publicKey));
    });
  });

  group('Authenticated Message Encryption Tests (AES-256 + HMAC-SHA256)', () {
    test('Encrypt and decrypt roundtrip matches plaintext', () {
      final alice = DiffieHellman.generate();
      final bob = DiffieHellman.generate();

      final aliceSharedKey = alice.computeSharedSecret(bob.publicKey);
      final bobSharedKey = bob.computeSharedSecret(alice.publicKey);

      final aliceCipher = MessageCipher(aliceSharedKey);
      final bobCipher = MessageCipher(bobSharedKey);

      const plaintext = 'Super secret message sent across P2P WebRTC data channel!';
      final EncryptedPacket packet = aliceCipher.encrypt(plaintext);

      // Verify packet structure
      expect(packet.ivBase64.isNotEmpty, isTrue);
      expect(packet.ciphertextBase64.isNotEmpty, isTrue);
      expect(packet.hmacHex.isNotEmpty, isTrue);

      // Bob decrypts
      final decrypted = bobCipher.decrypt(packet);
      expect(decrypted, equals(plaintext));
    });

    test('Tampered ciphertext is rejected by HMAC authentication', () {
      final alice = DiffieHellman.generate();
      final bob = DiffieHellman.generate();

      alice.computeSharedSecret(bob.publicKey);
      final bobKey = bob.computeSharedSecret(alice.publicKey);

      final aliceCipher = MessageCipher(alice.derivedAesKey!);
      final bobCipher = MessageCipher(bobKey);

      final packet = aliceCipher.encrypt('Original message');

      // Tamper with the ciphertext by flipping one byte
      final tamperedBytes = List<int>.from(packet.ciphertextBase64.codeUnits);
      tamperedBytes[0] = tamperedBytes[0] == 65 ? 66 : 65;
      final tamperedPacket = EncryptedPacket(
        ivBase64: packet.ivBase64,
        ciphertextBase64: String.fromCharCodes(tamperedBytes),
        hmacHex: packet.hmacHex,
        timestamp: packet.timestamp,
      );

      expect(() => bobCipher.decrypt(tamperedPacket), throwsFormatException);
    });
  });
}
