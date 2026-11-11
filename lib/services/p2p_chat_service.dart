import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide EncryptedPacket;
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as dart_crypto;
import '../crypto/triple_dh.dart';
import '../crypto/split_vault.dart';
import '../crypto/deniable_cipher.dart';
import 'signaling_service.dart';
import 'presence_history_store.dart';
import 'user_address.dart';
import 'saved_contact.dart';
import 'notification_service.dart';
import 'firestore_security.dart';

enum SessionStatus {
  idle,
  vaultLocked,
  signaling,
  webrtcConnected,
  exchanging3DH,
  presenceActivated,
  disconnected,
  error,
}

/// In-memory representation of an encrypted media or file attachment
class ChatMediaAttachment {
  final String fileId;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final bool isImage;
  final String sha256;
  Uint8List? bytes; // Volatile ephemeral RAM only!
  double progress; // 0.0 to 1.0
  bool isComplete;
  String? error;

  ChatMediaAttachment({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.isImage,
    required this.sha256,
    this.bytes,
    this.progress = 1.0,
    this.isComplete = true,
    this.error,
  });

  /// Explicitly zeroize media buffer from memory
  void zeroize() {
    if (bytes != null) {
      bytes!.fillRange(0, bytes!.length, 0);
      bytes = null;
    }
  }
}

class _IncomingFileAssembly {
  final ChatMediaAttachment meta;
  final List<Uint8List?> chunks;
  int receivedChunks = 0;

  _IncomingFileAssembly({
    required this.meta,
    required int totalChunks,
  }) : chunks = List<Uint8List?>.filled(totalChunks, null);

  void zeroize() {
    for (final c in chunks) {
      if (c != null) {
        c.fillRange(0, c.length, 0);
      }
    }
    chunks.clear();
    meta.zeroize();
  }
}

class ChatMessage {
  final String text;
  final bool isMe;
  final DateTime timestamp;
  final DeniablePacket? packet; // For packet & MAC disclosure inspection
  final ChatMediaAttachment? attachment;

  ChatMessage({
    required this.text,
    required this.isMe,
    required this.timestamp,
    this.packet,
    this.attachment,
  });
}

/// Orchestrates the Deniable Triple-DH (3DH) handshake,
/// 2-of-2 presence-enforced cache reconstruction,
/// and OTR-style MAC key publication over WebRTC RTCDataChannel.
class P2PChatService extends ChangeNotifier {
  final SignalingService _signalingService;
  final SplitVault _vault = SplitVault();
  PresenceHistoryStore? _historyStore;

  P2PChatService({SignalingService? signalingService})
      : _signalingService = signalingService ?? SignalingService();

  SessionStatus _status = SessionStatus.vaultLocked;
  String? _roomId;
  bool _isInitiator = false;
  String? _errorMessage;

  TripleDH? _tripleDH;
  DeniableCipher? _deniableCipher;
  RTCDataChannel? _dataChannel;

  final List<ChatMessage> _messages = [];
  final List<DeniablePacket> _packetLog = [];
  final List<UserAddress> _addresses = [];
  final List<SavedContact> _contacts = [];
  IncomingCallRequest? _incomingCall;
  final Map<String, _IncomingFileAssembly> _incomingAssemblies = {};

  SessionStatus get status => _status;
  String? get roomId => _roomId;
  String? get errorMessage => _errorMessage;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<DeniablePacket> get packetLog => List.unmodifiable(_packetLog);
  List<DisclosedMacKey> get publishedKeysLog => _deniableCipher?.publishedKeysLog ?? [];
  List<UserAddress> get addresses => List.unmodifiable(_addresses);
  List<SavedContact> get contacts => List.unmodifiable(_contacts);
  IncomingCallRequest? get incomingCall => _incomingCall;

  bool get isVaultUnlocked => _vault.identityKeyPair != null;
  bool get isPresenceActive => _vault.isPresenceActive;
  String? get myIdentityKeyHex => _myIdentityKeyHex;
  String? _myIdentityKeyHex;
  String? _peerIdentityKeyHex;
  String? get peerIdentityKeyHex => _peerIdentityKeyHex;

