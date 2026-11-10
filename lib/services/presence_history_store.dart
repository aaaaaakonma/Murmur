import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../crypto/split_vault.dart';
import 'user_address.dart';
import 'saved_contact.dart';

/// Local storage repository for Argon2id-wrapped credentials,
/// 2-of-2 presence-enforced chat history, disposable addresses,
/// and saved peer directory contacts.
class PresenceHistoryStore {
  static const String _keySalt = 'vault_salt';
  static const String _keyIdentity = 'vault_identity_wrapped';
  static const String _keyLocalShare = 'vault_local_share_wrapped';
  static const String _keyHistory = 'vault_encrypted_history';
  static const String _keyAddresses = 'user_disposable_addresses';
  static const String _keyContacts = 'vault_saved_contacts';

  final SharedPreferences _prefs;

  PresenceHistoryStore(this._prefs);

  static Future<PresenceHistoryStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PresenceHistoryStore(prefs);
  }

  bool get hasStoredVault => _prefs.containsKey(_keySalt) && _prefs.containsKey(_keyLocalShare);

  /// Initialize a brand new local vault with user passphrase
  Future<Map<String, Uint8List>> setupNewVault({
    required String passphrase,
    required SimpleKeyPair identityKeyPair,
    Uint8List? existingShare,
  }) async {
    final salt = SplitVault.generateSalt();
    final vaultKey = await SplitVault.deriveVaultKey(passphrase, salt);

    // Identity private key bytes
    final identityKeyData = await identityKeyPair.extract();
    final identityPrivBytes = identityKeyData.bytes;

    // Local share: either provided (s2 from peer) or generated freshly
    final localShare = existingShare ?? SplitVault.generateRandomShare();

    // Wrap both under Argon2id vault key
    final wrappedId = await SplitVault.wrapSecret(vaultKey, identityPrivBytes);
    final wrappedShare = await SplitVault.wrapSecret(vaultKey, localShare);

    await _prefs.setString(_keySalt, base64Encode(salt));
    await _prefs.setString(_keyIdentity, jsonEncode(wrappedId.toJson()));
    await _prefs.setString(_keyLocalShare, jsonEncode(wrappedShare.toJson()));

    return {'salt': salt, 'localShare': localShare};
  }

  /// Unlock local vault using user passphrase
  Future<Map<String, dynamic>> unlockVault(String passphrase) async {
    final saltBase64 = _prefs.getString(_keySalt);
    final idJson = _prefs.getString(_keyIdentity);
    final shareJson = _prefs.getString(_keyLocalShare);

    if (saltBase64 == null || idJson == null || shareJson == null) {
      throw StateError('No stored vault found on this device');
    }

    final salt = base64Decode(saltBase64);
    final vaultKey = await SplitVault.deriveVaultKey(passphrase, salt);

    final wrappedId = EncryptedBlob.fromJson(jsonDecode(idJson) as Map<String, dynamic>);
    final wrappedShare = EncryptedBlob.fromJson(jsonDecode(shareJson) as Map<String, dynamic>);

    // Unwrap identity private key & local share
    final identityPrivBytes = await SplitVault.unwrapSecret(vaultKey, wrappedId);
    final localShare = await SplitVault.unwrapSecret(vaultKey, wrappedShare);

    final keyPair = SimpleKeyPairData(
      identityPrivBytes,
      publicKey: await (await X25519().newKeyPairFromSeed(identityPrivBytes)).extractPublicKey(),
      type: KeyPairType.x25519,
    );

    return {
      'identityKeyPair': keyPair,
      'localShare': localShare,
    };
  }

  /// Append an encrypted message block to history at rest
  Future<void> appendHistoryBlock(EncryptedBlob block) async {
    final historyList = _prefs.getStringList(_keyHistory) ?? [];
    historyList.add(jsonEncode(block.toJson()));
    await _prefs.setStringList(_keyHistory, historyList);
  }

  /// Load all encrypted history blocks (still ciphertext without peer's share!)
  List<EncryptedBlob> loadEncryptedHistory() {
    final rawList = _prefs.getStringList(_keyHistory) ?? [];
    return rawList
        .map((s) => EncryptedBlob.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  /// Load all saved disposable addresses
  List<UserAddress> loadAddresses() {
    final rawList = _prefs.getStringList(_keyAddresses) ?? [];
    return rawList
        .map((s) => UserAddress.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  /// Save disposable addresses
  Future<void> saveAddresses(List<UserAddress> addresses) async {
    final rawList = addresses.map((a) => jsonEncode(a.toJson())).toList();
    await _prefs.setStringList(_keyAddresses, rawList);
  }

  /// Load all saved peer contacts
  List<SavedContact> loadContacts() {
    final rawList = _prefs.getStringList(_keyContacts) ?? [];
    return rawList
        .map((s) => SavedContact.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  /// Save peer contacts
  Future<void> saveContacts(List<SavedContact> contacts) async {
    final rawList = contacts.map((c) => jsonEncode(c.toJson())).toList();
    await _prefs.setStringList(_keyContacts, rawList);
  }

  /// Wipe all history and vault from local device
  Future<void> wipeAll() async {
    await _prefs.clear();
  }
}
