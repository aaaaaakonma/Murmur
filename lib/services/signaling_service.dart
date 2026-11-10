import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'user_address.dart';

typedef DataChannelCallback = void Function(RTCDataChannel channel);
typedef ConnectionStateCallback = void Function(RTCPeerConnectionState state);

/// Container for an incoming call request detected on an Address
class IncomingCallRequest {
  final String addressId;
  final String callId;
  final DocumentReference callRef;
  final Map<String, dynamic> offerData;
  final DateTime receivedAt;

  IncomingCallRequest({
    required this.addressId,
    required this.callId,
    required this.callRef,
    required this.offerData,
    required this.receivedAt,
  });
}

/// WebRTC Signaling manager powered by Cloud Firestore.
/// Facilitates SDP offer/answer exchange and ICE candidate trickle with buffering.
/// Supports both Rendezvous Addresses (aliases) and direct room codes.
class SignalingService {
  final FirebaseFirestore _firestore;

  SignalingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  DocumentReference? _activeSessionRef;
  String? _currentRoomId;

  StreamSubscription<DocumentSnapshot>? _roomSubscription;
  StreamSubscription<QuerySnapshot>? _candidateSubscription;
  final Map<String, StreamSubscription<QuerySnapshot>> _addressListeners = {};

  DataChannelCallback? onDataChannelReady;
  ConnectionStateCallback? onConnectionStateChange;

  static const Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // -------------------------------------------------------------
  // Address Rendezvous Signaling (Call Address & Listen to Address)
  // -------------------------------------------------------------

