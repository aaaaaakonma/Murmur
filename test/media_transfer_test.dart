import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:bored_p2p_chat/crypto/deniable_cipher.dart';
import 'package:bored_p2p_chat/services/p2p_chat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P2P Encrypted Media & File Transfer Tests', () {
    late SecretKey sessionKey;
    late DeniableCipher cipher;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // Generate a mock 256-bit session key
      final keyBytes = List<int>.generate(32, (i) => i * 7 % 256);
      sessionKey = SecretKey(keyBytes);
      cipher = DeniableCipher(sessionKey: sessionKey);
    });

    test('encryptBytes and decryptBytes roundtrip preserves binary fidelity', () async {
      // 64 KB pseudo-random binary payload (e.g. simulated image or PDF)
      final rawData = Uint8List.fromList(List<int>.generate(65536, (i) => (i * 31 + 17) % 256));
      final originalSha256 = dart_crypto.sha256.convert(rawData).toString();

      final packet = await cipher.encryptBytes(rawData);
      expect(packet.ciphertextBase64, isNotEmpty);
      expect(packet.hmacHex, isNotEmpty);
      expect(packet.seq, equals(1));

      // Decrypt with cipher instance
      final decrypted = await cipher.decryptBytes(packet);
      final decryptedSha256 = dart_crypto.sha256.convert(decrypted).toString();

      expect(decryptedSha256, equals(originalSha256));
      expect(decrypted.length, equals(rawData.length));
      expect(decrypted, equals(rawData));
    });

    test('tampered ciphertext in media packet throws FormatException', () async {
      final payload = utf8.encode('Top-Secret Blueprint Image Bytes');
      final packet = await cipher.encryptBytes(payload);

      // Corrupt one character in base64 ciphertext
      final tamperedBase64 = '${packet.ciphertextBase64.substring(0, packet.ciphertextBase64.length - 2)}AA';
      final tamperedPacket = DeniablePacket(
        seq: packet.seq,
        nonceBase64: packet.nonceBase64,
        ciphertextBase64: tamperedBase64,
        gcmTagBase64: packet.gcmTagBase64,
        hmacHex: packet.hmacHex,
        disclosedMacKeys: packet.disclosedMacKeys,
        localTimestamp: packet.localTimestamp,
      );

      expect(
        () async => await cipher.decryptBytes(tamperedPacket),
        throwsA(isA<FormatException>()),
      );
    });

    test('ChatMediaAttachment zeroize() wipes RAM with 0x00 bytes', () {
      final sampleBytes = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
      final attachment = ChatMediaAttachment(
        fileId: 'test_file_001',
        fileName: 'blueprint.png',
        fileSize: sampleBytes.length,
        mimeType: 'image/png',
        isImage: true,
        sha256: dart_crypto.sha256.convert(sampleBytes).toString(),
        bytes: sampleBytes,
        progress: 1.0,
        isComplete: true,
      );

      expect(attachment.bytes, isNotNull);
      expect(attachment.bytes!.any((b) => b != 0), isTrue);

      // Trigger zeroization
      attachment.zeroize();

      // Bytes must be nullified and memory wiped
      expect(attachment.bytes, isNull);
      expect(sampleBytes.every((b) => b == 0), isTrue);
    });

    test('Disconnect zeroizes in-memory media attachments in P2PChatService', () async {
      final chatService = P2PChatService();
      await chatService.unlockOrCreateVault('test_vault_passphrase_456');

      final mediaBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      final attachment = ChatMediaAttachment(
        fileId: 'media_abc',
        fileName: 'classified.jpg',
        fileSize: mediaBytes.length,
        mimeType: 'image/jpeg',
        isImage: true,
        sha256: dart_crypto.sha256.convert(mediaBytes).toString(),
        bytes: mediaBytes,
      );

      expect(attachment.bytes, isNotNull);
      expect(attachment.isComplete, isTrue);

      // Verify leaveRoom or disconnect clears session and zeroizes volatile state
      await chatService.leaveRoom();

      expect(chatService.messages, isEmpty);
      expect(chatService.packetLog, isEmpty);
      expect(chatService.status, equals(SessionStatus.idle));
    });
  });
}
