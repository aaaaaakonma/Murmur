import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../crypto/triple_dh.dart';

class TripleDhInspectorDialog extends StatefulWidget {
  final TripleDhTelemetry? telemetry;
  final List<TripleDhLogEntry> logs;
  final bool isSecure;
  final bool isInRoom;

  const TripleDhInspectorDialog({
    super.key,
    required this.telemetry,
    required this.logs,
    required this.isSecure,
    required this.isInRoom,
  });

  @override
  State<TripleDhInspectorDialog> createState() => _TripleDhInspectorDialogState();
}

class _TripleDhInspectorDialogState extends State<TripleDhInspectorDialog> {
  bool _copied = false;

  void _copyAllLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== TRIPLE-DH (3DH) CONNECTION TELEMETRY & AUDIT LOG ===');
    if (widget.telemetry != null) {
      final t = widget.telemetry!;
      buffer.writeln('Handshake Latency: ${t.totalHandshakeLatencyMs.toStringAsFixed(2)} ms');
      buffer.writeln('Crypto Compute: ${t.cryptoComputeTimeMs.toStringAsFixed(2)} ms');
      buffer.writeln('Wire Transit: ${t.wireTransitLatencyMs?.toStringAsFixed(2) ?? "N/A"} ms');
      buffer.writeln('Local Identity (IK): ${t.localIdentityPubHex ?? "N/A"}');
      buffer.writeln('Remote Identity (IK): ${t.remoteIdentityPubHex ?? "N/A"}');
      buffer.writeln('Local Ephemeral (EK): ${t.localEphemeralPubHex ?? "N/A"}');
      buffer.writeln('Remote Ephemeral (EK): ${t.remoteEphemeralPubHex ?? "N/A"}');
      buffer.writeln('Breakdown: DH1=${t.dh1TimeMs.toStringAsFixed(2)}ms, DH2=${t.dh2TimeMs.toStringAsFixed(2)}ms, DH3=${t.dh3TimeMs.toStringAsFixed(2)}ms, HKDF=${t.hkdfTimeMs.toStringAsFixed(2)}ms');
      buffer.writeln('-------------------------------------------------------');
    }
    for (final log in widget.logs) {
      buffer.writeln(log.toString());
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('3DH connection logs copied to clipboard'),
        backgroundColor: Color(0xFF10B981),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.telemetry;
    final hasTelemetry = t != null && t.isCompleted;

    return Dialog(
      backgroundColor: const Color(0xFF0E0E11),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: Color(0xFF27272A)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF141418),
                border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: widget.isSecure
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      Icons.bolt,
                      size: 16,
                      color: widget.isSecure ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Triple-DH (3DH) Handshake Telemetry',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.isSecure
                              ? 'Mutual Authenticated • X25519 ECDH + HKDF-SHA256'
                              : (widget.isInRoom ? 'Negotiating 3DH Wire Handshake...' : 'Channel Standby'),
                          style: TextStyle(
                            color: widget.isSecure ? const Color(0xFF10B981) : const Color(0xFFA1A1AA),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFFA1A1AA)),
                    splashRadius: 18,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Modal Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Latency Summary Metrics Grid
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            label: '3DH TOTAL LATENCY',
                            value: hasTelemetry
                                ? '${t.totalHandshakeLatencyMs.toStringAsFixed(1)} ms'
                                : (widget.isInRoom ? 'Exchanging...' : 'Standby'),
                            subtext: 'Wire & handshake round-trip',
                            icon: Icons.speed,
                            accentColor: const Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricCard(
                            label: 'CRYPTO COMPUTE',
                            value: t != null
                                ? '${t.cryptoComputeTimeMs.toStringAsFixed(2)} ms'
                                : (widget.isInRoom ? 'Calculating...' : '0.00 ms'),
                            subtext: '3x X25519 + HKDF-SHA256',
                            icon: Icons.memory,
                            accentColor: const Color(0xFF38BDF8),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricCard(
                            label: 'WIRE TRANSIT',
                            value: t?.wireTransitLatencyMs != null
                                ? '${t!.wireTransitLatencyMs!.toStringAsFixed(1)} ms'
                                : (hasTelemetry ? '< 1 ms' : 'N/A'),
                            subtext: 'SCTP DataChannel transit',
                            icon: Icons.swap_horiz,
                            accentColor: const Color(0xFFA78BFA),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Crypto Breakdown details
                    if (t != null) ...[
                      const Text(
                        'CRYPTOGRAPHIC EXECUTION BREAKDOWN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: Color(0xFF71717A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121215),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xFF27272A)),
                        ),
                        child: Column(
                          children: [
                            _buildBreakdownRow('Ephemeral Key Generation', '${t.ephemeralGenTimeMs.toStringAsFixed(2)} ms', 'X25519 CSPRNG'),
                            _buildBreakdownRow('DH1 = DH(ik, EK)', '${t.dh1TimeMs.toStringAsFixed(2)} ms', 'Mutual identity bind'),
                            _buildBreakdownRow('DH2 = DH(ek, IK)', '${t.dh2TimeMs.toStringAsFixed(2)} ms', 'Forward secrecy bind'),
                            _buildBreakdownRow('DH3 = DH(ek, EK)', '${t.dh3TimeMs.toStringAsFixed(2)} ms', 'Ephemeral-only secrecy'),
                            _buildBreakdownRow('HKDF-SHA256 Master Key', '${t.hkdfTimeMs.toStringAsFixed(2)} ms', 'Transcript-bound HKDF'),
                            if (t.remoteIdentityPubHex != null) ...[
                              const Divider(color: Color(0xFF27272A), height: 16),
                              _buildKeyRow('Remote Identity (IK)', t.remoteIdentityPubHex!),
                            ],
                            if (t.localEphemeralPubHex != null) ...[
                              const SizedBox(height: 4),
                              _buildKeyRow('Local Ephemeral (EK)', t.localEphemeralPubHex!),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Logs Header + Copy Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '3DH CONNECTION EVENT LOG',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                                color: Color(0xFF71717A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF27272A),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                '${widget.logs.length} entries',
                                style: const TextStyle(
                                  fontFamily: 'JetBrains Mono',
                                  fontSize: 10,
                                  color: Color(0xFFA1A1AA),
                                ),
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: widget.logs.isNotEmpty ? _copyAllLogs : null,
                          borderRadius: BorderRadius.circular(2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF18181D),
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: const Color(0xFF27272A)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _copied ? Icons.check : Icons.copy,
                                  size: 12,
                                  color: _copied ? const Color(0xFF10B981) : const Color(0xFFA1A1AA),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _copied ? 'Copied' : 'Copy Logs',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _copied ? const Color(0xFF10B981) : const Color(0xFFA1A1AA),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Monospace Terminal Box
                    Container(
                      constraints: const BoxConstraints(minHeight: 180, maxHeight: 320),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF09090C),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFF27272A)),
                      ),
                      child: widget.logs.isEmpty
                          ? const Center(
                              child: Text(
                                'No 3DH connection logs yet. Start or join a peer session.',
                                style: TextStyle(
                                  fontFamily: 'JetBrains Mono',
                                  fontSize: 11,
                                  color: Color(0xFF52525B),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: widget.logs.length,
                              itemBuilder: (ctx, idx) => _buildLogItem(widget.logs[idx]),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // Modal Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF141418),
                border: Border(top: BorderSide(color: Color(0xFF27272A))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Forward Secrecy • Repudiation • Zero Server Signatures',
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      color: Color(0xFF71717A),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF27272A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                      elevation: 0,
                    ),
                    child: const Text('Close', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required String subtext,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF121215),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: Color(0xFF71717A),
                ),
              ),
              Icon(icon, size: 12, color: accentColor),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF52525B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(String step, String duration, String note) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(step, style: const TextStyle(fontSize: 11, color: Color(0xFFD4D4D8))),
              const SizedBox(width: 6),
              Text('($note)', style: const TextStyle(fontSize: 10, color: Color(0xFF71717A))),
            ],
          ),
          Text(
            duration,
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF38BDF8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyRow(String label, String hexKey) {
    final short = hexKey.length > 28 ? '${hexKey.substring(0, 14)}...${hexKey.substring(hexKey.length - 12)}' : hexKey;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF71717A))),
        Text(
          short,
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 10,
            color: Color(0xFFA1A1AA),
          ),
        ),
      ],
    );
  }

  Widget _buildLogItem(TripleDhLogEntry entry) {
    Color stageBg;
    Color stageFg;

    switch (entry.stage) {
      case 'VERIFIED':
        stageBg = const Color(0xFF064E3B);
        stageFg = const Color(0xFF34D399);
        break;
      case 'DH_COMPUTE':
      case 'DH_START':
      case 'KEYGEN':
      case 'KEYGEN_DONE':
        stageBg = const Color(0xFF0C4A6E);
        stageFg = const Color(0xFF38BDF8);
        break;
      case 'TX_HANDSHAKE':
      case 'TX_SHARE':
        stageBg = const Color(0xFF312E81);
        stageFg = const Color(0xFF818CF8);
        break;
      case 'RX_HANDSHAKE':
      case 'RX_SHARE':
        stageBg = const Color(0xFF4C1D95);
        stageFg = const Color(0xFFA78BFA);
        break;
      case 'DISCONNECTED':
        stageBg = const Color(0xFF7F1D1D);
        stageFg = const Color(0xFFF87171);
        break;
      default:
        stageBg = const Color(0xFF27272A);
        stageFg = const Color(0xFFA1A1AA);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.formattedTimestamp,
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 10,
              color: Color(0xFF52525B),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: stageBg,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              entry.stage,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: stageFg,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.message,
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 10,
                    color: Color(0xFFE4E4E7),
                  ),
                ),
                if (entry.detail != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    entry.detail!,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 9,
                      color: Color(0xFF71717A),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (entry.durationMs != null) ...[
            const SizedBox(width: 6),
            Text(
              '+${entry.durationMs!.toStringAsFixed(1)}ms',
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 9,
                color: Color(0xFF38BDF8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
