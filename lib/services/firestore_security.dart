import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Thrown when a client action violates the rate limiting policy.
class RateLimitException implements Exception {
  final String action;
  final int retryAfterSeconds;
  final String message;

  RateLimitException({
    required this.action,
    required this.retryAfterSeconds,
    required this.message,
  });

  @override
  String toString() => 'RateLimitException: $message (Retry after $retryAfterSeconds s)';
}

/// Token bucket algorithm for rate-limiting Firestore reads & writes.
class TokenBucket {
  final double capacity;
  final double refillPerSecond;
  double _tokens;
  DateTime _lastRefill;

  TokenBucket({required this.capacity, required this.refillPerSecond})
      : _tokens = capacity,
        _lastRefill = DateTime.now();

  void _refill() {
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastRefill).inMilliseconds;
    if (elapsedMs > 0) {
      final added = (elapsedMs / 1000.0) * refillPerSecond;
      _tokens = (_tokens + added).clamp(0.0, capacity);
      _lastRefill = now;
    }
  }

  bool tryConsume({double cost = 1.0}) {
    _refill();
    if (_tokens >= cost) {
      _tokens -= cost;
      return true;
    }
    return false;
  }

  int get waitSecondsForNextToken {
    _refill();
    if (_tokens >= 1.0) return 0;
    final needed = 1.0 - _tokens;
    return (needed / refillPerSecond).ceil();
  }
}

/// Manages rate limiting across all Firestore operations to stop bots & runaway loops.
class FirestoreRateLimiter {
  static final FirestoreRateLimiter _instance = FirestoreRateLimiter._internal();
  factory FirestoreRateLimiter() => _instance;
  FirestoreRateLimiter._internal();

  final Map<String, TokenBucket> _buckets = {
    // Max 5 address provisions per minute (refill 1 every 12 seconds)
    'create_address': TokenBucket(capacity: 5, refillPerSecond: 5.0 / 60.0),
    // Max 3 call initiations per 10 seconds (refill 1 every 3.3 seconds)
    'call_address': TokenBucket(capacity: 3, refillPerSecond: 0.3),
    // Max 5 answers per 10 seconds
    'answer_call': TokenBucket(capacity: 5, refillPerSecond: 0.5),
    // Max 3 rooms created per 30 seconds
    'create_room': TokenBucket(capacity: 3, refillPerSecond: 3.0 / 30.0),
    // Max 5 rooms joined per 30 seconds
    'join_room': TokenBucket(capacity: 5, refillPerSecond: 5.0 / 30.0),
    // Max 20 ICE candidates trickled per second
    'trickle_candidate': TokenBucket(capacity: 20, refillPerSecond: 10.0),
  };

  /// Verify rate limit before executing action, or throw [RateLimitException]
  void enforce(String action) {
    final bucket = _buckets[action];
    if (bucket == null) return;

    if (!bucket.tryConsume()) {
      final waitSec = bucket.waitSecondsForNextToken;
      throw RateLimitException(
        action: action,
        retryAfterSeconds: waitSec > 0 ? waitSec : 1,
        message: 'Rate limit exceeded for "$action". Throttling automated/bot requests. Please wait $waitSec seconds.',
      );
    }
  }

  /// Reset all buckets (primarily for testing)
  void reset() {
    _buckets.forEach((key, bucket) {
      bucket._tokens = bucket.capacity;
      bucket._lastRefill = DateTime.now();
    });
  }
}

/// Result of a completed client Proof-of-Work challenge
class PoWResult {
  final int nonce;
  final int timestamp;
  final String hashHex;
  final int difficultyBits;

  PoWResult({
    required this.nonce,
    required this.timestamp,
    required this.hashHex,
    required this.difficultyBits,
  });

  Map<String, dynamic> toJson() => {
        'powNonce': nonce,
        'powTimestamp': timestamp,
        'powHash': hashHex,
      };
}

/// Lightweight Proof-of-Work engine for stopping automated bot scripts and scrapers.
/// Legitimate users spend ~10ms computing a 12-bit challenge.
/// Automated spam bots attempting 10,000 requests/sec are halted by CPU saturation.
class AntiBotProofOfWork {
  static const int defaultDifficultyBits = 12; // 3 hex zeros ('000')

  /// Solve Proof of Work challenge
  static Future<PoWResult> solve({
    required String challengeId,
    int difficultyBits = defaultDifficultyBits,
  }) async {
    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    final String prefix = '0' * (difficultyBits ~/ 4);
    int nonce = 0;

    while (true) {
      final input = '$challengeId:$timestamp:$nonce';
      final digest = sha256.convert(utf8.encode(input)).toString();

      if (digest.startsWith(prefix)) {
        return PoWResult(
          nonce: nonce,
          timestamp: timestamp,
          hashHex: digest,
          difficultyBits: difficultyBits,
        );
      }
      nonce++;

      // Yield event loop every 5000 iterations to keep UI responsive
      if (nonce % 5000 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// Verify a Proof of Work payload
  static bool verify({
    required String challengeId,
    required int nonce,
    required int timestamp,
    required String hashHex,
    int difficultyBits = defaultDifficultyBits,
    int maxAgeSeconds = 300,
  }) {
    // 1. Freshness check: timestamp must be within 5 minutes
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - timestamp).abs() > maxAgeSeconds * 1000) {
      return false;
    }

    // 2. Target prefix check
    final String prefix = '0' * (difficultyBits ~/ 4);
    if (!hashHex.startsWith(prefix)) {
      return false;
    }

    // 3. Hash computation check
    final input = '$challengeId:$timestamp:$nonce';
    final computed = sha256.convert(utf8.encode(input)).toString();
    return computed == hashHex;
  }
}

/// Validates Firestore document payloads to prevent injection of malicious or oversized data.
class FirestorePayloadValidator {
  static const int maxSdpBytes = 16384;
  static const int maxCandidateBytes = 1024;
  static const int minAddressLen = 8;
  static const int maxAddressLen = 64;

  static final RegExp _validIdRegex = RegExp(r'^[a-zA-Z0-9_\-:]+$');

  /// Validate address or room ID
  static void validateId(String id, {String name = 'ID'}) {
    final clean = id.trim();
    if (clean.length < minAddressLen || clean.length > maxAddressLen) {
      throw ArgumentError('$name must be between $minAddressLen and $maxAddressLen characters.');
    }
    if (!_validIdRegex.hasMatch(clean)) {
      throw ArgumentError('$name contains invalid characters. Only alphanumeric, dashes, colons, and underscores allowed.');
    }
  }

  /// Validate WebRTC SDP payload
  static void validateSdp(String sdp) {
    if (sdp.trim().isEmpty) {
      throw ArgumentError('SDP cannot be empty.');
    }
    if (utf8.encode(sdp).length > maxSdpBytes) {
      throw ArgumentError('SDP payload exceeds maximum allowed size of $maxSdpBytes bytes.');
    }
  }

  /// Validate ICE candidate string
  static void validateCandidate(String candidate) {
    if (candidate.trim().isEmpty) {
      throw ArgumentError('ICE candidate cannot be empty.');
    }
    if (utf8.encode(candidate).length > maxCandidateBytes) {
      throw ArgumentError('ICE candidate payload exceeds maximum allowed size.');
    }
  }
}
