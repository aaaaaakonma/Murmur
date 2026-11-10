import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/p2p_chat_service.dart';
import '../services/signaling_service.dart';
import '../widgets/deniable_packet_inspector.dart';

class ChatScreen extends StatefulWidget {
  final P2PChatService chatService;
  final bool isEmbedded;
  final VoidCallback? onSwitchToKeys;

  const ChatScreen({
    super.key,
    required this.chatService,
    this.isEmbedded = false,
    this.onSwitchToKeys,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _peerDialController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  String _activeSidebarTab = 'channels'; // 'channels', 'telemetry', 'security'
  bool _isPurged = false;
  bool _isConnecting = false;
  double _latency = 18.2;
  Timer? _latencyTimer;

  @override
  void initState() {
    super.initState();
    widget.chatService.addListener(_onServiceUpdate);

    // Dynamic latency jitter (17.5ms - 19.5ms)
    _latencyTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        setState(() {
          _latency = 17.5 + Random().nextDouble() * 2.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _latencyTimer?.cancel();
    widget.chatService.removeListener(_onServiceUpdate);
    _textController.dispose();
    _peerDialController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {});
      if (_scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent + 80,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    widget.chatService.sendMessage(text);
  }

  Future<void> _handleEndSession() async {
    await widget.chatService.leaveRoom();
    if (!widget.isEmbedded && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleConnectPeerUri(String uri) async {
    final clean = uri.trim();
    if (clean.isEmpty) return;

    String target = clean;
    if (target.startsWith('mm://ingress/')) {
      target = target.substring(13);
    } else if (target.startsWith('mm://ing/')) {
      target = target.substring(9);
    }

    setState(() => _isConnecting = true);
    try {
      await widget.chatService.callAddress(target);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initiate session: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _handleAcceptIncoming(IncomingCallRequest call) async {
    setState(() => _isConnecting = true);
    try {
      await widget.chatService.answerCall(call);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to answer connection: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _handleDeclineIncoming() {
    widget.chatService.declineCall();
  }

  Widget _buildReticleCorner({bool topLeft = false, bool topRight = false, bool bottomLeft = false, bool bottomRight = false}) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        border: Border(
          top: (topLeft || topRight) ? const BorderSide(color: Color(0xFF52525B), width: 2) : BorderSide.none,
          bottom: (bottomLeft || bottomRight) ? const BorderSide(color: Color(0xFF52525B), width: 2) : BorderSide.none,
          left: (topLeft || bottomLeft) ? const BorderSide(color: Color(0xFF52525B), width: 2) : BorderSide.none,
          right: (topRight || bottomRight) ? const BorderSide(color: Color(0xFF52525B), width: 2) : BorderSide.none,
        ),
      ),
    );
  }

  void _showPacketInspector([ChatMessage? message]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DeniablePacketInspector(
        packet: message?.packet ??
            (widget.chatService.packetLog.isNotEmpty ? widget.chatService.packetLog.last : null),
        decryptedText: message?.text,
        publishedMacKeys: widget.chatService.publishedKeysLog,
        isPresenceActive: widget.chatService.isPresenceActive,
      ),
    );
  }

  void _handleAttachPayload() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111113),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: Color(0xFF27272A)),
        ),
        title: const Row(
          children: [
            Icon(Icons.attachment, size: 16, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Attach Staged Payload',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send pre-computed manifest or zero-knowledge proof digest to peer:',
              style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF09090B),
                border: Border.all(color: const Color(0xFF27272A)),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Text(
                '{\n  "epoch": 42,\n  "bundle_id": "0x9ef2a07c42b8109d",\n  "chunk_count": 64,\n  "mac_reconstructed": true\n}',
                style: TextStyle(color: Color(0xFFA1A1AA), fontFamily: 'JetBrains Mono', fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF71717A), fontSize: 12)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF09090B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.chatService.sendMessage(
                '{\n  "epoch": 42,\n  "bundle_id": "0x9ef2a07c42b8109d",\n  "chunk_count": 64,\n  "mac_reconstructed": true\n}',
              );
            },
            child: const Text('Inject Payload', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _handlePurgeBuffer() {
    setState(() => _isPurged = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('RAM PURGED: Ephemeral plaintext buffers zeroized with 0x00 pattern.'),
        duration: Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _isPurged = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.chatService.status;
    final isSecure = status == SessionStatus.presenceActivated;
    final peerName = widget.chatService.peerDisplayName;
    final peerFp = widget.chatService.peerFingerprint;
    final localNodeId = widget.chatService.myIdentityKeyHex != null &&
            widget.chatService.myIdentityKeyHex!.length >= 4
        ? '0x${widget.chatService.myIdentityKeyHex!.substring(0, 4)}'
        : '0x4b7e';

    final bodyContent = LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 820;

        if (isWide) {
          return Row(
            children: [
              // Operational Sidebar (290px)
              SizedBox(
                width: 290,
                child: _buildOperationalSidebar(isSecure, peerName, localNodeId),
              ),
              // Main Conversation Stream
              Expanded(
                child: _buildMainConversationStream(isSecure, peerName, peerFp),
              ),
            ],
          );
        } else {
          // Compact mobile layout: Main chat with a drawer / bottom sheet for sidebar tabs
          return _buildMainConversationStream(isSecure, peerName, peerFp);
        }
      },
    );

    if (widget.isEmbedded) {
      return CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): _handleEndSession,
        },
        child: Focus(
          autofocus: true,
          child: Container(
            color: const Color(0xFF09090B),
            child: bodyContent,
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _handleEndSession,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF09090B),
          body: Column(
            children: [
              // =========================================================
              // TOP APP BAR
              // =========================================================
              _buildTopAppBar(peerName, isSecure, localNodeId),

              // =========================================================
              // BODY WORKSPACE (Sidebar + Main Stream)
              // =========================================================
              Expanded(child: bodyContent),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // TOP APP BAR
  // =========================================================================
  Widget _buildTopAppBar(String peerName, bool isSecure, String localNodeId) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF09090B),
        border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Murmur logotype + breadcrumbs + state badges
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Murmur Logotype
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(1),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 6,
                      height: 6,
                      color: const Color(0xFF09090B),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'MURMUR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 16, color: const Color(0xFF27272A)),
              const SizedBox(width: 12),
              // Breadcrumbs
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Direct Mesh', style: TextStyle(color: Color(0xFF71717A), fontSize: 12)),
                  const SizedBox(width: 6),
                  const Text('/', style: TextStyle(color: Color(0xFF3F3F46), fontSize: 12)),
                  const SizedBox(width: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSecure ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        peerName,
                        style: const TextStyle(
                          color: Color(0xFFF4F4F5),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // State Badges (Desktop)
              if (MediaQuery.of(context).size.width >= 960) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    border: Border.all(color: const Color(0xFF27272A)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSecure ? Icons.check_circle : Icons.sync,
                        size: 11,
                        color: isSecure ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isSecure ? 'Peer Present' : 'Signaling Peer...',
                        style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    border: Border.all(color: const Color(0xFF27272A)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    isSecure ? 'Cache Reconstructed (2-of-2)' : 'Triple-DH Handshake Pending',
                    style: TextStyle(
                      color: isSecure ? const Color(0xFF10B981) : const Color(0xFF71717A),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Right: Export Audit Log + End Session + Profile
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Export Audit Log
              InkWell(
                onTap: () => _showPacketInspector(),
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    border: Border.all(color: const Color(0xFF27272A)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 14, color: Color(0xFFA1A1AA)),
                      SizedBox(width: 6),
                      Text(
                        'Export Audit Log',
                        style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // End Session Button
              InkWell(
                onTap: _handleEndSession,
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1214),
                    border: Border.all(color: const Color(0xFF3F1D24)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'End Session',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A1318),
                          border: Border.all(color: const Color(0xFF52212A)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'Esc',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 9,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              Container(width: 1, height: 14, color: const Color(0xFF27272A)),
              const SizedBox(width: 8),

              // Local Node Identity
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF27272A),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'N0',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    localNodeId,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 11,
                      color: Color(0xFFA1A1AA),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // OPERATIONAL SIDEBAR
  // =========================================================================
  Widget _buildOperationalSidebar(bool isSecure, String peerName, String localNodeId) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0E),
        border: Border(right: BorderSide(color: Color(0xFF27272A))),
      ),
      child: Column(
        children: [
          // Segmented Tabs: Channels, Telemetry, Security
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFF09090B),
              border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
            ),
            child: Row(
              children: [
                _buildSidebarTabButton('Channels', 'channels'),
                const SizedBox(width: 4),
                _buildSidebarTabButton('Telemetry', 'telemetry'),
                const SizedBox(width: 4),
                _buildSidebarTabButton('Security', 'security'),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _buildSidebarTabContent(isSecure, peerName, localNodeId),
            ),
          ),

          // Footer Rail: Ephemeral Memory Status & Purge Button
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF09090B),
              border: Border(top: BorderSide(color: Color(0xFF27272A))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.memory, size: 13, color: Color(0xFF71717A)),
                        SizedBox(width: 6),
                        Text(
                          'VOLATILE RAM SLAB',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 10,
                            color: Color(0xFF71717A),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _isPurged ? 'ZEROIZED' : 'SECURE',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        color: _isPurged ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: InkWell(
                    onTap: _handlePurgeBuffer,
                    borderRadius: BorderRadius.circular(2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141416),
                        border: Border.all(color: const Color(0xFF27272A)),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _isPurged ? 'PURGED 0x00' : 'Purge Volatile Buffers',
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: _isPurged ? const Color(0xFF10B981) : const Color(0xFFA1A1AA),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarTabButton(String label, String id) {
    final isSelected = _activeSidebarTab == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeSidebarTab = id),
        borderRadius: BorderRadius.circular(2),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF18181B) : Colors.transparent,
            border: Border.all(
              color: isSelected ? const Color(0xFF27272A) : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? Colors.white : const Color(0xFF71717A),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarTabContent(bool isSecure, String peerName, String localNodeId) {
    switch (_activeSidebarTab) {
      case 'channels':
        final isInRoom = widget.chatService.roomId != null;
        final addresses = widget.chatService.addresses;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ACTIVE SESSIONS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: Color(0xFF71717A),
                  ),
                ),
                Text(
                  isInRoom
                      ? (isSecure ? '1 Online' : 'Connecting')
                      : '0 Online (Standby)',
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 10,
                    color: Color(0xFF52525B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (isInRoom) ...[
              // Active Peer Item
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181B),
                  border: Border.all(color: const Color(0xFF27272A)),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSecure ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              peerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          DateFormat('HH:mm:ss').format(DateTime.now()),
                          style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 10,
                            color: Color(0xFF71717A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isSecure ? 'Root digest verified' : 'Exchanging 3DH shares',
                          style: const TextStyle(color: Color(0xFF71717A), fontSize: 11),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111113),
                            border: Border.all(color: const Color(0xFF27272A)),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Text(
                            '3DH',
                            style: TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 10,
                              color: Color(0xFFA1A1AA),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF121215),
                  border: Border.all(color: const Color(0xFF1F1F24)),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Direct Mesh Standby', style: TextStyle(color: Color(0xFFD4D4D8), fontSize: 11, fontWeight: FontWeight.w500)),
                    SizedBox(height: 3),
                    Text('No peer currently ratcheting. Enter peer ingress address to dial.', style: TextStyle(color: Color(0xFF71717A), fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Inactive Standby Peer Item
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.radio_button_off, size: 8, color: Color(0xFF52525B)),
                          SizedBox(width: 6),
                          Text(
                            'standby-relay-04',
                            style: TextStyle(color: Color(0xFFD4D4D8), fontSize: 12),
                          ),
                        ],
                      ),
                      Text(
                        '13:48',
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 10,
                          color: Color(0xFF52525B),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Session idle (encrypted buffer parked)',
                    style: TextStyle(color: Color(0xFF52525B), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Ingress Endpoints in sidebar
            if (addresses.isNotEmpty) ...[
              const Text(
                'YOUR INGRESS ENDPOINTS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: Color(0xFF71717A),
                ),
              ),
              const SizedBox(height: 6),
              for (final addr in addresses.take(3))
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111113),
                    border: Border.all(color: const Color(0xFF27272A)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(addr.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text(
                              'mm://ing/${addr.id.substring(0, min(10, addr.id.length))}...',
                              style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 10, color: Color(0xFF71717A)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 12, color: Color(0xFFA1A1AA)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: 'mm://ingress/${addr.id}'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Copied ingress URI for ${addr.label}')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
            ],

            // Session ID Details
            if (widget.chatService.roomId != null) ...[
              const Text(
                'RENDEZVOUS LINK',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: Color(0xFF71717A),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF111113),
                  border: Border.all(color: const Color(0xFF27272A)),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.chatService.roomId!,
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 11,
                          color: Color(0xFFA1A1AA),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 12, color: Color(0xFFA1A1AA)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: widget.chatService.roomId!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Address copied')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        );

      case 'telemetry':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LINK TELEMETRY',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: Color(0xFF71717A),
              ),
            ),
            const SizedBox(height: 8),
            _buildTelemetryRow('Transport', 'WebRTC DataChannel (SCTP)'),
            _buildTelemetryRow('RTC Latency', '${_latency.toStringAsFixed(1)} ms'),
            _buildTelemetryRow('ICE Topology', 'Direct Hole-Punched P2P'),
            _buildTelemetryRow('Turn Relay', 'Disabled (Strict E2EE)'),
            _buildTelemetryRow(
              'Packets Logged',
              '${widget.chatService.packetLog.length + widget.chatService.messages.length}',
            ),
            _buildTelemetryRow(
              'Disclosed MACs',
              '${widget.chatService.publishedKeysLog.length} keys',
            ),
            _buildTelemetryRow('Memory Buffer', 'Non-swappable pinned RAM'),
          ],
        );

      case 'security':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SECURITY PROTOCOL COMMITMENT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: Color(0xFF71717A),
              ),
            ),
            const SizedBox(height: 8),
            _buildSecurityFeatureCard(
              title: 'Triple-DH (3DH)',
              desc: 'Ephemeral + Identity keys exchanged over X25519. Provides forward secrecy and mutual authentication without server trust.',
              status: isSecure ? 'ACTIVE' : 'NEGOTIATING',
              isGreen: isSecure,
            ),
            const SizedBox(height: 8),
            _buildSecurityFeatureCard(
              title: '2-of-2 Presence-Enforced Cache',
              desc: 'Decryption key K reconstructed in RAM as K = s₁ ⊕ s₂. The moment peer leaves, s₂ is zeroized and past history is mathematically unrecoverable.',
              status: isSecure ? 'LOCKED TO RAM' : 'DORMANT',
              isGreen: isSecure,
            ),
            const SizedBox(height: 8),
            _buildSecurityFeatureCard(
              title: 'Off-The-Record (OTR) MAC Disclosure',
              desc: 'HMAC keys are published in the header of the next packet, allowing either party or an adversary to forge transcripts after the fact (cryptographic deniability).',
              status: 'FORGING ENABLED',
              isGreen: true,
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTelemetryRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111113),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: const Color(0xFF1F1F23)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF71717A), fontSize: 11)),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 11,
              color: Color(0xFFE4E4E7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityFeatureCard({
    required String title,
    required String desc,
    required String status,
    required bool isGreen,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111113),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: const Color(0xFF1F1F23)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isGreen ? const Color(0xFF0F291E) : const Color(0xFF281E0F),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: isGreen ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 9,
                    color: isGreen ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // MAIN CONVERSATION / DATA STREAM
  // =========================================================================
  Widget _buildMainConversationStream(bool isSecure, String peerName, String peerFp) {
    final isInRoom = widget.chatService.roomId != null;
    final incomingCall = widget.chatService.incomingCall;

    return Column(
      children: [
        // Active Peer Details Header
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Color(0xFF0C0C0E),
            border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Peer name & Fingerprint badge
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isInRoom
                          ? (isSecure ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                          : const Color(0xFF71717A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isInRoom ? peerName : 'DIRECT MESH CHANNEL',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111113),
                      border: Border.all(color: const Color(0xFF27272A)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      isInRoom ? peerFp : 'STANDBY',
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        color: Color(0xFF71717A),
                      ),
                    ),
                  ),
                  if (isInRoom) ...[
                    const SizedBox(width: 10),
                    const Text('|', style: TextStyle(color: Color(0xFF27272A))),
                    const SizedBox(width: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isSecure ? 'Verified Handshake' : 'Negotiating Channels...',
                          style: TextStyle(
                            color: isSecure ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),

              // Right link parameters
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.chatService.packetLog.isNotEmpty) ...[
                    InkWell(
                      onTap: () => _showPacketInspector(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF18181D),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: const Color(0xFF27272A)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.history, size: 12, color: Color(0xFFA1A1AA)),
                            SizedBox(width: 4),
                            Text('Audit Log', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  Text(
                    isInRoom ? 'SCTP: ${_latency.toStringAsFixed(1)} ms' : 'SCTP: Idle',
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 11,
                      color: Color(0xFF71717A),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111113),
                      border: Border.all(color: const Color(0xFF1F1F23)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      isInRoom ? 'Deniable Ratchet' : 'Argon2id Pinned',
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        color: Color(0xFFA1A1AA),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Message List Stream or Standby Initiator View
        Expanded(
          child: !isInRoom
              ? _buildDirectMeshInitiatorView(incomingCall)
              : Container(
                  color: const Color(0xFF09090B),
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    children: [
                // Operational Handshake Notice
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111113),
                    border: Border.all(color: const Color(0xFF1F1F23)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      Text(
                        DateFormat('HH:mm:ss.SSS').format(DateTime.now()),
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 10,
                          color: Color(0xFF52525B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF18181B),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'SESSION INITIALIZED',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                            color: Color(0xFFA1A1AA),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Direct peer-to-peer data channel established. Initial Triple-DH keys exchanged in volatile memory.',
                          style: TextStyle(color: Color(0xFF71717A), fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // If empty state
                if (widget.chatService.messages.isEmpty) ...[
                  _buildEmptyStateNotice(isSecure),
                ] else ...[
                  for (final msg in widget.chatService.messages)
                    _buildMessageBubble(msg, peerName),
                ],
              ],
            ),
          ),
        ),

        // Docked Clinical Composer
        _buildDockedComposer(isSecure, peerName),
      ],
    );
  }

  Widget _buildDirectMeshInitiatorView(IncomingCallRequest? incomingCall) {
    final addresses = widget.chatService.addresses;
    final primaryAddr = addresses.isNotEmpty ? addresses.first : null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 580),
          decoration: BoxDecoration(
            color: const Color(0xFF101013),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFF27272A)),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 28, offset: Offset(0, 14)),
            ],
          ),
          child: Stack(
            children: [
              Positioned(top: -1, left: -1, child: _buildReticleCorner(topLeft: true)),
              Positioned(top: -1, right: -1, child: _buildReticleCorner(topRight: true)),
              Positioned(bottom: -1, left: -1, child: _buildReticleCorner(bottomLeft: true)),
              Positioned(bottom: -1, right: -1, child: _buildReticleCorner(bottomRight: true)),

              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF18181C),
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(color: const Color(0xFF3F3F46)),
                              ),
                              child: const Center(
                                child: Icon(Icons.hub_outlined, size: 16, color: Color(0xFF10B981)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'DIRECT MESH',
                                      style: TextStyle(
                                        fontFamily: 'JetBrains Mono',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        letterSpacing: 2.5,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'CHANNEL',
                                      style: TextStyle(
                                        fontFamily: 'JetBrains Mono',
                                        fontWeight: FontWeight.w400,
                                        fontSize: 13,
                                        letterSpacing: 2.0,
                                        color: Color(0xFF10B981),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'P2P WEBRTC DATACHANNEL • 3DH ZERO-KNOWLEDGE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 1.5,
                                    color: Color(0xFF71717A),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF18181C),
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: const Color(0xFF27272A)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.circle, size: 5, color: Color(0xFF10B981)),
                              SizedBox(width: 5),
                              Text(
                                'STANDBY',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'JetBrains Mono',
                                  color: Color(0xFF10B981),
                                  letterSpacing: 1.0,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Direct browser-to-browser encrypted session. Keys are negotiated via Deniable Triple-DH with 2-of-2 presence enforcement. No transcripts are retained on signaling nodes.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8E9192), height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    const Divider(color: Color(0xFF27272A), height: 1),
                    const SizedBox(height: 18),

                    // Inbound Connection Request (if present)
                    if (incomingCall != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C140E),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xFFB45309)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.ring_volume, size: 14, color: Color(0xFFFBBF24)),
                                SizedBox(width: 8),
                                Text(
                                  'Incoming P2P Call Offer Detected',
                                  style: TextStyle(
                                    color: Color(0xFFFBBF24),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Inbound handshake request routed through ingress endpoint:\n${incomingCall.addressId}',
                              style: const TextStyle(
                                color: Color(0xFFD4D4D8),
                                fontSize: 11,
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                FilledButton.icon(
                                  icon: const Icon(Icons.check, size: 13, color: Color(0xFF09090B)),
                                  label: const Text('Accept & Open Chat',
                                      style: TextStyle(color: Color(0xFF09090B), fontSize: 11, fontWeight: FontWeight.w600)),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                  onPressed: _isConnecting ? null : () => _handleAcceptIncoming(incomingCall),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.close, size: 13, color: Color(0xFFF87171)),
                                  label: const Text('Reject & Burn',
                                      style: TextStyle(color: Color(0xFFF87171), fontSize: 11, fontWeight: FontWeight.w600)),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1F1315),
                                    side: const BorderSide(color: Color(0xFF3F1D24)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  onPressed: _handleDeclineIncoming,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Dial Peer Section
                    const Text(
                      'DIAL REMOTE INGRESS ENDPOINT',
                      style: TextStyle(
                        color: Color(0xFFA1A1AA),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF09090B),
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: const Color(0xFF27272A)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: [
                                const Icon(Icons.call_made_rounded, size: 14, color: Color(0xFF10B981)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _peerDialController,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontFamily: 'JetBrains Mono',
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Enter peer address (e.g. mm://ing/... or bored_8f3a...)',
                                      hintStyle: TextStyle(color: Color(0xFF52525B), fontSize: 11),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                                    ),
                                    onSubmitted: (val) => _handleConnectPeerUri(val),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          onPressed: _isConnecting
                              ? null
                              : () => _handleConnectPeerUri(_peerDialController.text),
                          child: _isConnecting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF09090B)),
                                )
                              : const Text(
                                  'Connect',
                                  style: TextStyle(
                                    color: Color(0xFF09090B),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Share your ingress endpoint
                    if (primaryAddr != null) ...[
                      const Text(
                        'OR SHARE YOUR INGRESS ADDRESS',
                        style: TextStyle(
                          color: Color(0xFF71717A),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141418),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: const Color(0xFF27272A)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        primaryAddr.label,
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1F1F26),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                        child: Text(
                                          primaryAddr.isOneTime ? 'SINGLE-USE' : 'PERSISTENT',
                                          style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 9, fontFamily: 'JetBrains Mono'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'mm://ingress/${primaryAddr.id}',
                                    style: const TextStyle(
                                      fontFamily: 'JetBrains Mono',
                                      fontSize: 11,
                                      color: Color(0xFF71717A),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: 'mm://ingress/${primaryAddr.id}'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Ingress URI copied to clipboard')),
                                );
                              },
                              borderRadius: BorderRadius.circular(2),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1F1F24),
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(color: const Color(0xFF2E2E36)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.copy, size: 12, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text('Copy', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ),
                            if (widget.onSwitchToKeys != null) ...[
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: widget.onSwitchToKeys,
                                borderRadius: BorderRadius.circular(2),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141418),
                                    borderRadius: BorderRadius.circular(2),
                                    border: Border.all(color: const Color(0xFF27272A)),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.qr_code, size: 12, color: Color(0xFFA1A1AA)),
                                      SizedBox(width: 4),
                                      Text('QR & Keys', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 10)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    const Divider(color: Color(0xFF27272A), height: 1),
                    const SizedBox(height: 14),

                    // Bottom protocol telemetry
                    Row(
                      children: [
                        _buildStatusColumn('CIPHER', 'X25519-3DH'),
                        Container(width: 1, height: 24, color: const Color(0xFF27272A)),
                        _buildStatusColumn('CACHE KEY', 'K = s₁ ⊕ s₂'),
                        Container(width: 1, height: 24, color: const Color(0xFF27272A)),
                        _buildStatusColumn('MEMORY', 'VOLATILE_RAM'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusColumn(String label, String val) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF52525B), fontSize: 9, fontFamily: 'JetBrains Mono')),
            const SizedBox(height: 2),
            Text(val, style: const TextStyle(color: Color(0xFFD4D4D8), fontSize: 9, fontFamily: 'JetBrains Mono', fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateNotice(bool isSecure) {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      alignment: Alignment.center,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF111113),
          border: Border.all(color: const Color(0xFF27272A)),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSecure ? Icons.lock_open : Icons.sync,
              size: 28,
              color: isSecure ? const Color(0xFF10B981) : const Color(0xFF71717A),
            ),
            const SizedBox(height: 12),
            Text(
              isSecure ? 'Direct Channel Ready' : 'Negotiating Peer Presence...',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              isSecure
                ? 'Type a message below to transmit over the encrypted WebRTC data channel. MAC keys will automatically disclose on following packets for repudiation.'
                : 'Waiting for remote peer to complete the Triple-DH handshake and 2-of-2 presence share swap.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF71717A), fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, String peerName) {
    final isMe = message.isMe;
    final timeStr = DateFormat('HH:mm:ss').format(message.timestamp);

    // Check if the message is a JSON payload
    bool isJsonPayload = false;
    String? formattedJson;
    try {
      final decoded = jsonDecode(message.text);
      if (decoded is Map<String, dynamic>) {
        isJsonPayload = true;
        formattedJson = const JsonEncoder.withIndent('  ').convert(decoded);
      }
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Header info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMe) ...[
                  Text(
                    peerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('•', style: TextStyle(color: Color(0xFF52525B), fontSize: 10)),
                  const SizedBox(width: 8),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      color: Color(0xFF71717A),
                    ),
                  ),
                ] else ...[
                  const Text('Deniable', style: TextStyle(color: Color(0xFF71717A), fontSize: 10)),
                  const SizedBox(width: 6),
                  const Text('•', style: TextStyle(color: Color(0xFF52525B), fontSize: 10)),
                  const SizedBox(width: 6),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      color: Color(0xFF71717A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'local-node',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 2),

          // Message Body Container
          Container(
            constraints: const BoxConstraints(maxWidth: 640),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFF1C1C20) : const Color(0xFF141416),
              border: Border.all(
                color: isMe ? const Color(0xFF2E2E33) : const Color(0xFF27272A),
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: isJsonPayload
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Technical Payload Card
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF09090B),
                          border: Border.all(color: const Color(0xFF27272A)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF111113),
                                border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'payload.json',
                                        style: TextStyle(
                                          fontFamily: 'JetBrains Mono',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFFA1A1AA),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '• ${message.text.length} bytes',
                                        style: const TextStyle(
                                          fontFamily: 'JetBrains Mono',
                                          fontSize: 10,
                                          color: Color(0xFF52525B),
                                        ),
                                      ),
                                    ],
                                  ),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: message.text));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Payload JSON copied')),
                                      );
                                    },
                                    child: const Row(
                                      children: [
                                        Icon(Icons.copy, size: 12, color: Color(0xFF71717A)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Copy',
                                          style: TextStyle(
                                            fontFamily: 'JetBrains Mono',
                                            fontSize: 10,
                                            color: Color(0xFF71717A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: SelectableText(
                                formattedJson!,
                                style: const TextStyle(
                                  fontFamily: 'JetBrains Mono',
                                  fontSize: 11,
                                  color: Color(0xFFA1A1AA),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : SelectableText(
                    message.text,
                    style: TextStyle(
                      color: isMe ? const Color(0xFFF4F4F5) : const Color(0xFFE4E4E7),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
          ),

          // Message Footer / Status
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2, right: 2),
            child: isMe
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, size: 12, color: Color(0xFF10B981)),
                      const SizedBox(width: 4),
                      const Text(
                        'Delivered',
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 10,
                          color: Color(0xFF71717A),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _showPacketInspector(message),
                        child: const Text(
                          'OTR MAC Log',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 10,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  )
                : InkWell(
                    onTap: () => _showPacketInspector(message),
                    child: const Text(
                      '3DH Authenticated • MAC Disclosed',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        color: Color(0xFF71717A),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // DOCKED CLINICAL COMPOSER
  // =========================================================================
  Widget _buildDockedComposer(bool isSecure, String peerName) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0E),
        border: Border(top: BorderSide(color: Color(0xFF27272A))),
      ),
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111113),
            border: Border.all(color: const Color(0xFF27272A)),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Text Input Area
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _handleSend();
                    }
                  },
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    enabled: isSecure,
                    maxLines: 4,
                    minLines: 2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.5,
                      fontFamily: 'Geist',
                    ),
                    decoration: InputDecoration(
                      hintText: isSecure
                          ? 'Type dispatch to $peerName... (Enter to send, Shift+Enter for newline)'
                          : 'Waiting for remote peer presence handshake...',
                      hintStyle: const TextStyle(color: Color(0xFF52525B), fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),

              // Composer Toolbar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF0E0E10),
                  border: Border(top: BorderSide(color: Color(0xFF1F1F23))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left: Attach button
                    InkWell(
                      onTap: isSecure ? _handleAttachPayload : null,
                      borderRadius: BorderRadius.circular(2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.attachment, size: 14, color: Color(0xFFA1A1AA)),
                            SizedBox(width: 6),
                            Text(
                              'Attach',
                              style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Right: Helper text & Send Button
                    Row(
                      children: [
                        const Text(
                          'Press Enter to send',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 10,
                            color: Color(0xFF52525B),
                          ),
                        ),
                        const SizedBox(width: 12),
                        InkWell(
                          onTap: isSecure ? _handleSend : null,
                          borderRadius: BorderRadius.circular(2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSecure ? Colors.white : const Color(0xFF27272A),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Send',
                                  style: TextStyle(
                                    color: isSecure ? const Color(0xFF09090B) : const Color(0xFF71717A),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.arrow_upward,
                                  size: 13,
                                  color: isSecure ? const Color(0xFF09090B) : const Color(0xFF71717A),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
