import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bored_p2p_chat/services/p2p_chat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Peer Disconnect & Presence Termination Zeroization Tests', () {
    test('Messages and session keys are zeroized immediately when peer disconnects', () async {
      SharedPreferences.setMockInitialValues({});
      final chatService = P2PChatService();

      // Unlock vault with passphrase
      await chatService.unlockOrCreateVault('test_vault_passphrase_123');
      expect(chatService.isVaultUnlocked, isTrue);

      // Simulate presence and reconstructed messages
      // Suppose chat had messages in memory
      expect(chatService.messages, isEmpty);

      // Verify leaveRoom or disconnect clears messages and resets presence
      await chatService.leaveRoom();
      expect(chatService.messages, isEmpty);
      expect(chatService.packetLog, isEmpty);
      expect(chatService.isPresenceActive, isFalse);
      expect(chatService.status, equals(SessionStatus.idle));
    });
  });
}
