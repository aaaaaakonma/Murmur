import 'dart:math';

/// Represents a disposable, privacy-preserving rendezvous address
/// that a user can generate, share with a peer, and burn at will.
class UserAddress {
  final String id; // Normalized ID, e.g. "bored_9f81a7b2c3d4e5f6"
  final String label; // User-defined label, e.g. "Anon #1", "Work", "Burner"
  final bool isOneTime; // Whether to automatically burn the address after 1 chat
  final DateTime createdAt;

  UserAddress({
    required this.id,
    required this.label,
    this.isOneTime = false,
    required this.createdAt,
  });

  /// Formatted ID for display, e.g. "bored_9f81-a7b2-c3d4-e5f6"
  String get formattedId {
    if (!id.startsWith('bored_') || id.length < 22) return id;
    final hexPart = id.substring(6);
    if (hexPart.length == 16) {
      return 'bored_${hexPart.substring(0, 4)}-${hexPart.substring(4, 8)}-${hexPart.substring(8, 12)}-${hexPart.substring(12, 16)}';
    }
    return id;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'isOneTime': isOneTime,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory UserAddress.fromJson(Map<String, dynamic> json) => UserAddress(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'Disposable Alias',
        isOneTime: json['isOneTime'] as bool? ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );

  /// Generate a cryptographically secure random disposable address
  /// with 64 bits of entropy (16 hex chars)
  static String generateId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(8, (_) => rand.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'bored_$hex';
  }

  /// Normalizes user-entered address strings (stripping hyphens, colons, spaces)
  static String normalizeId(String rawInput) {
    String cleaned = rawInput.trim();
    // Replace colon with underscore if typed as bored:xxxx
    if (cleaned.startsWith('bored:')) {
      cleaned = 'bored_${cleaned.substring(6)}';
    }
    if (!cleaned.startsWith('bored_')) {
      cleaned = 'bored_$cleaned';
    }
    // Remove dashes and spaces from the hex portion
    final hexPart = cleaned.substring(6).replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toLowerCase();
    return 'bored_$hexPart';
  }
}
