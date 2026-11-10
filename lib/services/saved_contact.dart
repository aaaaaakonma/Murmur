import 'user_address.dart';

/// Represents a saved peer contact in the user's encrypted vault.
/// Allows direct 1-click calling without sharing links.
class SavedContact {
  final String id;
  final String alias;
  final String mailboxId;
  final String? fingerprint;
  final DateTime addedAt;
  final DateTime? lastDialedAt;

  SavedContact({
    required this.id,
    required this.alias,
    required this.mailboxId,
    this.fingerprint,
    required this.addedAt,
    this.lastDialedAt,
  });

  String get formattedMailboxId {
    return UserAddress(
      id: mailboxId,
      label: alias,
      createdAt: addedAt,
    ).formattedId;
  }

  SavedContact copyWith({
    String? alias,
    String? mailboxId,
    String? fingerprint,
    DateTime? lastDialedAt,
  }) {
    return SavedContact(
      id: id,
      alias: alias ?? this.alias,
      mailboxId: mailboxId ?? this.mailboxId,
      fingerprint: fingerprint ?? this.fingerprint,
      addedAt: addedAt,
      lastDialedAt: lastDialedAt ?? this.lastDialedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'alias': alias,
        'mailboxId': mailboxId,
        'fingerprint': fingerprint,
        'addedAt': addedAt.millisecondsSinceEpoch,
        'lastDialedAt': lastDialedAt?.millisecondsSinceEpoch,
      };

  factory SavedContact.fromJson(Map<String, dynamic> json) => SavedContact(
        id: json['id'] as String,
        alias: json['alias'] as String? ?? 'Peer Node',
        mailboxId: json['mailboxId'] as String,
        fingerprint: json['fingerprint'] as String?,
        addedAt: DateTime.fromMillisecondsSinceEpoch(
          json['addedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ),
        lastDialedAt: json['lastDialedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['lastDialedAt'] as int)
            : null,
      );
}
