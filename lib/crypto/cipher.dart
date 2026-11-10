import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Represents an encrypted wire packet transmitted over WebRTC DataChannel
class EncryptedPacket {
  final String ivBase64;
  final String ciphertextBase64;
  final String hmacHex;
  final int timestamp;

  EncryptedPacket({
    required this.ivBase64,
    required this.ciphertextBase64,
    required this.hmacHex,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'iv': ivBase64,
        'ciphertext': ciphertextBase64,
        'hmac': hmacHex,
        'timestamp': timestamp,
      };

  factory EncryptedPacket.fromJson(Map<String, dynamic> json) => EncryptedPacket(
        ivBase64: json['iv'] as String,
        ciphertextBase64: json['ciphertext'] as String,
        hmacHex: json['hmac'] as String,
        timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );

  String toWireJson() => jsonEncode(toJson());

  factory EncryptedPacket.fromWireJson(String wire) =>
      EncryptedPacket.fromJson(jsonDecode(wire) as Map<String, dynamic>);
}

/// Provides authenticated AES-256-CBC encryption using the key derived
/// from the Diffie-Hellman handshake, with Encrypt-then-MAC (HMAC-SHA256).
class MessageCipher {
  final Uint8List _keyBytes;
  late final enc.Key _encKey;
  late final Hmac _hmac;

  MessageCipher(Uint8List keyBytes) : _keyBytes = keyBytes {
    if (keyBytes.length != 32) {
      throw ArgumentError('Key must be exactly 32 bytes (256 bits)');
    }
    _encKey = enc.Key(_keyBytes);
    _hmac = Hmac(sha256, _keyBytes);
  }

  /// Encrypts plaintext string into an authenticated EncryptedPacket
  EncryptedPacket encrypt(String plaintext) {
    // Generate 16 cryptographically secure random bytes for IV
    final Random random = Random.secure();
    final Uint8List ivBytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      ivBytes[i] = random.nextInt(256);
    }
    final enc.IV iv = enc.IV(ivBytes);

    // AES-CBC encryption with PKCS7 padding
    final enc.Encrypter encrypter = enc.Encrypter(enc.AES(_encKey, mode: enc.AESMode.cbc));
    final enc.Encrypted encrypted = encrypter.encrypt(plaintext, iv: iv);

    // Encrypt-then-MAC: HMAC over (IV + Ciphertext)
    final List<int> authenticatedData = [...iv.bytes, ...encrypted.bytes];
    final Digest macDigest = _hmac.convert(authenticatedData);

    return EncryptedPacket(
      ivBase64: iv.base64,
      ciphertextBase64: encrypted.base64,
      hmacHex: macDigest.toString(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Verifies HMAC and decrypts the packet back into plaintext
  String decrypt(EncryptedPacket packet) {
    final enc.IV iv = enc.IV.fromBase64(packet.ivBase64);
    final enc.Encrypted encrypted = enc.Encrypted.fromBase64(packet.ciphertextBase64);

    // Verify MAC
    final List<int> authenticatedData = [...iv.bytes, ...encrypted.bytes];
    final Digest expectedMac = _hmac.convert(authenticatedData);

    if (expectedMac.toString() != packet.hmacHex) {
      throw const FormatException('MAC verification failed: message has been tampered with or corrupted!');
    }

    final enc.Encrypter encrypter = enc.Encrypter(enc.AES(_encKey, mode: enc.AESMode.cbc));
    return encrypter.decrypt(encrypted, iv: iv);
  }
}
