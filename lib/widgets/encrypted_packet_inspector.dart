import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../crypto/cipher.dart';

class EncryptedPacketInspector extends StatelessWidget {
  final EncryptedPacket packet;
  final String? decryptedText;

  const EncryptedPacketInspector({
    super.key,
    required this.packet,
    this.decryptedText,
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
                Icon(Icons.lock_clock_rounded, color: Colors.cyanAccent),
                SizedBox(width: 8),
                Text(
                  'Wire Packet Inspector (WebRTC DataChannel)',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'This is the actual payload sent across the peer-to-peer WebRTC connection. Notice that message contents are 100% encrypted with AES-256 and authenticated with HMAC.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const Divider(color: Colors.white12, height: 24),
            if (decryptedText != null) ...[
              _buildField('Decrypted Plaintext:', decryptedText!, Colors.greenAccent),
              const SizedBox(height: 12),
            ],
            _buildField('Initialization Vector (IV - 16 bytes Base64):', packet.ivBase64, Colors.amberAccent),
            const SizedBox(height: 12),
            _buildField('AES-256 Ciphertext (Base64):', packet.ciphertextBase64, Colors.lightBlueAccent),
            const SizedBox(height: 12),
            _buildField('HMAC-SHA256 Authentication Tag:', packet.hmacHex, Colors.purpleAccent),
            const SizedBox(height: 12),
            _buildField(
              'Timestamp:',
              DateTime.fromMillisecondsSinceEpoch(packet.timestamp).toIso8601String(),
              Colors.white70,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                label: const Text('Copy Raw JSON Packet', style: TextStyle(color: Colors.white70)),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: packet.toWireJson()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Raw packet JSON copied')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String title, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF11111B),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            value,
            style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: valueColor),
          ),
        ),
      ],
    );
  }
}