  /// Initiator (Caller): Dial a peer's disposable address
  Future<String> callAddress(String targetAddress) async {
    final cleanAddress = UserAddress.normalizeId(targetAddress);
    debugPrint('[Signaling] Calling address: $cleanAddress');

    // Register active address doc if not already present
    final addressRef = _firestore.collection('addresses').doc(cleanAddress);
    await addressRef.set({
      'lastActive': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final callRef = addressRef.collection('calls').doc();
    _activeSessionRef = callRef;
    _currentRoomId = '$cleanAddress/${callRef.id}';

    _peerConnection = await createPeerConnection(_configuration);
    _setupPeerConnectionListeners();

    // Caller creates DataChannel
    final RTCDataChannelInit dataChannelDict = RTCDataChannelInit()..ordered = true;
    _dataChannel = await _peerConnection!.createDataChannel('p2p_chat', dataChannelDict);
    _setupDataChannelListeners(_dataChannel!);
    onDataChannelReady?.call(_dataChannel!);

    // Collect ICE candidates and write to callerCandidates
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        callRef.collection('callerCandidates').add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    // Create SDP Offer
    final RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    await callRef.set({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'status': 'calling',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final List<RTCIceCandidate> candidateQueue = [];
    bool hasSetRemote = false;

    // Listen for Callee's SDP Answer
    _roomSubscription = callRef.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data != null && data['answer'] != null && !hasSetRemote) {
        hasSetRemote = true;
        debugPrint('[Signaling] Caller received SDP answer from address owner!');
        final answerMap = data['answer'] as Map<String, dynamic>;
        final answer = RTCSessionDescription(answerMap['sdp'], answerMap['type']);
        await _peerConnection?.setRemoteDescription(answer);

        // Drain buffered candidates
        for (final cand in candidateQueue) {
          try {
            await _peerConnection?.addCandidate(cand);
          } catch (e) {
            debugPrint('[Signaling] Error adding queued ICE candidate: $e');
          }
        }
        candidateQueue.clear();
      }
    });

    // Listen for Callee ICE Candidates
    _candidateSubscription = callRef.collection('calleeCandidates').snapshots().listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );

          if (hasSetRemote) {
            try {
              await _peerConnection?.addCandidate(candidate);
            } catch (e) {
              debugPrint('[Signaling] Error adding callee ICE candidate: $e');
            }
          } else {
            candidateQueue.add(candidate);
          }
        }
      }
    });

    return _currentRoomId!;
  }

  /// Address Owner: Start listening for incoming connection requests on [addressId]
  void startListeningToAddress(
    String addressId,
    void Function(IncomingCallRequest call) onCallReceived,
  ) {
    final clean = UserAddress.normalizeId(addressId);
    if (_addressListeners.containsKey(clean)) return;

    debugPrint('[Signaling] Starting background listener on address: $clean');
    final addressRef = _firestore.collection('addresses').doc(clean);

    // Ensure document exists
    addressRef.set({
      'status': 'listening',
      'lastListening': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final sub = addressRef
        .collection('calls')
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && data['offer'] != null) {
            final call = IncomingCallRequest(
              addressId: clean,
              callId: change.doc.id,
              callRef: change.doc.reference,
              offerData: data['offer'] as Map<String, dynamic>,
              receivedAt: DateTime.now(),
            );
            onCallReceived(call);
          }
        }
      }
    });

    _addressListeners[clean] = sub;
  }

  /// Address Owner: Stop listening to [addressId]
  void stopListeningToAddress(String addressId) {
    final clean = UserAddress.normalizeId(addressId);
    _addressListeners[clean]?.cancel();
    _addressListeners.remove(clean);
  }

  /// Address Owner (Callee): Accept & answer an incoming call request
  Future<void> answerAddressCall(IncomingCallRequest call) async {
    _activeSessionRef = call.callRef;
    _currentRoomId = '${call.addressId}/${call.callId}';
    debugPrint('[Signaling] Answering call on address: ${call.addressId}');

    _peerConnection = await createPeerConnection(_configuration);
    _setupPeerConnectionListeners();

    // Callee waits for the incoming RTCDataChannel created by caller
    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
      debugPrint('[Signaling] Callee acquired RTCDataChannel: state=${channel.state}');
      _dataChannel = channel;
      _setupDataChannelListeners(channel);
      onDataChannelReady?.call(channel);
    };

    // Callee ICE candidates written to calleeCandidates
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        call.callRef.collection('calleeCandidates').add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    // Set Remote Description from Caller's Offer
    final offer = RTCSessionDescription(
      call.offerData['sdp'] as String,
      call.offerData['type'] as String,
    );
    await _peerConnection!.setRemoteDescription(offer);

    // Create SDP Answer
    final RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await call.callRef.update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'status': 'connected',
    });

    // Listen for Caller ICE candidates
    _candidateSubscription = call.callRef
        .collection('callerCandidates')
        .snapshots()
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final candidateData = change.doc.data()!;
          try {
            await _peerConnection?.addCandidate(
              RTCIceCandidate(
                candidateData['candidate'],
                candidateData['sdpMid'],
                candidateData['sdpMLineIndex'],
              ),
            );
          } catch (e) {
            debugPrint('[Signaling] Callee error adding caller candidate: $e');
          }
        }
      }
    });
  }

  // -------------------------------------------------------------
  // Legacy / Direct Room Signaling (Create & Join by Room ID)
  // -------------------------------------------------------------

  /// Initialize caller side: creates room, creates data channel, posts SDP offer
  Future<String> createRoom() async {
    final roomRef = _firestore.collection('rooms').doc();
    _activeSessionRef = roomRef;
    _currentRoomId = roomRef.id;
    debugPrint('[Signaling] Creating direct room: $_currentRoomId');

    _peerConnection = await createPeerConnection(_configuration);
    _setupPeerConnectionListeners();

    // Caller creates the RTCDataChannel
    final RTCDataChannelInit dataChannelDict = RTCDataChannelInit()..ordered = true;
    _dataChannel = await _peerConnection!.createDataChannel('p2p_chat', dataChannelDict);
    _setupDataChannelListeners(_dataChannel!);
    onDataChannelReady?.call(_dataChannel!);

    // Collect ICE candidates and write to callerCandidates
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        roomRef.collection('callerCandidates').add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    // Create SDP Offer
    final RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    await roomRef.set({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'status': 'waiting',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final List<RTCIceCandidate> candidateQueue = [];
    bool hasSetRemote = false;

    // Listen for Callee's SDP Answer
    _roomSubscription = roomRef.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data != null && data['answer'] != null && !hasSetRemote) {
        hasSetRemote = true;
        final answerMap = data['answer'] as Map<String, dynamic>;
        final answer = RTCSessionDescription(answerMap['sdp'], answerMap['type']);
        await _peerConnection?.setRemoteDescription(answer);

        for (final cand in candidateQueue) {
          try {
            await _peerConnection?.addCandidate(cand);
          } catch (e) {
            debugPrint('[Signaling] Error adding queued ICE candidate: $e');
          }
        }
        candidateQueue.clear();
      }
    });

    // Listen for Callee ICE Candidates
    _candidateSubscription = roomRef.collection('calleeCandidates').snapshots().listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );

          if (hasSetRemote) {
            try {
              await _peerConnection?.addCandidate(candidate);
            } catch (e) {
              debugPrint('[Signaling] Error adding callee ICE candidate: $e');
            }
          } else {
            candidateQueue.add(candidate);
          }
        }
      }
    });

    return _currentRoomId!;
  }

  /// Initialize callee side: joins existing room, receives offer, posts answer
  Future<void> joinRoom(String roomId) async {
    final clean = roomId.trim();
    // If it's an address format, dispatch to calling address instead!
    if (clean.startsWith('bored_') || clean.startsWith('bored:')) {
      await callAddress(clean);
      return;
    }

    final roomRef = _firestore.collection('rooms').doc(clean);
    _activeSessionRef = roomRef;
    _currentRoomId = clean;
    final roomSnapshot = await roomRef.get();

    if (!roomSnapshot.exists) {
      throw Exception('Room $roomId does not exist.');
    }

    _peerConnection = await createPeerConnection(_configuration);
    _setupPeerConnectionListeners();

    // Callee waits for the incoming RTCDataChannel created by caller
    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
      _dataChannel = channel;
      _setupDataChannelListeners(channel);
      onDataChannelReady?.call(channel);
    };

    // Callee ICE candidates written to calleeCandidates
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        roomRef.collection('calleeCandidates').add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    // Set Remote Description from Caller's Offer
    final data = roomSnapshot.data()!;
    final offerMap = data['offer'] as Map<String, dynamic>;
    final offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);
    await _peerConnection!.setRemoteDescription(offer);

    // Create SDP Answer
    final RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await roomRef.update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'status': 'connected',
    });

    // Listen for Caller ICE candidates
    _candidateSubscription = roomRef.collection('callerCandidates').snapshots().listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final candidateData = change.doc.data()!;
          try {
            await _peerConnection?.addCandidate(
              RTCIceCandidate(
                candidateData['candidate'],
                candidateData['sdpMid'],
                candidateData['sdpMLineIndex'],
              ),
            );
          } catch (e) {
            debugPrint('[Signaling] Callee error adding caller candidate: $e');
          }
        }
      }
    });
  }

  void _setupPeerConnectionListeners() {
    _peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[Signaling] PeerConnectionState changed: $state');
      onConnectionStateChange?.call(state);
    };
    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('[Signaling] IceConnectionState changed: $state');
    };
  }

  void _setupDataChannelListeners(RTCDataChannel channel) {
    channel.onDataChannelState = (RTCDataChannelState state) {
      debugPrint('[Signaling] DataChannel state changed: $state');
    };
  }

  /// Clean up active call/room connections, subscriptions and session docs
  Future<void> disposeSession() async {
    await _roomSubscription?.cancel();
    _roomSubscription = null;
    await _candidateSubscription?.cancel();
    _candidateSubscription = null;
    await _dataChannel?.close();
    _dataChannel = null;
    await _peerConnection?.close();
    _peerConnection = null;

    if (_activeSessionRef != null) {
      try {
        final callerCandidates = await _activeSessionRef!.collection('callerCandidates').get();
        for (final doc in callerCandidates.docs) {
          await doc.reference.delete();
        }
        final calleeCandidates = await _activeSessionRef!.collection('calleeCandidates').get();
        for (final doc in calleeCandidates.docs) {
          await doc.reference.delete();
        }
        await _activeSessionRef!.delete();
      } catch (_) {}
      _activeSessionRef = null;
    }
    _currentRoomId = null;
  }

  /// Full teardown including address background listeners
  Future<void> dispose() async {
    for (final sub in _addressListeners.values) {
      await sub.cancel();
    }
    _addressListeners.clear();
    await disposeSession();
  }
}
