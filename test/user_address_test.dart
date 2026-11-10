import 'package:flutter_test/flutter_test.dart';
import 'package:bored_p2p_chat/services/user_address.dart';

void main() {
  group('UserAddress Disposable Alias Tests', () {
    test('generateId produces valid 64-bit random bored_ prefixed hex', () {
      final id1 = UserAddress.generateId();
      final id2 = UserAddress.generateId();

      expect(id1.startsWith('bored_'), isTrue);
      expect(id2.startsWith('bored_'), isTrue);
      expect(id1.length, equals(22)); // 'bored_' (6) + 16 hex chars
      expect(id1, isNot(equals(id2)));
    });

    test('formattedId groups hex characters in 4-character blocks', () {
      final address = UserAddress(
        id: 'bored_7a9f3c218b4ed05a',
        label: 'Test Alias',
        createdAt: DateTime.now(),
      );

      expect(address.formattedId, equals('bored_7a9f-3c21-8b4e-d05a'));
    });

    test('normalizeId handles inputs with dashes, colons, or spaces', () {
      expect(
        UserAddress.normalizeId('bored_7a9f-3c21-8b4e-d05a'),
        equals('bored_7a9f3c218b4ed05a'),
      );
      expect(
        UserAddress.normalizeId('bored:7a9f3c218b4ed05a'),
        equals('bored_7a9f3c218b4ed05a'),
      );
      expect(
        UserAddress.normalizeId('7a9f-3c21-8b4e-d05a'),
        equals('bored_7a9f3c218b4ed05a'),
      );
    });

    test('serialization roundtrip preserves properties', () {
      final address = UserAddress(
        id: 'bored_7a9f3c218b4ed05a',
        label: 'Burner Address',
        isOneTime: true,
        createdAt: DateTime.now(),
      );

      final json = address.toJson();
      final restored = UserAddress.fromJson(json);

      expect(restored.id, equals(address.id));
      expect(restored.label, equals(address.label));
      expect(restored.isOneTime, isTrue);
    });
  });
}