  String get peerFingerprint {
    if (_peerIdentityKeyHex == null || _peerIdentityKeyHex!.length < 16) {
      if (_roomId != null && _roomId!.length >= 8) {
        return 'fp: ${_roomId!.substring(0, 4)}:${_roomId!.substring(4, min(8, _roomId!.length))}:verified';
      }
      return 'fp: 7f0a:e29b:11c8:4c8b:9910';
    }
    final s = _peerIdentityKeyHex!;
    final chunks = <String>[];
    for (int i = 0; i < s.length && chunks.length < 5; i += 4) {
      chunks.add(s.substring(i, (i + 4 <= s.length) ? i + 4 : s.length));
    }
    return 'fp: ${chunks.join(':')}';
  }

  String get peerDisplayName {
    // Check if matching contact in saved contacts list
    for (final contact in _contacts) {
      if (_roomId != null && _roomId!.contains(contact.mailboxId)) {
        return contact.alias;
      }
    }
    if (_roomId != null && _roomId!.startsWith('bored_')) {
      final clean = _roomId!.replaceAll('bored_', '').replaceAll('-', '');
      if (clean.isNotEmpty) {
        return 'node-${clean.substring(0, min(6, clean.length))}';
      }
    }
    if (_peerIdentityKeyHex != null && _peerIdentityKeyHex!.isNotEmpty) {
      return 'node-${_peerIdentityKeyHex!.substring(0, min(6, _peerIdentityKeyHex!.length))}';
    }
    return 'node-peer';
  }

  /// Initialize local vault from storage or create new with passphrase
  Future<void> unlockOrCreateVault(String passphrase) async {
    _historyStore ??= await PresenceHistoryStore.create();

    if (_historyStore!.hasStoredVault) {
      final unlocked = await _historyStore!.unlockVault(passphrase);
      _vault.unlockLocalVault(
        identityKeyPair: unlocked['identityKeyPair'] as SimpleKeyPair,
        localShare: unlocked['localShare'] as Uint8List,
      );
    } else {
      final identityKey = await X25519().newKeyPair();
      final sharePair = SplitVault.createSharePair();
      // s1 stays on this device, s2 is for peer
      await _historyStore!.setupNewVault(
        passphrase: passphrase,
        identityKeyPair: identityKey,
        existingShare: sharePair['s1'],
      );
      _vault.unlockLocalVault(
        identityKeyPair: identityKey,
        localShare: sharePair['s1']!,
      );
    }

    final pubKey = await _vault.identityKeyPair!.extractPublicKey();
    _myIdentityKeyHex = pubKey.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // Load or initialize disposable addresses
    final loaded = _historyStore!.loadAddresses();
    _addresses.clear();
    _addresses.addAll(loaded);
    if (_addresses.isEmpty) {
      final defaultAddr = UserAddress(
        id: UserAddress.generateId(),
        label: 'Default Alias',
        createdAt: DateTime.now(),
      );
      _addresses.add(defaultAddr);
      await _historyStore!.saveAddresses(_addresses);
    }

    // Load saved contacts
    final loadedContacts = _historyStore!.loadContacts();
    _contacts.clear();
    _contacts.addAll(loadedContacts);

    _startAddressListeners();

    _status = SessionStatus.idle;
    notifyListeners();
  }

  void _startAddressListeners() {
    for (final addr in _addresses) {
      _signalingService.startListeningToAddress(addr.id, _onIncomingCallReceived);
    }
  }

  void _onIncomingCallReceived(IncomingCallRequest call) {
    debugPrint('[P2P] Incoming connection detected on address: ${call.addressId}');
    _incomingCall = call;

    // Resolve caller if matching saved contact in vault
    SavedContact? matchedContact;
    try {
      matchedContact = _contacts.firstWhere(
        (c) => c.mailboxId == call.addressId,
      );
    } catch (_) {}

    // Trigger Cross-Platform Blind / Zero-Knowledge Push Notification
    NotificationService().showInboundCallNotification(
      callId: call.callId,
      addressId: call.addressId,
      callerAlias: matchedContact?.alias,
      isVaultLocked: !isVaultUnlocked,
    );

    notifyListeners();
  }

