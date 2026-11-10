import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Wrapped ciphertext container for storing sensitive keys at rest
class EncryptedBlob {
  final String nonceBase64;
  final String ciphertextBase64;
  final String macBase64;

  EncryptedBlob({
    required this.nonceBase64,
    required this.ciphertextBase64,
    required this.macBase64,
  });

  Map<String, dynamic> toJson() => {
        'nonce': nonceBase64,
        'ciphertext': ciphertextBase64,
        'mac': macBase64,
      };

  factory EncryptedBlob.fromJson(Map<String, dynamic> json) => EncryptedBlob(
        nonceBase64: json['nonce'] as String,
        ciphertextBase64: json['ciphertext'] as String,
        macBase64: json['mac'] as String,
      );
}

/// Enforces 2-of-2 secret sharing for active presence and
/// Argon2id wrapping for data at rest.
class SplitVault {
  static final Argon2id argon2id = Argon2id(
    memory: 64 * 1024, // 64 MB
    iterations: 2,
    parallelism: 1,
    hashLength: 32,
  );
  static final AesGcm aesGcm = AesGcm.with256bits();

  Uint8List? _localShare;
  Uint8List? _remoteShare;
  Uint8List? _reconstructedK; // K = s1 XOR s2
  SimpleKeyPair? _identityKeyPair;

  Uint8List? get localShare => _localShare;
  Uint8List? get reconstructedK => _reconstructedK;
  SimpleKeyPair? get identityKeyPair => _identityKeyPair;
  bool get isPresenceActive => _reconstructedK != null;

  /// Derive a 256-bit vault encryption key from passphrase and salt
  static Future<SecretKey> deriveVaultKey(String passphrase, List<int> salt) async {
    return await argon2id.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
  }

  /// Generate a random 16-byte salt for Argon2id
  static Uint8List generateSalt() {
    final rand = Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => rand.nextInt(256)));
  }

  /// Generate a random 32-byte secret share
  static Uint8List generateRandomShare() {
    final rand = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => rand.nextInt(256)));
  }

  /// Create a fresh 2-of-2 split: produces (s1, s2) such that s1 XOR s2 = K
  static Map<String, Uint8List> createSharePair() {
    final masterK = generateRandomShare();
    final s1 = generateRandomShare();
    final s2 = xorShares(masterK, s1);
    return {'k': masterK, 's1': s1, 's2': s2};
  }

  /// Mathematical 2-of-2 XOR operation: K = s1 XOR s2
  static Uint8List xorShares(Uint8List a, Uint8List b) {
    if (a.length != 32 || b.length != 32) {
      throw ArgumentError('Shares must be exactly 32 bytes');
    }
    final result = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      result[i] = a[i] ^ b[i];
    }
    return result;
  }

  /// Wrap private bytes (identity key or share) under the Argon2id vault key
  static Future<EncryptedBlob> wrapSecret(SecretKey vaultKey, List<int> secretBytes) async {
    final secretBox = await aesGcm.encrypt(secretBytes, secretKey: vaultKey);
    return EncryptedBlob(
      nonceBase64: base64Encode(secretBox.nonce),
      ciphertextBase64: base64Encode(secretBox.cipherText),
      macBase64: base64Encode(secretBox.mac.bytes),
    );
  }

  /// Unwrap private bytes under the Argon2id vault key
  static Future<Uint8List> unwrapSecret(SecretKey vaultKey, EncryptedBlob blob) async {
    final secretBox = SecretBox(
      base64Decode(blob.ciphertextBase64),
      nonce: base64Decode(blob.nonceBase64),
      mac: Mac(base64Decode(blob.macBase64)),
    );
    final decrypted = await aesGcm.decrypt(secretBox, secretKey: vaultKey);
    return Uint8List.fromList(decrypted);
  }

  /// Set the unlocked local credentials into memory
  void unlockLocalVault({
    required SimpleKeyPair identityKeyPair,
    required Uint8List localShare,
  }) {
    _identityKeyPair = identityKeyPair;
    _localShare = localShare;
  }

  /// Reconstruct K = s1 XOR s2 when peer supplies their share over 3DH
  void activatePresence(Uint8List remoteShare) {
    if (_localShare == null) {
      throw StateError('Cannot reconstruct K: local share is not unlocked');
    }
    _remoteShare = remoteShare;
    _reconstructedK = xorShares(_localShare!, _remoteShare!);
  }

  /// Encrypt a history message using the active reconstructed K
  Future<EncryptedBlob> encryptHistoryMessage(String messageText) async {
    if (_reconstructedK == null) {
      throw StateError('Cannot encrypt history: Peer is not present (K is not reconstructed)');
    }
    final key = SecretKey(_reconstructedK!);
    final bytes = utf8.encode(messageText);
    final box = await aesGcm.encrypt(bytes, secretKey: key);
    return EncryptedBlob(
      nonceBase64: base64Encode(box.nonce),
      ciphertextBase64: base64Encode(box.cipherText),
      macBase64: base64Encode(box.mac.bytes),
    );
  }

  /// Decrypt a history message using the active reconstructed K
  Future<String> decryptHistoryMessage(EncryptedBlob blob) async {
    if (_reconstructedK == null) {
      throw StateError('Cannot decrypt history: Peer is not present (K is not reconstructed)');
    }
    final key = SecretKey(_reconstructedK!);
    final box = SecretBox(
      base64Decode(blob.ciphertextBase64),
      nonce: base64Decode(blob.nonceBase64),
      mac: Mac(base64Decode(blob.macBase64)),
    );
    final bytes = await aesGcm.decrypt(box, secretKey: key);
    return utf8.decode(bytes);
  }

  /// Explicitly wipe all active keys and the reconstructed K from RAM
  void zeroizeSession() {
    if (_reconstructedK != null) {
      _reconstructedK!.fillRange(0, _reconstructedK!.length, 0);
      _reconstructedK = null;
    }
    if (_remoteShare != null) {
      _remoteShare!.fillRange(0, _remoteShare!.length, 0);
      _remoteShare = null;
    }
  }

  /// Complete logout wipe
  void zeroizeAll() {
    zeroizeSession();
    if (_localShare != null) {
      _localShare!.fillRange(0, _localShare!.length, 0);
      _localShare = null;
    }
    _identityKeyPair = null;
  }
}
