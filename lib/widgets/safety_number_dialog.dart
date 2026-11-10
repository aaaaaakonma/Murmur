import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SafetyNumberDialog extends StatelessWidget {
  final String safetyNumber;
  final String? myPublicKey;
  final String? sharedSecret;

  const SafetyNumberDialog({
    super.key,
    required this.safetyNumber,
    this.myPublicKey,
    this.sharedSecret,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.verified_user_rounded, color: Colors.greenAccent),
          SizedBox(width: 8),
          Text(
            'Safety Number Verification',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Compare this number with your peer over another channel (voice, in person, or trusted chat) to verify that no man-in-the-middle is intercepting your Diffie-Hellman exchange.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF11111B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: SelectableText(
                  safetyNumber,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text(
                'Cryptographic Details',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              iconColor: Colors.white60,
              collapsedIconColor: Colors.white60,
              children: [
                if (myPublicKey != null) ...[
                  const Text('My DH Public Key (g^a mod p):',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  SelectableText(
                    myPublicKey!,
                    maxLines: 3,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                ],
                if (sharedSecret != null) ...[
                  const Text('Derived Shared Secret (S):',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  SelectableText(
                    sharedSecret!,
                    maxLines: 2,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: safetyNumber));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Safety number copied to clipboard')),
            );
          },
          child: const Text('Copy Number', style: TextStyle(color: Colors.cyanAccent)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(backgroundColor: Colors.greenAccent.shade700),
          child: const Text('Verified', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
