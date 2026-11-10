import 'package:flutter/material.dart';
import '../crypto/deniable_cipher.dart';

class DeniablePacketInspector extends StatelessWidget {
  final DeniablePacket? packet;
  final String? decryptedText;
  final List<DisclosedMacKey> publishedMacKeys;
  final bool isPresenceActive;

  const DeniablePacketInspector({
    super.key,
    this.packet,
    this.decryptedText,
    required this.publishedMacKeys,
    required this.isPresenceActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF181825),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.security_update_good, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text(
                  'Deniability & Presence Inspector',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isPresenceActive ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isPresenceActive ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
              child: Row(
                children: [
                  Icon(isPresenceActive ? Icons.lock_open : Icons.lock_outline,
                      color: isPresenceActive ? Colors.greenAccent : Colors.redAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isPresenceActive
                          ? '2-of-2 Presence Active: K = s₁ ⊕ s₂ reconstructed in RAM. Seized device offline holds only one share s₁.'
                          : 'Presence Inactive: History key K is zeroized.',
                      style: TextStyle(
                        color: isPresenceActive ? Colors.greenAccent : Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'OTR-Style Disclosed MAC Keys (Repudiation):',
              style: TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Once MAC keys are published in the clear, anyone on the Internet could have forged valid HMAC tags for these messages, providing mathematical plausible deniability.',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 8),
            if (publishedMacKeys.isEmpty)
              const Text('No disclosed MAC keys published yet (revealed on next message).',
                  style: TextStyle(color: Colors.white30, fontSize: 11))
            else
              ...publishedMacKeys.map(
                (k) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF11111B),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Text('Seq #${k.seq}: ', style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
                      Expanded(
                        child: Text(
                          k.keyHex,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace', color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (packet != null) ...[
              const Divider(color: Colors.white12, height: 24),
              const Text('Selected Wire Packet:',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (decryptedText != null) ...[
                _buildField('Decrypted Plaintext:', decryptedText!, Colors.greenAccent),
                const SizedBox(height: 8),
              ],
              _buildField('Seq:', packet!.seq.toString(), Colors.amberAccent),
              const SizedBox(height: 8),
              _buildField('Nonce (Base64):', packet!.nonceBase64, Colors.cyanAccent),
              const SizedBox(height: 8),
              _buildField('Ciphertext (Base64):', packet!.ciphertextBase64, Colors.lightBlueAccent),
              const SizedBox(height: 8),
              _buildField('Symmetric HMAC (Hex):', packet!.hmacHex, Colors.purpleAccent),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildField(String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF11111B),
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(value, style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: color)),
        ),
      ],
    );
  }
}