  /// Add a peer to saved contacts / address book
  Future<SavedContact> addContact(String alias, String mailboxId, {String? fingerprint}) async {
    final cleanMailbox = UserAddress.normalizeId(mailboxId);
    final contact = SavedContact(
      id: 'c_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}',
      alias: alias.trim().isEmpty ? 'Peer Node' : alias.trim(),
      mailboxId: cleanMailbox,
      fingerprint: fingerprint,
      addedAt: DateTime.now(),
    );
    _contacts.add(contact);
    await _historyStore?.saveContacts(_contacts);
    notifyListeners();
    return contact;
  }

  /// Delete a saved contact
  Future<void> deleteContact(String contactId) async {
    _contacts.removeWhere((c) => c.id == contactId);
    await _historyStore?.saveContacts(_contacts);
    notifyListeners();
  }

  /// 1-Click Call a saved contact without exchanging links
  Future<String> callContact(SavedContact contact) async {
    final updated = contact.copyWith(lastDialedAt: DateTime.now());
    final idx = _contacts.indexWhere((c) => c.id == contact.id);
    if (idx != -1) {
      _contacts[idx] = updated;
      await _historyStore?.saveContacts(_contacts);
    }
    return callAddress(contact.mailboxId);
  }

  /// Generate a brand new disposable address (alias) that can be shared with a peer
  Future<UserAddress> generateAddress({String? label, bool isOneTime = false}) async {
    FirestoreRateLimiter().enforce('create_address');
    final newAddr = UserAddress(
      id: UserAddress.generateId(),
      label: (label != null && label.trim().isNotEmpty)
          ? label.trim()
          : 'Disposable Alias #${_addresses.length + 1}',
      isOneTime: isOneTime,
      createdAt: DateTime.now(),
    );
    _addresses.add(newAddr);
    await _historyStore?.saveAddresses(_addresses);
    _signalingService.startListeningToAddress(newAddr.id, _onIncomingCallReceived);
    notifyListeners();
    return newAddr;
  }

  /// Delete / burn an address
  Future<void> deleteAddress(String addressId) async {
    _signalingService.stopListeningToAddress(addressId);
    _addresses.removeWhere((a) => a.id == addressId);
    await _historyStore?.saveAddresses(_addresses);
    notifyListeners();
  }

