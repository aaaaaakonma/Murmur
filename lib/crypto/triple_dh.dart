import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

enum TripleDhLogLevel {
  info,
  crypto,
  success,
  warning,
  error,
}

/// An immutable event entry from the 3DH connection and handshake sequence.
class TripleDhLogEntry {
  final DateTime timestamp;
  final String stage;
  final String message;
  final String? detail;
  final double? durationMs;
  final TripleDhLogLevel level;

  TripleDhLogEntry({
    required this.timestamp,
    required this.stage,
    required this.message,
    this.detail,
    this.durationMs,
    this.level = TripleDhLogLevel.info,
  });

  String get formattedTimestamp {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  String toString() => '[$formattedTimestamp][$stage] $message${detail != null ? ' ($detail)' : ''}';
}

/// Measured hardware execution times for all 3DH cryptographic primitives.
class TripleDhCryptoTimings {
  final Duration ephemeralGenDuration;
  final Duration dh1Duration;
  final Duration dh2Duration;
  final Duration dh3Duration;
  final Duration hkdfDuration;
  final Duration totalCryptoDuration;

  const TripleDhCryptoTimings({
    this.ephemeralGenDuration = Duration.zero,
    this.dh1Duration = Duration.zero,
    this.dh2Duration = Duration.zero,
    this.dh3Duration = Duration.zero,
    this.hkdfDuration = Duration.zero,
    this.totalCryptoDuration = Duration.zero,
  });

  double get ephemeralGenMs => ephemeralGenDuration.inMicroseconds / 1000.0;
  double get dh1Ms => dh1Duration.inMicroseconds / 1000.0;
  double get dh2Ms => dh2Duration.inMicroseconds / 1000.0;
  double get dh3Ms => dh3Duration.inMicroseconds / 1000.0;
  double get hkdfMs => hkdfDuration.inMicroseconds / 1000.0;
  double get totalCryptoMs => totalCryptoDuration.inMicroseconds / 1000.0;
}

/// Comprehensive telemetry data for the Triple-DH handshake on connection.
class TripleDhTelemetry {
  final DateTime? startedAt;
  final DateTime? completedAt;
  final double totalHandshakeLatencyMs;
  final double cryptoComputeTimeMs;
  final double? wireTransitLatencyMs;
  final double ephemeralGenTimeMs;
  final double dh1TimeMs;
  final double dh2TimeMs;
  final double dh3TimeMs;
  final double hkdfTimeMs;
  final String? localEphemeralPubHex;
  final String? remoteEphemeralPubHex;
  final String? localIdentityPubHex;
  final String? remoteIdentityPubHex;
  final bool isInitiator;
  final bool isCompleted;

  const TripleDhTelemetry({
    this.startedAt,
    this.completedAt,
    this.totalHandshakeLatencyMs = 0.0,
    this.cryptoComputeTimeMs = 0.0,
    this.wireTransitLatencyMs,
    this.ephemeralGenTimeMs = 0.0,
    this.dh1TimeMs = 0.0,
    this.dh2TimeMs = 0.0,
    this.dh3TimeMs = 0.0,
    this.hkdfTimeMs = 0.0,
    this.localEphemeralPubHex,
    this.remoteEphemeralPubHex,
    this.localIdentityPubHex,
    this.remoteIdentityPubHex,
    this.isInitiator = false,
    this.isCompleted = false,
  });
}

/// Triple-DH (3DH) handshake manager providing mutual authentication
/// and cryptographic deniability without long-term digital signatures.
class TripleDH {
  static final X25519 x25519 = X25519();
  static final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  final SimpleKeyPair identityKeyPair;
  SimpleKeyPair? _ephemeralKeyPair;

  Duration? lastEphemeralGenDuration;
  TripleDhCryptoTimings? lastCryptoTimings;

  TripleDH({required this.identityKeyPair});

  /// Generate a fresh ephemeral keypair for this session
  Future<SimplePublicKey> generateEphemeralKey() async {
    final sw = Stopwatch()..start();
    _ephemeralKeyPair = await x25519.newKeyPair();
    final pub = await _ephemeralKeyPair!.extractPublicKey();
    sw.stop();
    lastEphemeralGenDuration = sw.elapsed;
    return pub;
  }

  SimpleKeyPair? get ephemeralKeyPair => _ephemeralKeyPair;

