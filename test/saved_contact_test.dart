import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bored_p2p_chat/services/saved_contact.dart';
import 'package:bored_p2p_chat/services/presence_history_store.dart';

void main() {
  group('SavedContact Peer Directory Tests', () {
    test('serialization roundtrip preserves all fields', () {
      final now = DateTime.now();
      final contact = SavedContact(
        id: 'c_12345',
        alias: 'Alice (HQ Relay)',
        mailboxId: 'bored_8f3a9e1c4b2a7182',
        fingerprint: 'fp: 7f0a:e29b:11c8',
        addedAt: now,
        lastDialedAt: now,
      );

      final json = contact.toJson();
      final restored = SavedContact.fromJson(json);

      expect(restored.id, equals('c_12345'));
      expect(restored.alias, equals('Alice (HQ Relay)'));
      expect(restored.mailboxId, equals('bored_8f3a9e1c4b2a7182'));
      expect(restored.fingerprint, equals('fp: 7f0a:e29b:11c8'));
      expect(restored.addedAt.millisecondsSinceEpoch, equals(now.millisecondsSinceEpoch));
      expect(restored.lastDialedAt?.millisecondsSinceEpoch, equals(now.millisecondsSinceEpoch));
    });

    test('formattedMailboxId outputs hyphen-grouped hex', () {
      final contact = SavedContact(
        id: 'c_1',
        alias: 'Bob',
        mailboxId: 'bored_8f3a9e1c4b2a7182',
        addedAt: DateTime.now(),
      );

      expect(contact.formattedMailboxId, equals('bored_8f3a-9e1c-4b2a-7182'));
    });

    test('PresenceHistoryStore persists and loads saved contacts', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await PresenceHistoryStore.create();

      expect(store.loadContacts(), isEmpty);

      final c1 = SavedContact(
        id: 'c_1',
        alias: 'Alice',
        mailboxId: 'bored_1111222233334444',
        addedAt: DateTime.now(),
      );
      final c2 = SavedContact(
        id: 'c_2',
        alias: 'Charlie',
        mailboxId: 'bored_5555666677778888',
        addedAt: DateTime.now(),
      );

      await store.saveContacts([c1, c2]);

      final loaded = store.loadContacts();
      expect(loaded.length, equals(2));
      expect(loaded[0].alias, equals('Alice'));
      expect(loaded[1].alias, equals('Charlie'));
      expect(loaded[1].mailboxId, equals('bored_5555666677778888'));
    });
  });
}