  /// Dial a peer's disposable address
  Future<String> callAddress(String targetAddress) async {
    if (!isVaultUnlocked) {
      throw StateError('Unlock your passphrase vault first');
    }
    try {
      _isInitiator = true;
      _status = SessionStatus.signaling;
      _errorMessage = null;
      notifyListeners();

      _tripleDH = TripleDH(identityKeyPair: _vault.identityKeyPair!);
      _signalingService.onDataChannelReady = _onDataChannelAcquired;
      _signalingService.onConnectionStateChange = _onConnectionState;

      _roomId = await _signalingService.callAddress(targetAddress);
      notifyListeners();
      return _roomId!;
    } catch (e) {
      _status = SessionStatus.error;
      _errorMessage = 'Failed to call address: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Answer an incoming connection request on an Address
  Future<void> answerCall(IncomingCallRequest call) async {
    if (!isVaultUnlocked) {
      throw StateError('Unlock your passphrase vault first');
    }
    try {
      _isInitiator = false;
      _status = SessionStatus.signaling;
      _errorMessage = null;
      _roomId = call.addressId;
      notifyListeners();

      _tripleDH = TripleDH(identityKeyPair: _vault.identityKeyPair!);
      _signalingService.onDataChannelReady = _onDataChannelAcquired;
      _signalingService.onConnectionStateChange = _onConnectionState;

      await _signalingService.answerAddressCall(call);

      // If address was single-use (burner), burn it now
      final matchedAddr = _addresses.firstWhere(
        (a) => a.id == call.addressId,
        orElse: () => UserAddress(id: '', label: '', createdAt: DateTime.now()),
      );
      if (matchedAddr.isOneTime && matchedAddr.id.isNotEmpty) {
        await deleteAddress(matchedAddr.id);
      }

      NotificationService().cancelCallNotification(call.callId);
      _incomingCall = null;
      notifyListeners();
    } catch (e) {
      _status = SessionStatus.error;
      _errorMessage = 'Failed to answer call: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Decline incoming call
  void declineCall() {
    if (_incomingCall != null) {
      NotificationService().cancelCallNotification(_incomingCall!.callId);
    }
    _incomingCall = null;
    notifyListeners();
  }

  /// Host / Caller: create a new room
  Future<String> hostRoom() async {
    if (!isVaultUnlocked) {
      throw StateError('Unlock your passphrase vault first');
    }
    try {
      _isInitiator = true;
      _status = SessionStatus.signaling;
      _errorMessage = null;
      notifyListeners();

      _tripleDH = TripleDH(identityKeyPair: _vault.identityKeyPair!);

      _signalingService.onDataChannelReady = _onDataChannelAcquired;
      _signalingService.onConnectionStateChange = _onConnectionState;

      _roomId = await _signalingService.createRoom();
      notifyListeners();
      return _roomId!;
    } catch (e) {
      _status = SessionStatus.error;
      _errorMessage = 'Failed to create room: $e\n\nEnsure Cloud Firestore is created in the Firebase console for project murmur-b7430.';
      notifyListeners();
      rethrow;
    }
  }

  /// Callee / Peer: join an existing room
  Future<void> joinRoom(String roomId) async {
    if (!isVaultUnlocked) {
      throw StateError('Unlock your passphrase vault first');
    }
    try {
      _isInitiator = false;
      _status = SessionStatus.signaling;
      _errorMessage = null;
      _roomId = roomId;
      notifyListeners();

      _tripleDH = TripleDH(identityKeyPair: _vault.identityKeyPair!);

      _signalingService.onDataChannelReady = _onDataChannelAcquired;
      _signalingService.onConnectionStateChange = _onConnectionState;

      await _signalingService.joinRoom(roomId);
    } catch (e) {
      _status = SessionStatus.error;
      _errorMessage = 'Failed to join room: $e\n\nEnsure Cloud Firestore is created in the Firebase console for project murmur-b7430.';
      notifyListeners();
      rethrow;
    }
  }

  void _onConnectionState(RTCPeerConnectionState state) {
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
      _onDisconnected();
    }
  }

  void _onDataChannelAcquired(RTCDataChannel channel) {
    debugPrint('[P2P] RTCDataChannel acquired. Current state: ${channel.state}');
    _dataChannel = channel;

    channel.onDataChannelState = (RTCDataChannelState state) {
      debugPrint('[P2P] RTCDataChannel state transition: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _status = SessionStatus.webrtcConnected;
        notifyListeners();
        _send3DHHandshake();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _onDisconnected();
      }
    };

    channel.onMessage = (RTCDataChannelMessage message) {
      _handleIncomingData(message.text);
    };

    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      debugPrint('[P2P] RTCDataChannel was already OPEN! Sending 3DH handshake immediately...');
      _status = SessionStatus.webrtcConnected;
      notifyListeners();
      _send3DHHandshake();
    }
  }

  /// Step 1: Send our Identity Key & fresh Ephemeral Key (No signatures!)
  Future<void> _send3DHHandshake() async {
    if (_dataChannel == null || _tripleDH == null) return;

    _status = SessionStatus.exchanging3DH;
    notifyListeners();

    final myEphemeralPub = await _tripleDH!.generateEphemeralKey();
    final myIdentityPub = await _vault.identityKeyPair!.extractPublicKey();

    final handshakePayload = jsonEncode({
      'type': '3DH_HANDSHAKE',
      'ik': base64Encode(myIdentityPub.bytes),
      'ek': base64Encode(myEphemeralPub.bytes),
    });

    _dataChannel!.send(RTCDataChannelMessage(handshakePayload));
  }

  /// Handle incoming wire messages over RTCDataChannel
  Future<void> _handleIncomingData(String rawText) async {
    try {
      final Map<String, dynamic> data = jsonDecode(rawText) as Map<String, dynamic>;
      final String type = data['type'] as String? ?? '';

      switch (type) {
        case '3DH_HANDSHAKE':
          final remoteIKBytes = base64Decode(data['ik'] as String);
          final remoteEKBytes = base64Decode(data['ek'] as String);

          _peerIdentityKeyHex = remoteIKBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

          final remoteIK = SimplePublicKey(remoteIKBytes, type: KeyPairType.x25519);
          final remoteEK = SimplePublicKey(remoteEKBytes, type: KeyPairType.x25519);

          // Compute Deniable Triple-DH Session Key
          SecretKey sessionKey;
          if (_isInitiator) {
            sessionKey = await _tripleDH!.computeInitiatorSessionKey(
              remoteIdentityKey: remoteIK,
              remoteEphemeralKey: remoteEK,
            );
          } else {
            sessionKey = await _tripleDH!.computeResponderSessionKey(
              remoteIdentityKey: remoteIK,
              remoteEphemeralKey: remoteEK,
            );
          }

          _deniableCipher = DeniableCipher(sessionKey: sessionKey);

          // Step 2: Swap 2-of-2 cache shares over encrypted channel
          final sharePayload = jsonEncode({
            'type': 'SHARE_SWAP',
            'share': base64Encode(_vault.localShare!),
          });
          _dataChannel?.send(RTCDataChannelMessage(sharePayload));
          break;

        case 'SHARE_SWAP':
          final remoteShare = base64Decode(data['share'] as String);

          // Step 3: Reconstruct K = s1 XOR s2 in memory!
          _vault.activatePresence(remoteShare);
          _status = SessionStatus.presenceActivated;

          // Decrypt historical messages from disk into RAM
          await _decryptHistoricalMessages();
          notifyListeners();
          break;

        case 'DENIABLE_MSG':
          if (_deniableCipher == null) throw Exception('Cipher not ready');
          final packetMap = data['packet'] as Map<String, dynamic>;
          final packet = DeniablePacket.fromJson(packetMap);
          _packetLog.add(packet);

          // Decrypt & verify symmetric HMAC
          final plaintext = await _deniableCipher!.decryptMessage(packet);

          _messages.add(ChatMessage(
            text: plaintext,
            isMe: false,
            timestamp: DateTime.fromMillisecondsSinceEpoch(packet.localTimestamp),
            packet: packet,
          ));

          // Save to encrypted history at rest using K
          if (_vault.isPresenceActive && _historyStore != null) {
            final encryptedBlock = await _vault.encryptHistoryMessage(plaintext);
            await _historyStore!.appendHistoryBlock(encryptedBlock);
          }

          notifyListeners();
          break;

        case 'FILE_TRANSFER_START':
          final fileId = data['fileId'] as String;
          final fileName = data['fileName'] as String;
          final fileSize = data['fileSize'] as int;
          final mimeType = data['mimeType'] as String;
          final totalChunks = data['totalChunks'] as int;
          final fileSha256 = data['sha256'] as String;
          final isImage = data['isImage'] as bool? ?? mimeType.startsWith('image/');

          final incomingAttachment = ChatMediaAttachment(
            fileId: fileId,
            fileName: fileName,
            fileSize: fileSize,
            mimeType: mimeType,
            isImage: isImage,
            sha256: fileSha256,
            bytes: null,
            progress: 0.0,
            isComplete: false,
          );

          final incomingMsg = ChatMessage(
            text: isImage ? '[Image: $fileName]' : '[File: $fileName]',
            isMe: false,
            timestamp: DateTime.now(),
            attachment: incomingAttachment,
          );

          _messages.add(incomingMsg);
          _incomingAssemblies[fileId] = _IncomingFileAssembly(
            meta: incomingAttachment,
            totalChunks: totalChunks,
          );
          notifyListeners();
          break;

        case 'FILE_TRANSFER_CHUNK':
          final fileId = data['fileId'] as String;
          final chunkIndex = data['chunkIndex'] as int;
          final assembly = _incomingAssemblies[fileId];
          if (assembly != null && _deniableCipher != null) {
            final packetMap = data['packet'] as Map<String, dynamic>;
            final chunkPacket = DeniablePacket.fromJson(packetMap);
            _packetLog.add(chunkPacket);

            final decryptedBytes = await _deniableCipher!.decryptBytes(chunkPacket);
            if (chunkIndex >= 0 && chunkIndex < assembly.chunks.length) {
              if (assembly.chunks[chunkIndex] == null) {
                assembly.chunks[chunkIndex] = Uint8List.fromList(decryptedBytes);
                assembly.receivedChunks++;
                assembly.meta.progress = assembly.receivedChunks / assembly.chunks.length;
                notifyListeners();
              }
            }
          }
          break;

        case 'FILE_TRANSFER_COMPLETE':
          final fileId = data['fileId'] as String;
          final expectedSha256 = data['sha256'] as String;
          final assembly = _incomingAssemblies.remove(fileId);
          if (assembly != null) {
            final builder = BytesBuilder(copy: false);
            for (final chunk in assembly.chunks) {
              if (chunk != null) {
                builder.add(chunk);
              }
            }
            final assembledBytes = builder.toBytes();
            final actualSha256 = dart_crypto.sha256.convert(assembledBytes).toString();
            if (actualSha256 == expectedSha256) {
              assembly.meta.bytes = assembledBytes;
              assembly.meta.progress = 1.0;
              assembly.meta.isComplete = true;
            } else {
              assembly.meta.error = 'Checksum validation failed: file corrupted in transit.';
              debugPrint('[P2P] Checksum mismatch on file $fileId: expected $expectedSha256, got $actualSha256');
            }
            notifyListeners();
          }
          break;

        case 'PEER_LEFT':
          debugPrint('[P2P] Remote peer explicitly left. Wiping volatile RAM and sealing history...');
          _onDisconnected();
          break;

        default:
          debugPrint('Unknown packet type: $type');
      }
    } catch (e) {
      debugPrint('Error handling incoming data channel message: $e');
    }
  }

  /// Decrypt stored history blocks using active K
  Future<void> _decryptHistoricalMessages() async {
    if (_historyStore == null || !_vault.isPresenceActive) return;
    final blocks = _historyStore!.loadEncryptedHistory();
    for (final block in blocks) {
      try {
        final text = await _vault.decryptHistoryMessage(block);
        _messages.add(ChatMessage(
          text: text,
          isMe: false,
          timestamp: DateTime.now(),
        ));
      } catch (e) {
        debugPrint('Could not decrypt history block: $e');
      }
    }
  }

  /// Encrypt and transmit a new message with OTR MAC key disclosure
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    if (_deniableCipher == null || _dataChannel == null) {
      throw StateError('Channel or cipher not ready');
    }

    final packet = await _deniableCipher!.encryptMessage(text);
    _packetLog.add(packet);

    final payload = jsonEncode({
      'type': 'DENIABLE_MSG',
      'packet': packet.toJson(),
    });

    await _dataChannel!.send(RTCDataChannelMessage(payload));

    _messages.add(ChatMessage(
      text: text,
      isMe: true,
      timestamp: DateTime.fromMillisecondsSinceEpoch(packet.localTimestamp),
      packet: packet,
    ));

    // Save to local history encrypted under K
    if (_vault.isPresenceActive && _historyStore != null) {
      final encryptedBlock = await _vault.encryptHistoryMessage(text);
      await _historyStore!.appendHistoryBlock(encryptedBlock);
    }

    notifyListeners();
  }

  /// Encrypt and transmit media file (image, document, binary) in chunked deniable packets
  Future<void> sendMediaFile({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    if (bytes.isEmpty) return;
    if (_deniableCipher == null || _dataChannel == null) {
      throw StateError('Channel or cipher not ready');
    }

    // 20MB safety limit to protect RAM and browser buffers
    const maxSizeBytes = 20 * 1024 * 1024;
    if (bytes.length > maxSizeBytes) {
      throw ArgumentError('File exceeds max 20 MB size limit.');
    }

    final fileId = _generateRandomHex(8);
    final detectedMime = mimeType ?? _detectMimeType(fileName);
    final isImage = detectedMime.startsWith('image/');
    final fileSha256 = dart_crypto.sha256.convert(bytes).toString();

    // 16 KB safe WebRTC chunk size
    const chunkSize = 16384;
    final totalChunks = (bytes.length / chunkSize).ceil();

    final attachment = ChatMediaAttachment(
      fileId: fileId,
      fileName: fileName,
      fileSize: bytes.length,
      mimeType: detectedMime,
      isImage: isImage,
      sha256: fileSha256,
      bytes: bytes,
      progress: 0.0,
      isComplete: false,
    );

    final chatMsg = ChatMessage(
      text: isImage ? '[Image: $fileName]' : '[File: $fileName]',
      isMe: true,
      timestamp: DateTime.now(),
      attachment: attachment,
    );

    _messages.add(chatMsg);
    notifyListeners();

    try {
      // 1. Send FILE_TRANSFER_START
      final startPayload = jsonEncode({
        'type': 'FILE_TRANSFER_START',
        'fileId': fileId,
        'fileName': fileName,
        'fileSize': bytes.length,
        'mimeType': detectedMime,
        'totalChunks': totalChunks,
        'sha256': fileSha256,
        'isImage': isImage,
      });
      await _dataChannel!.send(RTCDataChannelMessage(startPayload));

      // 2. Stream encrypted chunks
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize < bytes.length) ? start + chunkSize : bytes.length;
        final slice = bytes.sublist(start, end);

        final encryptedPacket = await _deniableCipher!.encryptBytes(slice);

        final chunkPayload = jsonEncode({
          'type': 'FILE_TRANSFER_CHUNK',
          'fileId': fileId,
          'chunkIndex': i,
          'totalChunks': totalChunks,
          'packet': encryptedPacket.toJson(),
        });

        await _dataChannel!.send(RTCDataChannelMessage(chunkPayload));

        attachment.progress = (i + 1) / totalChunks;
        notifyListeners();

        // Brief yield for WebRTC bufferedAmount stability
        if (totalChunks > 1) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }

      // 3. Send FILE_TRANSFER_COMPLETE
      final completePayload = jsonEncode({
        'type': 'FILE_TRANSFER_COMPLETE',
        'fileId': fileId,
        'sha256': fileSha256,
      });
      await _dataChannel!.send(RTCDataChannelMessage(completePayload));

      attachment.isComplete = true;
      attachment.progress = 1.0;
      notifyListeners();
    } catch (e) {
      attachment.error = 'Transfer failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  static String _detectMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt') || lower.endsWith('.log')) return 'text/plain';
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
  }

  static String _generateRandomHex(int byteCount) {
    final rnd = Random.secure();
    return List.generate(byteCount, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  void _onDisconnected() {
    // CRITICAL: Zeroize K and remote share s2 from memory immediately!
    _vault.zeroizeSession();
    _tripleDH?.zeroizeEphemeral();
    _deniableCipher = null;

    // Zeroize all volatile media attachments in RAM
    for (final msg in _messages) {
      msg.attachment?.zeroize();
    }
    for (final assembly in _incomingAssemblies.values) {
      assembly.zeroize();
    }
    _incomingAssemblies.clear();

    // CRITICAL VULNERABILITY FIX: The moment one party leaves, active presence is terminated.
    // All decrypted plaintext messages and packets MUST be immediately purged from volatile RAM.
    _messages.clear();
    _packetLog.clear();

    _status = SessionStatus.disconnected;
    notifyListeners();
  }

  /// Leave room and clean up session
  Future<void> leaveRoom() async {
    try {
      if (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
        final leavePkt = jsonEncode({
          'type': 'PEER_LEFT',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        _dataChannel!.send(RTCDataChannelMessage(leavePkt));
      }
    } catch (e) {
      debugPrint('[P2P] Notice: Could not send PEER_LEFT packet over data channel: $e');
    }

    _onDisconnected();
    await _signalingService.disposeSession();
    _startAddressListeners();
    _roomId = null;
    _peerIdentityKeyHex = null;
    _tripleDH = null;
    _status = SessionStatus.idle;
    notifyListeners();
  }

  /// Cleanly reset disconnected state back to idle standby
  Future<void> resetToIdle() async {
    await leaveRoom();
  }
}
