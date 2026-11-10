import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Represents a disclosed MAC key from an earlier message (OTR repudiation)
class DisclosedMacKey {
  final int seq;
  final String keyHex;

  DisclosedMacKey({required this.seq, required this.keyHex});

  Map<String, dynamic> toJson() => {'seq': seq, 'key': keyHex};

  factory DisclosedMacKey.fromJson(Map<String, dynamic> json) => DisclosedMacKey(
        seq: json['seq'] as int,
        keyHex: json['key'] as String,
      );
}

/// Wire envelope carrying ciphertext, authentication tag, HMAC, and disclosed MAC keys
class DeniablePacket {
  final int seq;
  final String nonceBase64;
  final String ciphertextBase64;
  final String gcmTagBase64;
  final String hmacHex;
  final List<DisclosedMacKey> disclosedMacKeys;
  final int localTimestamp; // Unauthenticated local client timestamp

  DeniablePacket({
    required this.seq,
    required this.nonceBase64,
    required this.ciphertextBase64,
    required this.gcmTagBase64,
    required this.hmacHex,
    required this.disclosedMacKeys,
    required this.localTimestamp,
  });

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'nonce': nonceBase64,
        'ciphertext': ciphertextBase64,
        'tag': gcmTagBase64,
        'hmac': hmacHex,
        'disclosed': disclosedMacKeys.map((k) => k.toJson()).toList(),
        'ts': localTimestamp,
      };

  factory DeniablePacket.fromJson(Map<String, dynamic> json) => DeniablePacket(
        seq: json['seq'] as int,
        nonceBase64: json['nonce'] as String,
        ciphertextBase64: json['ciphertext'] as String,
        gcmTagBase64: json['tag'] as String,
        hmacHex: json['hmac'] as String,
        disclosedMacKeys: (json['disclosed'] as List? ?? [])
            .map((item) => DisclosedMacKey.fromJson(item as Map<String, dynamic>))
            .toList(),
        localTimestamp: json['ts'] as int? ?? 0,
      );

  String toWireJson() => jsonEncode(toJson());

  factory DeniablePacket.fromWireJson(String wire) =>
      DeniablePacket.fromJson(jsonDecode(wire) as Map<String, dynamic>);
}

/// Implements deniable message encryption with OTR-style MAC key publication.
/// Symmetric MAC keys are published after use to allow universal third-party forgery.
class DeniableCipher {
  static final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final AesGcm aesGcm = AesGcm.with256bits();

  final SecretKey sessionKey;
  int _sendSeq = 0;
  final List<DisclosedMacKey> _pendingMacDisclosures = [];

  // Log of all disclosed MAC keys for transparency and writeup/export
  final List<DisclosedMacKey> publishedKeysLog = [];

  DeniableCipher({required this.sessionKey});

  /// Derive unique encryption and MAC keys for sequence number [seq]
  Future<Map<String, SecretKey>> _deriveMessageKeys(int seq) async {
    final encKey = await hkdf.deriveKey(
      secretKey: sessionKey,
      info: utf8.encode('Deniable-ENC:seq:$seq'),
    );
    final macKey = await hkdf.deriveKey(
      secretKey: sessionKey,
      info: utf8.encode('Deniable-MAC:seq:$seq'),
    );
    return {'enc': encKey, 'mac': macKey};
  }

  /// Encrypt a new message and publish any pending MAC keys from previous messages
  Future<DeniablePacket> encryptMessage(String plaintext) async {
    _sendSeq++;
    final currentSeq = _sendSeq;

    final keys = await _deriveMessageKeys(currentSeq);
    final encKey = keys['enc']!;
    final macKey = keys['mac']!;

    // Encrypt with AES-GCM
    final plaintextBytes = utf8.encode(plaintext);
    final secretBox = await aesGcm.encrypt(plaintextBytes, secretKey: encKey);

    // Compute outer symmetric HMAC-SHA256 over nonce + ciphertext + GCM tag
    final hmac = Hmac.sha256();
    final authenticatedData = [
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ];
    final macSignature = await hmac.calculateMac(
      authenticatedData,
      secretKey: macKey,
    );

    // Attach pending disclosed MAC keys from earlier messages
    final disclosuresToSend = List<DisclosedMacKey>.from(_pendingMacDisclosures);
    publishedKeysLog.addAll(disclosuresToSend);
    _pendingMacDisclosures.clear();

    // Queue current message's MAC key to be revealed in the NEXT packet
    final macBytes = await macKey.extractBytes();
    _pendingMacDisclosures.add(
      DisclosedMacKey(
        seq: currentSeq,
        keyHex: _bytesToHex(macBytes),
      ),
    );

    return DeniablePacket(
      seq: currentSeq,
      nonceBase64: base64Encode(secretBox.nonce),
      ciphertextBase64: base64Encode(secretBox.cipherText),
      gcmTagBase64: base64Encode(secretBox.mac.bytes),
      hmacHex: _bytesToHex(macSignature.bytes),
      disclosedMacKeys: disclosuresToSend,
      localTimestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Decrypt incoming packet, verify symmetric HMAC, and record disclosed MAC keys
  Future<String> decryptMessage(DeniablePacket packet) async {
    // Record peer's disclosed MAC keys
    publishedKeysLog.addAll(packet.disclosedMacKeys);

    final keys = await _deriveMessageKeys(packet.seq);
    final encKey = keys['enc']!;
    final macKey = keys['mac']!;

    final nonce = base64Decode(packet.nonceBase64);
    final ciphertext = base64Decode(packet.ciphertextBase64);
    final gcmTag = base64Decode(packet.gcmTagBase64);

    // 1. Verify Outer HMAC
    final hmac = Hmac.sha256();
    final authenticatedData = [...nonce, ...ciphertext, ...gcmTag];
    final expectedMac = await hmac.calculateMac(
      authenticatedData,
      secretKey: macKey,
    );

    if (_bytesToHex(expectedMac.bytes) != packet.hmacHex) {
      throw const FormatException('HMAC verification failed: packet has been altered!');
    }

    // 2. Decrypt AES-GCM
    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(gcmTag),
    );
    final decryptedBytes = await aesGcm.decrypt(secretBox, secretKey: encKey);
    return utf8.decode(decryptedBytes);
  }

  /// Release any un-disclosed MAC keys (e.g. at end of session)
  List<DisclosedMacKey> flushPendingDisclosures() {
    final list = List<DisclosedMacKey>.from(_pendingMacDisclosures);
    publishedKeysLog.addAll(list);
    _pendingMacDisclosures.clear();
    return list;
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
