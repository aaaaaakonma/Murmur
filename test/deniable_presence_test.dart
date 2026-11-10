import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:bored_p2p_chat/crypto/triple_dh.dart';
import 'package:bored_p2p_chat/crypto/split_vault.dart';
import 'package:bored_p2p_chat/crypto/deniable_cipher.dart';

void main() {
  group('Deniable Triple-DH (3DH) Handshake Tests', () {
    test('Alice and Bob compute identical session keys with zero signatures', () async {
      final x25519 = X25519();

      // Long-term Identity keys
      final aliceIK = await x25519.newKeyPair();
      final bobIK = await x25519.newKeyPair();

      final alice3DH = TripleDH(identityKeyPair: aliceIK);
      final bob3DH = TripleDH(identityKeyPair: bobIK);

      // Fresh Ephemeral keys
      final aliceEKPub = await alice3DH.generateEphemeralKey();
      final bobEKPub = await bob3DH.generateEphemeralKey();

      final aliceIKPub = await aliceIK.extractPublicKey();
      final bobIKPub = await bobIK.extractPublicKey();

      // Alice computes session key as initiator
      final aliceSessionKey = await alice3DH.computeInitiatorSessionKey(
        remoteIdentityKey: bobIKPub,
        remoteEphemeralKey: bobEKPub,
      );

      // Bob computes session key as responder
      final bobSessionKey = await bob3DH.computeResponderSessionKey(
        remoteIdentityKey: aliceIKPub,
        remoteEphemeralKey: aliceEKPub,
      );

      final aliceBytes = await aliceSessionKey.extractBytes();
      final bobBytes = await bobSessionKey.extractBytes();

      expect(aliceBytes, equals(bobBytes));
      expect(aliceBytes.length, equals(32));
    });
  });

  group('2-of-2 Presence-Enforced Cache Tests', () {
    test('History cannot be decrypted without peer supplying s2', () async {
      // Create 2-of-2 split: K = s1 XOR s2
      final sharePair = SplitVault.createSharePair();
      final masterK = sharePair['k']!;
      final s1 = sharePair['s1']!;
      final s2 = sharePair['s2']!;

      expect(SplitVault.xorShares(s1, s2), equals(masterK));

      final aliceVault = SplitVault();
      final dummyIdKey = await X25519().newKeyPair();
      aliceVault.unlockLocalVault(identityKeyPair: dummyIdKey, localShare: s1);

      // Presence is NOT active yet (Alice only has s1)
      expect(aliceVault.isPresenceActive, isFalse);
      expect(() => aliceVault.encryptHistoryMessage('test'), throwsStateError);

      // Bob comes online and supplies s2 over the authenticated session
      aliceVault.activatePresence(s2);
      expect(aliceVault.isPresenceActive, isTrue);
      expect(aliceVault.reconstructedK, equals(masterK));

      // Alice can now encrypt and decrypt history
      const secretHistory = 'Classified peer conversation from yesterday';
      final encryptedBlob = await aliceVault.encryptHistoryMessage(secretHistory);
      final decrypted = await aliceVault.decryptHistoryMessage(encryptedBlob);
      expect(decrypted, equals(secretHistory));

      // Session ends: zeroize K and s2 from memory
      aliceVault.zeroizeSession();
      expect(aliceVault.isPresenceActive, isFalse);
      expect(aliceVault.reconstructedK, isNull);

      // Attempting to decrypt now fails because K is wiped
      expect(() => aliceVault.decryptHistoryMessage(encryptedBlob), throwsStateError);
    });

    test('Argon2id wraps and unwraps local share at rest', () async {
      const passphrase = 'correct horse battery staple';
      final salt = SplitVault.generateSalt();
      final vaultKey = await SplitVault.deriveVaultKey(passphrase, salt);

      final localShare = SplitVault.generateRandomShare();
      final wrapped = await SplitVault.wrapSecret(vaultKey, localShare);

      // Correct passphrase unwraps successfully
      final unwrapped = await SplitVault.unwrapSecret(vaultKey, wrapped);
      expect(unwrapped, equals(localShare));

      // Wrong passphrase fails decryption
      final wrongVaultKey = await SplitVault.deriveVaultKey('wrong_passphrase', salt);
      expect(
        () => SplitVault.unwrapSecret(wrongVaultKey, wrapped),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('Deniable Cipher & OTR-Style MAC Key Disclosure Tests', () {
    test('Messages are encrypted and previous MAC keys are published on next message', () async {
      final sessionKey = SecretKey(List<int>.generate(32, (i) => i));

      final senderCipher = DeniableCipher(sessionKey: sessionKey);
      final receiverCipher = DeniableCipher(sessionKey: sessionKey);

      // Message 1
      final p1 = await senderCipher.encryptMessage('First private message');
      expect(p1.seq, equals(1));
      expect(p1.disclosedMacKeys, isEmpty); // No previous MAC key to disclose yet

      final text1 = await receiverCipher.decryptMessage(p1);
      expect(text1, equals('First private message'));

      // Message 2: Should disclose the MAC key for Message 1!
      final p2 = await senderCipher.encryptMessage('Second private message');
      expect(p2.seq, equals(2));
      expect(p2.disclosedMacKeys.length, equals(1));
      expect(p2.disclosedMacKeys.first.seq, equals(1));

      final text2 = await receiverCipher.decryptMessage(p2);
      expect(text2, equals('Second private message'));

      // Verify repudiation: With the disclosed MAC key, anyone can forge an HMAC for Message 1
      final disclosedKeyHex = p2.disclosedMacKeys.first.keyHex;
      final rawMacKeyBytes = Uint8List.fromList(
        List.generate(
          disclosedKeyHex.length ~/ 2,
          (i) => int.parse(disclosedKeyHex.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );
      final forgedMacKey = SecretKey(rawMacKeyBytes);
      final forgedData = [...base64Decode(p1.nonceBase64), ...base64Decode(p1.ciphertextBase64), ...base64Decode(p1.gcmTagBase64)];
      final forgedMac = await Hmac.sha256().calculateMac(forgedData, secretKey: forgedMacKey);

      // The forged MAC matches the original packet MAC, proving universal forgeability!
      final forgedHex = forgedMac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(forgedHex, equals(p1.hmacHex));
    });
  });
}