  /// Alice (Initiator) handshake computation:
  /// DH1 = DH(ik_A, EK_B)
  /// DH2 = DH(ek_A, IK_B)
  /// DH3 = DH(ek_A, EK_B)
  Future<SecretKey> computeInitiatorSessionKey({
    required SimplePublicKey remoteIdentityKey,
    required SimplePublicKey remoteEphemeralKey,
  }) async {
    if (_ephemeralKeyPair == null) {
      throw StateError('Ephemeral keypair has not been generated');
    }

    final totalSw = Stopwatch()..start();

    final sw1 = Stopwatch()..start();
    final dh1 = await x25519.sharedSecretKey(
      keyPair: identityKeyPair,
      remotePublicKey: remoteEphemeralKey,
    );
    sw1.stop();

    final sw2 = Stopwatch()..start();
    final dh2 = await x25519.sharedSecretKey(
      keyPair: _ephemeralKeyPair!,
      remotePublicKey: remoteIdentityKey,
    );
    sw2.stop();

    final sw3 = Stopwatch()..start();
    final dh3 = await x25519.sharedSecretKey(
      keyPair: _ephemeralKeyPair!,
      remotePublicKey: remoteEphemeralKey,
    );
    sw3.stop();

    final myIdentityPub = await identityKeyPair.extractPublicKey();
    final myEphemeralPub = await _ephemeralKeyPair!.extractPublicKey();

    final swHkdf = Stopwatch()..start();
    final masterKey = await _deriveMasterKey(
      dh1: dh1,
      dh2: dh2,
      dh3: dh3,
      initiatorIK: myIdentityPub,
      initiatorEK: myEphemeralPub,
      responderIK: remoteIdentityKey,
      responderEK: remoteEphemeralKey,
    );
    swHkdf.stop();
    totalSw.stop();

    lastCryptoTimings = TripleDhCryptoTimings(
      ephemeralGenDuration: lastEphemeralGenDuration ?? Duration.zero,
      dh1Duration: sw1.elapsed,
      dh2Duration: sw2.elapsed,
      dh3Duration: sw3.elapsed,
      hkdfDuration: swHkdf.elapsed,
      totalCryptoDuration: totalSw.elapsed + (lastEphemeralGenDuration ?? Duration.zero),
    );

    return masterKey;
  }

  /// Bob (Responder) handshake computation:
  /// DH1 = DH(ek_B, IK_A)  [matches Alice DH1]
  /// DH2 = DH(ik_B, EK_A)  [matches Alice DH2]
  /// DH3 = DH(ek_B, EK_A)  [matches Alice DH3]
  Future<SecretKey> computeResponderSessionKey({
    required SimplePublicKey remoteIdentityKey,
    required SimplePublicKey remoteEphemeralKey,
  }) async {
    if (_ephemeralKeyPair == null) {
      throw StateError('Ephemeral keypair has not been generated');
    }

    final totalSw = Stopwatch()..start();

    // Notice: Bob uses his ephemeral against Alice's identity (matches DH1)
    final sw1 = Stopwatch()..start();
    final dh1 = await x25519.sharedSecretKey(
      keyPair: _ephemeralKeyPair!,
      remotePublicKey: remoteIdentityKey,
    );
    sw1.stop();

    // Notice: Bob uses his identity against Alice's ephemeral (matches DH2)
    final sw2 = Stopwatch()..start();
    final dh2 = await x25519.sharedSecretKey(
      keyPair: identityKeyPair,
      remotePublicKey: remoteEphemeralKey,
    );
    sw2.stop();

    final sw3 = Stopwatch()..start();
    final dh3 = await x25519.sharedSecretKey(
      keyPair: _ephemeralKeyPair!,
      remotePublicKey: remoteEphemeralKey,
    );
    sw3.stop();

    final myIdentityPub = await identityKeyPair.extractPublicKey();
    final myEphemeralPub = await _ephemeralKeyPair!.extractPublicKey();

    final swHkdf = Stopwatch()..start();
    final masterKey = await _deriveMasterKey(
      dh1: dh1,
      dh2: dh2,
      dh3: dh3,
      initiatorIK: remoteIdentityKey,
      initiatorEK: remoteEphemeralKey,
      responderIK: myIdentityPub,
      responderEK: myEphemeralPub,
    );
    swHkdf.stop();
    totalSw.stop();

    lastCryptoTimings = TripleDhCryptoTimings(
      ephemeralGenDuration: lastEphemeralGenDuration ?? Duration.zero,
      dh1Duration: sw1.elapsed,
      dh2Duration: sw2.elapsed,
      dh3Duration: sw3.elapsed,
      hkdfDuration: swHkdf.elapsed,
      totalCryptoDuration: totalSw.elapsed + (lastEphemeralGenDuration ?? Duration.zero),
    );

    return masterKey;
  }

  /// Combine DH outputs and bind with transcript
  Future<SecretKey> _deriveMasterKey({
    required SecretKey dh1,
    required SecretKey dh2,
    required SecretKey dh3,
    required SimplePublicKey initiatorIK,
    required SimplePublicKey initiatorEK,
    required SimplePublicKey responderIK,
    required SimplePublicKey responderEK,
  }) async {
    final dh1Bytes = await dh1.extractBytes();
    final dh2Bytes = await dh2.extractBytes();
    final dh3Bytes = await dh3.extractBytes();

    final ikm = Uint8List.fromList([...dh1Bytes, ...dh2Bytes, ...dh3Bytes]);

    final transcript = [
      ...initiatorIK.bytes,
      ...initiatorEK.bytes,
      ...responderIK.bytes,
      ...responderEK.bytes,
    ];

    final info = [
      ...utf8.encode('TripleDH-Deniable-v1:'),
      ...transcript,
    ];

    return await hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      info: info,
    );
  }

  /// Wipe ephemeral keys when session ends
  void zeroizeEphemeral() {
    _ephemeralKeyPair = null;
    lastCryptoTimings = null;
    lastEphemeralGenDuration = null;
  }
}
