import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Implements Diffie-Hellman Key Exchange using RFC 3526 2048-bit MODP Group 14
/// with pure Dart [BigInt.modPow], requiring no external native C++ crypto libraries.
class DiffieHellman {
  /// RFC 3526 Group 14: 2048-bit MODP Prime p
  static final BigInt prime = BigInt.parse(
    'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1'
    '29024E088A67CC74020BBEA63B139B22514A08798E3404DD'
    'EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245'
    'E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED'
    'EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D'
    'C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F'
    '83655D23DCA3AD961C62F356208552BB9ED529077096966D'
    '670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B'
    'E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9'
    'DE2BCBF6955817183995497CEA956AE515D2261898FA0510'
    '15728E5A8AACAA68FFFFFFFFFFFFFFFF',
    radix: 16,
  );

  /// Generator g = 2
  static final BigInt generator = BigInt.from(2);

  final BigInt privateKey;
  final BigInt publicKey;
  BigInt? _sharedSecret;
  Uint8List? _derivedAesKey;
  String? _safetyNumber;

  DiffieHellman._({
    required this.privateKey,
    required this.publicKey,
  });

  /// Factory to generate a new key pair using cryptographically secure random bytes
  factory DiffieHellman.generate() {
    final Random random = Random.secure();
    // 256 bits of private entropy is standard and secure for 2048-bit MODP (RFC 3526 Section 3)
    final Uint8List randomBytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      randomBytes[i] = random.nextInt(256);
    }
    // Ensure the most significant bit is set so it's a full 256-bit number
    randomBytes[0] |= 0x80;

    final BigInt privateKey = _bytesToBigInt(randomBytes);
    // Calculate public key: A = g^a mod p
    final BigInt publicKey = generator.modPow(privateKey, prime);

    return DiffieHellman._(
      privateKey: privateKey,
      publicKey: publicKey,
    );
  }

  /// Calculates the shared secret S = (peerPublicKey ^ privateKey) mod p
  /// and derives the 256-bit symmetric encryption key using SHA-256
  Uint8List computeSharedSecret(BigInt peerPublicKey) {
    if (peerPublicKey <= BigInt.one || peerPublicKey >= prime - BigInt.one) {
      throw ArgumentError('Invalid peer public key: outside valid range (1, p-1)');
    }

    // S = B^a mod p
    final BigInt secret = peerPublicKey.modPow(privateKey, prime);
    _sharedSecret = secret;

    // Convert secret to bytes (big-endian)
    final Uint8List secretBytes = _bigIntToBytes(secret);

    // Derive 256-bit key via SHA-256
    final Digest hash = sha256.convert(secretBytes);
    _derivedAesKey = Uint8List.fromList(hash.bytes);

    // Generate human-verifiable safety number (fingerprint)
    _safetyNumber = _computeSafetyNumber(publicKey, peerPublicKey);

    return _derivedAesKey!;
  }

  Uint8List? get derivedAesKey => _derivedAesKey;
  BigInt? get sharedSecret => _sharedSecret;
  String? get safetyNumber => _safetyNumber;

  /// Hex representation of public key for transmission over WebRTC
  String get publicKeyHex => publicKey.toRadixString(16);

  /// Parse a received hex string to BigInt
  static BigInt parsePublicKey(String hex) {
    return BigInt.parse(hex, radix: 16);
  }

  /// Calculates a deterministic safety number between two peers
  /// Min(A, B) + Max(A, B) hashed with SHA-256, formatted as 6-digit chunks
  static String _computeSafetyNumber(BigInt a, BigInt b) {
    final BigInt first = a < b ? a : b;
    final BigInt second = a < b ? b : a;

    final List<int> combined = [
      ..._bigIntToBytes(first),
      ..._bigIntToBytes(second),
    ];

    final Digest digest = sha256.convert(combined);
    final String hex = digest.toString();

    // Take parts of the hash to create groups of 5 digits (like Signal/WhatsApp)
    final List<String> chunks = [];
    for (int i = 0; i < 4; i++) {
      final int val = int.parse(hex.substring(i * 8, (i + 1) * 8), radix: 16) % 100000;
      chunks.add(val.toString().padLeft(5, '0'));
    }
    return chunks.join(' - ');
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  static Uint8List _bigIntToBytes(BigInt number) {
    int byteLength = (number.bitLength + 7) >> 3;
    if (byteLength == 0) byteLength = 1;
    final Uint8List bytes = Uint8List(byteLength);
    BigInt temp = number;
    for (int i = byteLength - 1; i >= 0; i--) {
      bytes[i] = (temp & BigInt.from(0xff)).toInt();
      temp = temp >> 8;
    }
    return bytes;
  }
}
