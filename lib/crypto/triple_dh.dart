import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Triple-DH (3DH) handshake manager providing mutual authentication
/// and cryptographic deniability without long-term digital signatures.
class TripleDH {
  static final X25519 x25519 = X25519();
  static final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  final SimpleKeyPair identityKeyPair;
  SimpleKeyPair? _ephemeralKeyPair;

  TripleDH({required this.identityKeyPair});

  /// Generate a fresh ephemeral keypair for this session
  Future<SimplePublicKey> generateEphemeralKey() async {
    _ephemeralKeyPair = await x25519.newKeyPair();
    return await _ephemeralKeyPair!.extractPublicKey();
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

    final dh1 = await x25519.sharedSecretKey(
      keyPair: identityKeyPair,
      remotePublicKey: remoteEphemeralKey,
    );

    final dh2 = await x25519.sharedSecretKey(
      keyPair: _ephemeralKeyPair!,
      remotePublicKey: remoteIdentityKey,
    );

    final dh3 = await x25519.sharedSecretKey(
      keyPair: _ephemeralKeyPair!,
      remotePublicKey: remoteEphemeralKey,
    );

    final myIdentityPub = await identityKeyPair.extractPublicKey();
    final myEphemeralPub = await _ephemeralKeyPair!.extractPublicKey();

    return _deriveMasterKey(
      dh1: dh1,
      dh2: dh2,
      dh3: dh3,
      initiatorIK: myIdentityPub,
      initiatorEK: myEphemeralPub,
      responderIK: remoteIdentityKey,
      responderEK: remoteEphemeralKey,
    );
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

    // Notice: Bob uses his ephemeral against Alice's identity (matches DH1)
    final dh1 = await x25519.sharedSecretKey(
      keyPair: _ephemeralKeyPair!,
      remotePublicKey: remoteIdentityKey,
    );

    // Notice: Bob uses his identity against Alice's ephemeral (matches DH2)
    final dh2 = await x25519.sharedSecretKey(
      keyPair: identityKeyPair,
      remotePublicKey: remoteEphemeralKey,
    );

    final dh3 = await x25519.sharedSecretKey(
      keyPair: _ephemeralKeyPair!,
      remotePublicKey: remoteEphemeralKey,
    );

    final myIdentityPub = await identityKeyPair.extractPublicKey();
    final myEphemeralPub = await _ephemeralKeyPair!.extractPublicKey();

    return _deriveMasterKey(
      dh1: dh1,
      dh2: dh2,
      dh3: dh3,
      initiatorIK: remoteIdentityKey,
      initiatorEK: remoteEphemeralKey,
      responderIK: myIdentityPub,
      responderEK: myEphemeralPub,
    );
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
  }
}
