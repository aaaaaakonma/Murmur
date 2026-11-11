import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/p2p_chat_service.dart';
import '../services/signaling_service.dart';
import '../services/user_address.dart';
import '../services/saved_contact.dart';
import '../services/notification_service.dart';
import '../widgets/deniable_packet_inspector.dart';
import '../widgets/hypercube_watermark.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  final P2PChatService chatService;

  const HomeScreen({super.key, required this.chatService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _peerUriController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _zeroizeOnUnload = true;
  String? _vaultErrorMessage;
  String _selectedFilter = 'all'; // 'all', 'ephemeral', 'persistent'
  String? _selectedAddressId;
  String _activeWorkspaceTab = 'keys'; // 'keys' or 'chat'
  String _mobileKeyView = 'ledger'; // 'ledger' or 'inspector' on mobile
  bool _isNotificationBannerDismissed = false;

  void _showPacketInspector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DeniablePacketInspector(
        packet: widget.chatService.packetLog.isNotEmpty ? widget.chatService.packetLog.last : null,
        decryptedText: widget.chatService.messages.isNotEmpty ? widget.chatService.messages.last.text : null,
        publishedMacKeys: widget.chatService.publishedKeysLog,
        isPresenceActive: widget.chatService.isPresenceActive,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.chatService.addListener(_onServiceUpdate);
    NotificationService().permissionState.addListener(_onPermissionStateChanged);
    NotificationService().initialize(onTap: (payload) {
      if (mounted) {
        setState(() => _activeWorkspaceTab = 'chat');
      }
    });
  }

  void _onPermissionStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onServiceUpdate);
    NotificationService().permissionState.removeListener(_onPermissionStateChanged);
    _passphraseController.dispose();
    _searchController.dispose();
    _peerUriController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {
        if (_selectedAddressId == null && widget.chatService.addresses.isNotEmpty) {
          _selectedAddressId = widget.chatService.addresses.first.id;
        }
      });
    }
  }

  // -------------------------------------------------------------
  // Vault Unlock Action
  // -------------------------------------------------------------
  Future<void> _handleUnlockVault() async {
    final pass = _passphraseController.text.trim();
    if (pass.isEmpty) {
      setState(() => _vaultErrorMessage = 'Please enter your master passphrase.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _vaultErrorMessage = 'Entropy threshold not met. Min 6 characters required.');
      return;
    }

    setState(() {
      _isLoading = true;
      _vaultErrorMessage = null;
    });

    try {
      await widget.chatService.unlockOrCreateVault(pass);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (widget.chatService.addresses.isNotEmpty) {
          _selectedAddressId = widget.chatService.addresses.first.id;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _vaultErrorMessage = 'Vault derivation failed: $e';
      });
    }
  }

  // -------------------------------------------------------------
  // Address / Key Actions
  // -------------------------------------------------------------
  Future<void> _handleCreateKeyModal() async {
    final aliasController = TextEditingController(text: 'node-ingress-point');
    bool isSingleUse = true;
    String selectedExp = '15m';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF121216),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: Color(0xFF27272A)),
          ),
          contentPadding: const EdgeInsets.all(20),
          title: Row(
            children: [
              const Icon(Icons.vpn_key_rounded, size: 18, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              const Text('Provision Ingress Key',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Color(0xFF71717A)),
                onPressed: () => Navigator.of(ctx).pop(false),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Key Alias / Name',
                    style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextField(
                  controller: aliasController,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'JetBrains Mono'),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF09090B),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(2),
                      borderSide: const BorderSide(color: Color(0xFF27272A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(2),
                      borderSide: const BorderSide(color: Color(0xFF52525B)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Key Lifecycle & Policy',
                    style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setDlgState(() => isSingleUse = true),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSingleUse ? const Color(0xFF181820) : const Color(0xFF0C0C0E),
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                              color: isSingleUse ? const Color(0xFF3F3F46) : const Color(0xFF27272A),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text('Single-Use',
                                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text('Burns automatically on first 3DH exchange.',
                                  style: TextStyle(color: Color(0xFF71717A), fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => setDlgState(() => isSingleUse = false),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: !isSingleUse ? const Color(0xFF181820) : const Color(0xFF0C0C0E),
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                              color: !isSingleUse ? const Color(0xFF3F3F46) : const Color(0xFF27272A),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF71717A),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text('Persistent',
                                      style: TextStyle(color: Color(0xFFD4D4D8), fontSize: 11, fontWeight: FontWeight.w500)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text('Accepts multiple peer ratchets until revoked.',
                                  style: TextStyle(color: Color(0xFF71717A), fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Volatile Expiration Window',
                    style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Row(
                  children: ['15m', '1 hr', '24 hr', 'Indefinite'].map((exp) {
                    final isSel = selectedExp == exp;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: InkWell(
                          onTap: () => setDlgState(() => selectedExp = exp),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFF181820) : const Color(0xFF0C0C0E),
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: isSel ? const Color(0xFF3F3F46) : const Color(0xFF27272A),
                              ),
                            ),
                            child: Text(
                              exp,
                              style: TextStyle(
                                color: isSel ? Colors.white : const Color(0xFF71717A),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFF18181C),
                side: const BorderSide(color: Color(0xFF27272A)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
              ),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFFD4D4D8), fontSize: 11)),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.bolt, size: 14, color: Color(0xFF09090B)),
              label: const Text('Generate Ingress Key',
                  style: TextStyle(color: Color(0xFF09090B), fontSize: 11, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final newAddr = await widget.chatService.generateAddress(
        label: aliasController.text.trim(),
        isOneTime: isSingleUse,
      );
      setState(() => _selectedAddressId = newAddr.id);
    }
  }

  Future<void> _handleConnectPeerUri() async {
    final uri = _peerUriController.text.trim();
    if (uri.isEmpty) return;

    // Strip optional mm://ingress/ or mm://ing/ prefix
    String cleaned = uri;
    if (cleaned.startsWith('mm://ingress/')) {
      cleaned = cleaned.substring(13);
    } else if (cleaned.startsWith('mm://ing/')) {
      cleaned = cleaned.substring(9);
    }

    setState(() => _isLoading = true);
    try {
      await widget.chatService.callAddress(cleaned);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _activeWorkspaceTab = 'chat';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e'), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  Future<void> _handleAcceptIncoming(IncomingCallRequest call) async {
    setState(() => _isLoading = true);
    try {
      await widget.chatService.answerCall(call);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _activeWorkspaceTab = 'chat';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to answer incoming connection: $e'), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  // -------------------------------------------------------------
  // Saved Peer Directory Actions
  // -------------------------------------------------------------
  Future<void> _handleCallContact(SavedContact contact) async {
    setState(() => _isLoading = true);
    try {
      await widget.chatService.callContact(contact);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _activeWorkspaceTab = 'chat';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to call ${contact.alias}: $e'), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  Future<void> _handleAddContactModal() async {
    final aliasController = TextEditingController();
    final mailboxController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121216),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: Color(0xFF27272A)),
        ),
        contentPadding: const EdgeInsets.all(20),
        title: Row(
          children: [
            const Icon(Icons.person_add_alt_1, size: 18, color: Color(0xFF60A5FA)),
            const SizedBox(width: 8),
            const Text('Save Peer Mailbox to Vault',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Color(0xFF71717A)),
              onPressed: () => Navigator.of(ctx).pop(false),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Save a peer\'s disposable or persistent ingress mailbox address in your encrypted local vault. Once saved, you can call them anytime with a single tap without manually sharing room links.',
              style: TextStyle(color: Color(0xFF71717A), fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 16),
            const Text('Peer Alias / Name',
                style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C0E),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TextField(
                controller: aliasController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(
                  hintText: 'e.g. Alice (HQ Relay), SecTeam-Node-4',
                  hintStyle: TextStyle(color: Color(0xFF52525B), fontSize: 11),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Peer Ingress Mailbox ID or URI',
                style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C0E),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TextField(
                controller: mailboxController,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'JetBrains Mono'),
                decoration: const InputDecoration(
                  hintText: 'e.g. bored_8f3a-9e1c... or mm://ingress/...',
                  hintStyle: TextStyle(color: Color(0xFF52525B), fontSize: 11),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF18181C),
              side: const BorderSide(color: Color(0xFF27272A)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            ),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFFD4D4D8), fontSize: 11)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            ),
            onPressed: () {
              if (mailboxController.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Save to Vault',
                style: TextStyle(color: Color(0xFF09090B), fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );

    if (result == true && mailboxController.text.trim().isNotEmpty) {
      final cleanUri = mailboxController.text.trim();
      String target = cleanUri;
      if (target.startsWith('mm://ingress/')) {
        target = target.substring(13);
      } else if (target.startsWith('mm://ing/')) {
        target = target.substring(9);
      }

      await widget.chatService.addContact(
        aliasController.text.trim().isEmpty ? 'Peer Node' : aliasController.text.trim(),
        target,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Peer mailbox saved to encrypted local vault.')),
        );
      }
    }
  }

  Future<void> _handleDeleteContact(SavedContact contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141113),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: Color(0xFF3F1D24)),
        ),
        title: const Text('Remove Contact from Vault?',
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        content: Text('Delete "${contact.alias}" from your local vault directory?',
            style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF71717A), fontSize: 11)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.chatService.deleteContact(contact.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${contact.alias} from vault')),
        );
      }
    }
  }

  // -------------------------------------------------------------
  // BUILD ENTRY POINT
  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (!widget.chatService.isVaultUnlocked) {
      return _buildVaultUnlockView();
    }
    return _buildWorkspaceView();
  }

  // =============================================================
  // SCREEN 1: PASSPHRASE VAULT UNLOCK (Exact Murmur Template)
  // =============================================================
  Widget _buildVaultUnlockView() {
    return Scaffold(
      backgroundColor: const Color(0xFF131315),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Hypercube Linework Watermark
          const Center(child: HypercubeWatermark(size: 880, opacity: 0.045)),

          // Centered Operational Container
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                width: 440,
                decoration: BoxDecoration(
                  color: const Color(0xFF101013),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFF27272A)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 32, offset: Offset(0, 16)),
                  ],
                ),
                child: Stack(
                  children: [
                    // Reticle Corner Notches (#52525b)
                    Positioned(top: -1, left: -1, child: _buildReticleCorner(topLeft: true)),
                    Positioned(top: -1, right: -1, child: _buildReticleCorner(topRight: true)),
                    Positioned(bottom: -1, left: -1, child: _buildReticleCorner(bottomLeft: true)),
                    Positioned(bottom: -1, right: -1, child: _buildReticleCorner(bottomRight: true)),

                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header: Murmur Logotype & Subsystem Badge
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
                                      child: Icon(Icons.shield_outlined, size: 16, color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Text(
                                            'MURMUR',
                                            style: TextStyle(
                                              fontFamily: 'JetBrains Mono',
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              letterSpacing: 3.5,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Color(0xFF10B981),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      const Text(
                                        'ENCRYPTED VAULT SUBSYSTEM',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 1.8,
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
                                    Icon(Icons.circle, size: 5, color: Color(0xFFA1A1AA)),
                                    SizedBox(width: 5),
                                    Text('v0.9.4-PROD',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontFamily: 'JetBrains Mono',
                                          color: Color(0xFFA1A1AA),
                                          letterSpacing: 1.2,
                                        )),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Zero-knowledge derivation via Argon2id v13. Keys are pinned to volatile memory and purged on disconnect.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF8E9192), height: 1.4),
                          ),
                          const SizedBox(height: 20),
                          const Divider(color: Color(0xFF27272A), height: 1),
                          const SizedBox(height: 20),

                          // Form
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              RichText(
                                text: const TextSpan(
                                  style: TextStyle(fontSize: 11, fontFamily: 'JetBrains Mono'),
                                  children: [
                                    TextSpan(text: '01 // ', style: TextStyle(color: Colors.white38)),
                                    TextSpan(
                                      text: 'MASTER PASSPHRASE',
                                      style: TextStyle(
                                        color: Color(0xFFA1A1AA),
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF18181C),
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(color: const Color(0xFF27272A)),
                                ),
                                child: const Text(
                                  'Argon2id (64MB)',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontFamily: 'JetBrains Mono',
                                    color: Color(0xFF71717A),
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Terminal input field
                          Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF141418),
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: const Color(0xFF2E2E33)),
                            ),
                            child: Row(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Icon(Icons.terminal, size: 16, color: Color(0xFF52525B)),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _passphraseController,
                                    obscureText: !_isPasswordVisible,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontFamily: 'JetBrains Mono',
                                      letterSpacing: 1.5,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Enter cryptographic secret...',
                                      hintStyle: TextStyle(
                                        color: Color(0xFF52525B),
                                        fontSize: 12,
                                        fontFamily: 'JetBrains Mono',
                                        letterSpacing: 0,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                    onSubmitted: (_) => _handleUnlockVault(),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                    size: 16,
                                    color: const Color(0xFF71717A),
                                  ),
                                  onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Memory Guard toggle
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              InkWell(
                                onTap: () => setState(() => _zeroizeOnUnload = !_zeroizeOnUnload),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _zeroizeOnUnload,
                                      activeColor: Colors.white,
                                      checkColor: const Color(0xFF131315),
                                      side: const BorderSide(color: Color(0xFF3F3F46)),
                                      onChanged: (val) => setState(() => _zeroizeOnUnload = val ?? true),
                                    ),
                                    const Text(
                                      'Volatile RAM Zeroization on unload',
                                      style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF141418),
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(color: const Color(0xFF27272A)),
                                ),
                                child: const Text(
                                  'MEM_GUARD',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontFamily: 'JetBrains Mono',
                                    color: Color(0xFF71717A),
                                    letterSpacing: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Error Feedback Box
                          if (_vaultErrorMessage != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A1314),
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(color: const Color(0xFF7F1D1D)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, size: 15, color: Color(0xFFFCA5A5)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _vaultErrorMessage!,
                                      style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),

                          // Primary Unlock Button
                          SizedBox(
                            height: 40,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                              ),
                              onPressed: _isLoading ? null : _handleUnlockVault,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_isLoading)
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF131315)),
                                    )
                                  else
                                    const Text(
                                      'UNLOCK VAULT',
                                      style: TextStyle(
                                        color: Color(0xFF131315),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                                  const SizedBox(width: 6),
                                  const Text('[↵]',
                                      style: TextStyle(
                                        color: Colors.black45,
                                        fontFamily: 'JetBrains Mono',
                                        fontSize: 11,
                                      )),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // FIDO2 Secondary Button
                          SizedBox(
                            height: 36,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.key, size: 15, color: Color(0xFFA1A1AA)),
                              label: const Text(
                                'AUTHENTICATE VIA FIDO2 / WEBAUTHN TOKEN',
                                style: TextStyle(
                                  color: Color(0xFFA1A1AA),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF27272A)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                              ),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Polling USB/NFC FIDO2 authenticator token...')),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Divider(color: Color(0xFF27272A), height: 1),
                          const SizedBox(height: 16),

                          // Telemetry Status Row
                          Row(
                            children: [
                              _buildStatusCol('CIPHER', 'X25519-3DH'),
                              Container(width: 1, height: 26, color: const Color(0xFF27272A)),
                              _buildStatusCol('MEMORY', 'VOLATILE_RAM'),
                              Container(width: 1, height: 26, color: const Color(0xFF27272A)),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('SUBSYSTEM',
                                          style: TextStyle(
                                            color: Color(0xFF52525B),
                                            fontSize: 9,
                                            fontFamily: 'JetBrains Mono',
                                          )),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Container(
                                            width: 5,
                                            height: 5,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Color(0xFF10B981),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Text('ONLINE',
                                              style: TextStyle(
                                                color: Color(0xFF10B981),
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'JetBrains Mono',
                                              )),
                                        ],
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
          ),
        ],
      ),
    );
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

  Widget _buildStatusCol(String label, String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF52525B), fontSize: 9, fontFamily: 'JetBrains Mono')),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(color: Color(0xFFD4D4D8), fontSize: 9, fontFamily: 'JetBrains Mono', fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // SCREEN 2: INGRESS KEYS & GATEWAY ADDRESSES WORKSPACE
  // =============================================================
  Widget _buildWorkspaceView() {
    final addresses = widget.chatService.addresses;
    final isDesktop = MediaQuery.of(context).size.width >= 1000;

    // Filter addresses
    final filteredAddresses = addresses.where((a) {
      if (_selectedFilter == 'ephemeral') return a.isOneTime;
      if (_selectedFilter == 'persistent') return !a.isOneTime;
      return true;
    }).where((a) {
      final query = _searchController.text.trim().toLowerCase();
      if (query.isEmpty) return true;
      return a.label.toLowerCase().contains(query) || a.id.toLowerCase().contains(query);
    }).toList();

    // Selected key for right inspector
    UserAddress? selectedAddr;
    if (_selectedAddressId != null) {
      selectedAddr = addresses.firstWhere(
        (a) => a.id == _selectedAddressId,
        orElse: () => addresses.isNotEmpty ? addresses.first : UserAddress(id: '', label: '', createdAt: DateTime.now()),
      );
    } else if (addresses.isNotEmpty) {
      selectedAddr = addresses.first;
    }

    final keysView = isDesktop
        ? Row(
            children: [
              // Left Main Pane (65%)
              Expanded(
                flex: 65,
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Color(0xFF27272A))),
                  ),
                  child: _buildLedgerView(filteredAddresses),
                ),
              ),
              // Right Inspector Pane (35%)
              Expanded(
                flex: 35,
                child: Container(
                  color: const Color(0xFF0C0C0F),
                  child: _buildInspectorView(selectedAddr),
                ),
              ),
            ],
          )
        : Column(
            children: [
              // Mobile switcher between Key Ledger and QR Inspector
              Container(
                color: const Color(0xFF0C0C0E),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildMobileSegmentButton(
                        'Ingress Keys (${filteredAddresses.length})',
                        Icons.key_outlined,
                        _mobileKeyView == 'ledger',
                        () => setState(() => _mobileKeyView = 'ledger'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMobileSegmentButton(
                        'QR & Inspector',
                        Icons.qr_code_2_rounded,
                        _mobileKeyView == 'inspector',
                        () => setState(() => _mobileKeyView = 'inspector'),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF27272A), height: 1),
              Expanded(
                child: _mobileKeyView == 'ledger'
                    ? _buildLedgerView(filteredAddresses)
                    : Container(
                        color: const Color(0xFF0C0C0F),
                        child: _buildInspectorView(selectedAddr),
                      ),
              ),
            ],
          );

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: _buildWorkspaceAppBar(),
      body: Column(
        children: [
          // Sub-Header Navigation Tab Strip (Persistent across tabs)
          _buildWorkspaceNavigationBar(),

          // Notification Permission Prompt Banner
          _buildNotificationPermissionBanner(),

          // Active Workspace Content
          Expanded(
            child: _activeWorkspaceTab == 'chat'
                ? ChatScreen(
                    chatService: widget.chatService,
                    isEmbedded: true,
                    onSwitchToKeys: () => setState(() => _activeWorkspaceTab = 'keys'),
                  )
                : (_activeWorkspaceTab == 'contacts'
                    ? _buildContactsDirectoryView()
                    : keysView),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildWorkspaceAppBar() {
    final hexDigest = widget.chatService.myIdentityKeyHex != null && widget.chatService.myIdentityKeyHex!.length >= 4
        ? '0x${widget.chatService.myIdentityKeyHex!.substring(0, 4)}'
        : '0x4b7e';

    final isInRoom = widget.chatService.roomId != null;
    final isSecure = widget.chatService.status == SessionStatus.presenceActivated;
    final isWide = MediaQuery.of(context).size.width >= 900;

    return AppBar(
      backgroundColor: const Color(0xFF09090B),
      elevation: 0,
      toolbarHeight: 48,
      titleSpacing: 16,
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(color: Color(0xFF27272A), height: 1),
      ),
      title: Row(
        children: [
          // Murmur Brand Mark (White square with black center)
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Center(
              child: Container(width: 6, height: 6, color: const Color(0xFF09090B)),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'MURMUR',
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 2.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 16, color: const Color(0xFF27272A)),
          const SizedBox(width: 12),
          Text(
            isWide ? 'MISSION-CRITICAL DIRECT MESH WORKSPACE' : 'DIRECT MESH',
            style: const TextStyle(
              fontSize: 10,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
              color: Color(0xFF71717A),
            ),
          ),
          if (isWide) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 16, color: const Color(0xFF27272A)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF121215),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isInRoom
                          ? (isSecure ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                          : const Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isInRoom
                        ? (isSecure ? 'P2P ESTABLISHED' : 'EXCHANGING 3DH')
                        : 'DAEMON ACTIVE',
                    style: const TextStyle(
                      color: Color(0xFFA1A1AA),
                      fontSize: 9,
                      fontFamily: 'JetBrains Mono',
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Notification Permission Action (Web & Mobile Prompt)
        ValueListenableBuilder<String>(
          valueListenable: NotificationService().permissionState,
          builder: (_, perm, __) {
            final isGranted = perm == 'granted';
            if (!isWide) {
              return IconButton(
                icon: Icon(
                  isGranted ? Icons.notifications_active : Icons.notifications_none,
                  size: 16,
                  color: isGranted ? const Color(0xFF10B981) : const Color(0xFFA1A1AA),
                ),
                tooltip: isGranted ? 'Notifications Active' : 'Allow Notifications',
                onPressed: () async {
                  final granted = await NotificationService().requestPermissions();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(granted ? 'Inbound call alerts active!' : 'Notifications not granted.'),
                        backgroundColor: granted ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    );
                  }
                },
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton.icon(
                icon: Icon(
                  isGranted ? Icons.notifications_active : Icons.notifications_none,
                  size: 13,
                  color: isGranted ? const Color(0xFF10B981) : const Color(0xFFA1A1AA),
                ),
                label: Text(
                  isGranted ? 'Alerts Active' : 'Allow Alerts',
                  style: TextStyle(
                    color: isGranted ? const Color(0xFF10B981) : const Color(0xFFA1A1AA),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFF141416),
                  side: BorderSide(color: isGranted ? const Color(0xFF1B4D33) : const Color(0xFF27272A)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () async {
                  final granted = await NotificationService().requestPermissions();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(granted ? 'Inbound call alerts active!' : 'Notifications not granted.'),
                        backgroundColor: granted ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    );
                  }
                },
              ),
            );
          },
        ),
        const SizedBox(width: 6),

        if (isWide && _activeWorkspaceTab == 'chat') ...[
          // Export Audit Log
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.history, size: 13, color: Color(0xFFA1A1AA)),
              label: const Text('Export Audit Log',
                  style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontWeight: FontWeight.w500)),
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFF141416),
                side: const BorderSide(color: Color(0xFF27272A)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: _showPacketInspector,
            ),
          ),
          const SizedBox(width: 8),

          if (isInRoom) ...[
            // End Session Button
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.power_settings_new, size: 14, color: Color(0xFFEF4444)),
                label: const Row(
                  children: [
                    Text('End Session',
                        style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.w500)),
                    SizedBox(width: 5),
                    Text('Esc', style: TextStyle(color: Color(0xFFEF4444), fontSize: 9, fontFamily: 'JetBrains Mono')),
                  ],
                ),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1214),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2),
                    side: const BorderSide(color: Color(0xFF3F1D24)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () async {
                  await widget.chatService.leaveRoom();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Session closed and ephemeral RAM buffers zeroized.')),
                    );
                  }
                },
              ),
            ),
          ] else ...[
            // Quick Burn / Zeroize All
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.local_fire_department, size: 14, color: Color(0xFFF87171)),
                label: const Text('Quick Burn',
                    style: TextStyle(color: Color(0xFFF87171), fontSize: 11, fontWeight: FontWeight.w500)),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1012),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                    side: const BorderSide(color: Color(0xFF3F1D24)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () async {
                  await widget.chatService.leaveRoom();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All ephemeral buffers zeroized and session closed.')),
                    );
                  }
                },
              ),
            ),
          ],
        ] else if (isWide) ...[
          // Quick Burn / Zeroize All on Keys tab (desktop)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextButton.icon(
              icon: const Icon(Icons.local_fire_department, size: 14, color: Color(0xFFF87171)),
              label: const Text('Quick Burn / Zeroize All',
                  style: TextStyle(color: Color(0xFFF87171), fontSize: 11, fontWeight: FontWeight.w500)),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF1A1012),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(3),
                  side: const BorderSide(color: Color(0xFF3F1D24)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: () async {
                await widget.chatService.leaveRoom();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All ephemeral buffers zeroized and session closed.')),
                  );
                }
              },
            ),
          ),
        ] else ...[
          // Mobile Quick Burn Icon
          IconButton(
            icon: const Icon(Icons.local_fire_department, size: 16, color: Color(0xFFF87171)),
            tooltip: 'Quick Burn / Zeroize All',
            onPressed: () async {
              await widget.chatService.leaveRoom();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All ephemeral buffers zeroized.')),
                );
              }
            },
          ),
        ],

        const SizedBox(width: 8),
        // Node Badge
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF121215),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFF27272A)),
          ),
          child: Row(
            children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981))),
              const SizedBox(width: 6),
              Text(hexDigest, style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontFamily: 'JetBrains Mono')),
            ],
          ),
        ),
        const SizedBox(width: 14),
      ],
    );
  }

  // =============================================================
  // SUB-HEADER WORKSPACE NAVIGATION BAR (High-Visibility Tabs)
  // =============================================================
  Widget _buildWorkspaceNavigationBar() {
    final isInRoom = widget.chatService.roomId != null;
    final isSecure = widget.chatService.status == SessionStatus.presenceActivated;
    final hasIncoming = widget.chatService.incomingCall != null;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 860;
    final isMobile = screenWidth < 680;

    return Container(
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF27272A)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Segmented Primary Tabs
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF131317),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF27272A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSubNavButton(
                      id: 'keys',
                      label: isDesktop ? 'Ingress Keys & Addresses' : (isMobile ? 'Keys' : 'Ingress Keys'),
                      icon: Icons.key_outlined,
                      badgeText: '${widget.chatService.addresses.length}',
                      isSelected: _activeWorkspaceTab == 'keys',
                      badgeColor: const Color(0xFF10B981),
                    ),
                    const SizedBox(width: 4),
                    _buildSubNavButton(
                      id: 'contacts',
                      label: isDesktop ? 'Saved Peers & Directory' : (isMobile ? 'Peers' : 'Saved Peers'),
                      icon: Icons.people_outline,
                      badgeText: '${widget.chatService.contacts.length}',
                      isSelected: _activeWorkspaceTab == 'contacts',
                      badgeColor: const Color(0xFF60A5FA),
                    ),
                    const SizedBox(width: 4),
                    _buildSubNavButton(
                      id: 'chat',
                      label: isDesktop ? 'Direct Mesh Chat' : (isMobile ? 'Chat' : 'Mesh Chat'),
                      icon: Icons.forum_outlined,
                      badgeText: hasIncoming
                          ? 'CALL'
                          : (isInRoom ? (isSecure ? 'P2P' : '3DH') : 'IDLE'),
                      isSelected: _activeWorkspaceTab == 'chat',
                      hasDot: true,
                      dotColor: hasIncoming
                          ? const Color(0xFFFBBF24)
                          : (isInRoom
                              ? (isSecure ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                              : const Color(0xFF71717A)),
                      badgeColor: hasIncoming
                          ? const Color(0xFFFBBF24)
                          : (isInRoom
                              ? (isSecure ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                              : const Color(0xFFA1A1AA)),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Contextual Right Actions (Desktop / Tablet)
          if (!isMobile) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasIncoming) ...[
                  // Incoming Call Alert Banner Button
                  FilledButton.icon(
                    icon: const Icon(Icons.call_rounded, size: 14, color: Color(0xFF09090B)),
                    label: Text(
                      isDesktop ? 'Incoming P2P Connection — Open Chat' : 'Incoming Call',
                      style: const TextStyle(color: Color(0xFF09090B), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFBBF24),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                    ),
                    onPressed: () {
                      setState(() => _activeWorkspaceTab = 'chat');
                    },
                  ),
                ] else if (_activeWorkspaceTab == 'contacts') ...[
                  // Add Peer Mailbox Contact
                  FilledButton.icon(
                    icon: const Icon(Icons.person_add_alt_1, size: 14, color: Color(0xFF09090B)),
                    label: const Text(
                      'Add Peer Contact',
                      style: TextStyle(color: Color(0xFF09090B), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                    ),
                    onPressed: _handleAddContactModal,
                  ),
                ] else if (_activeWorkspaceTab == 'keys') ...[
                  // Direct shortcut to chat
                  FilledButton.icon(
                    icon: const Icon(Icons.forum_outlined, size: 14, color: Colors.white),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isDesktop ? 'Switch to Direct Mesh Chat' : 'Open Chat',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward, size: 12, color: Color(0xFF10B981)),
                      ],
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF18181D),
                      side: const BorderSide(color: Color(0xFF3F3F46)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                    ),
                    onPressed: () => setState(() => _activeWorkspaceTab = 'chat'),
                  ),
                ] else ...[
                  // Direct shortcut to keys
                  OutlinedButton.icon(
                    icon: const Icon(Icons.vpn_key_outlined, size: 13, color: Color(0xFFA1A1AA)),
                    label: Text(
                      isDesktop ? 'Manage Ingress Keys & Addresses' : 'Ingress Keys',
                      style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFF121216),
                      side: const BorderSide(color: Color(0xFF27272A)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                    ),
                    onPressed: () => setState(() => _activeWorkspaceTab = 'keys'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubNavButton({
    required String id,
    required String label,
    required IconData icon,
    required String badgeText,
    required bool isSelected,
    bool hasDot = false,
    Color dotColor = const Color(0xFF10B981),
    Color badgeColor = const Color(0xFFA1A1AA),
  }) {
    final isMobile = MediaQuery.of(context).size.width < 680;
    return InkWell(
      onTap: () => setState(() => _activeWorkspaceTab = id),
      borderRadius: BorderRadius.circular(3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF222228) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected ? const Color(0xFF3F3F46) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : const Color(0xFFA1A1AA),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFFA1A1AA),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF131317) : const Color(0xFF18181D),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: isSelected ? const Color(0xFF3F3F46) : const Color(0xFF27272A),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasDot) ...[
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    badgeText,
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: badgeColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // SCREEN 3: SAVED PEER MAILBOXES & DIRECTORY
  // =============================================================
  Widget _buildContactsDirectoryView() {
    final contacts = widget.chatService.contacts;
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.people_alt_outlined, size: 20, color: Color(0xFF60A5FA)),
                        SizedBox(width: 10),
                        Text(
                          'Saved Peer Mailboxes & Directory',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Store verified peer ingress mailboxes in your encrypted Argon2id vault. Calling a peer directly negotiates a fresh, isolated Triple-DH room without manual link-sharing.',
                      style: TextStyle(color: Color(0xFF71717A), fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                icon: const Icon(Icons.person_add_alt_1, size: 15, color: Color(0xFF09090B)),
                label: const Text('Add Peer Contact', style: TextStyle(color: Color(0xFF09090B), fontSize: 12, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                ),
                onPressed: _handleAddContactModal,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // If no contacts
          if (contacts.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              decoration: BoxDecoration(
                color: const Color(0xFF101013),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181D),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF2E2E36)),
                    ),
                    child: const Icon(Icons.mail_lock_outlined, size: 26, color: Color(0xFFA1A1AA)),
                  ),
                  const SizedBox(height: 18),
                  const Text('NO SAVED PEER MAILBOXES IN VAULT',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontFamily: 'JetBrains Mono')),
                  const SizedBox(height: 8),
                  const Text(
                    'Save a peer’s Ingress Mailbox ID once. Next time you want to chat, simply tap "Call Peer" and Murmur will spawn an isolated ephemeral WebRTC session instantly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF71717A), fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 14, color: Colors.white),
                    label: const Text('Add First Peer Mailbox', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFF141418),
                      side: const BorderSide(color: Color(0xFF3F3F46)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                    ),
                    onPressed: _handleAddContactModal,
                  ),
                ],
              ),
            ),
          ] else ...[
            // Contacts Grid
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: contacts.map((contact) {
                return Container(
                  width: isDesktop ? 380 : double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111114),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFF27272A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF161B26),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(color: const Color(0xFF23354E)),
                                ),
                                child: Center(
                                  child: Text(
                                    contact.alias.isNotEmpty
                                        ? contact.alias.substring(0, min(2, contact.alias.length)).toUpperCase()
                                        : 'PE',
                                    style: const TextStyle(
                                      color: Color(0xFF93C5FD),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      fontFamily: 'JetBrains Mono',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    contact.alias,
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    contact.lastDialedAt != null
                                        ? 'Last session: ${DateFormat('MMM d, HH:mm').format(contact.lastDialedAt!)}'
                                        : 'Never called yet',
                                    style: const TextStyle(color: Color(0xFF71717A), fontSize: 10, fontFamily: 'JetBrains Mono'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFF71717A)),
                            onPressed: () => _handleDeleteContact(contact),
                            tooltip: 'Delete contact',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Mailbox row
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C0C0E),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: const Color(0xFF222226)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.alternate_email, size: 13, color: Color(0xFF71717A)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                contact.formattedMailboxId,
                                style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11, color: Color(0xFFD4D4D8)),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: contact.mailboxId));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Copied mailbox ID for ${contact.alias}')),
                                );
                              },
                              child: const Icon(Icons.copy, size: 13, color: Color(0xFFA1A1AA)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Direct 1-Click Call Button
                      SizedBox(
                        width: double.infinity,
                        height: 38,
                        child: FilledButton.icon(
                          icon: _isLoading
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF09090B)))
                              : const Icon(Icons.call, size: 14, color: Color(0xFF09090B)),
                          label: const Text('Call Peer (Spawn Ephemeral Room)',
                              style: TextStyle(color: Color(0xFF09090B), fontSize: 11, fontWeight: FontWeight.bold)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                          ),
                          onPressed: _isLoading ? null : () => _handleCallContact(contact),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // LEFT PANE: KEY LEDGER & CONNECT BAR
  // -------------------------------------------------------------
  Widget _buildLedgerView(List<UserAddress> addresses) {
    final isDesktop = MediaQuery.of(context).size.width >= 860;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header & Actions Bar
        Padding(
          padding: EdgeInsets.all(isDesktop ? 20 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isDesktop) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.key, size: 18, color: Color(0xFFA1A1AA)),
                        SizedBox(width: 8),
                        Text(
                          'Ingress Keys & Addresses',
                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.forum_outlined, size: 14, color: Color(0xFF34D399)),
                          label: const Text('Open Direct Mesh Chat',
                              style: TextStyle(color: Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F1E16),
                            side: const BorderSide(color: Color(0xFF1B4D33)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                          ),
                          onPressed: () => setState(() => _activeWorkspaceTab = 'chat'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.add, size: 15, color: Color(0xFF09090B)),
                          label: const Text('Create Ingress Key',
                              style: TextStyle(color: Color(0xFF09090B), fontSize: 12, fontWeight: FontWeight.w500)),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                          ),
                          onPressed: _handleCreateKeyModal,
                        ),
                      ],
                    ),
                  ],
                ),
              ] else ...[
                // Mobile Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.key, size: 16, color: Color(0xFFA1A1AA)),
                        SizedBox(width: 8),
                        Text(
                          'Ingress Keys',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.add, size: 14, color: Color(0xFF09090B)),
                      label: const Text('New Key',
                          style: TextStyle(color: Color(0xFF09090B), fontSize: 11, fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                      ),
                      onPressed: _handleCreateKeyModal,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              const Text(
                'Manage ephemeral and persistent ingress endpoints. External peers use these cryptographic addresses to initiate encrypted direct sessions.',
                style: TextStyle(color: Color(0xFF71717A), fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 12),

              // Peer Dialing Bar (Connect to Ingress)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF121215),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFF27272A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.call_made_rounded, size: 15, color: Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _peerUriController,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'JetBrains Mono'),
                        decoration: InputDecoration(
                          hintText: isDesktop
                              ? 'Enter peer address (e.g. bored_8f3a-9e1c... or mm://ing/...)'
                              : 'Enter peer address or URI...',
                          hintStyle: const TextStyle(color: Color(0xFF52525B), fontSize: 11),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (_) => _handleConnectPeerUri(),
                      ),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.call_made_rounded, size: 12, color: Color(0xFF09090B)),
                      label: _isLoading
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF09090B)))
                          : Text(isDesktop ? 'Connect & Open Chat' : 'Call',
                              style: const TextStyle(color: Color(0xFF09090B), fontSize: 11, fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 14 : 10, vertical: 8),
                      ),
                      onPressed: _isLoading ? null : _handleConnectPeerUri,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Filter Tabs & Search
              if (isDesktop) ...[
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF121215),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFF27272A)),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Row(
                        children: [
                          _buildFilterTab('all', 'All', widget.chatService.addresses.length),
                          _buildFilterTab('ephemeral', 'Single-Use', widget.chatService.addresses.where((a) => a.isOneTime).length),
                          _buildFilterTab('persistent', 'Persistent', widget.chatService.addresses.where((a) => !a.isOneTime).length),
                        ],
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 200,
                      height: 32,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF121215),
                          prefixIcon: const Icon(Icons.search, size: 14, color: Color(0xFF71717A)),
                          hintText: 'Search key or URI...',
                          hintStyle: const TextStyle(color: Color(0xFF52525B), fontSize: 11),
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(3),
                            borderSide: const BorderSide(color: Color(0xFF27272A)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(3),
                            borderSide: const BorderSide(color: Color(0xFF52525B)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Mobile stacked Filter & Search
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF121215),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFF27272A)),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Row(
                        children: [
                          Expanded(child: _buildFilterTab('all', 'All', widget.chatService.addresses.length)),
                          Expanded(child: _buildFilterTab('ephemeral', 'Single-Use', widget.chatService.addresses.where((a) => a.isOneTime).length)),
                          Expanded(child: _buildFilterTab('persistent', 'Persistent', widget.chatService.addresses.where((a) => !a.isOneTime).length)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF121215),
                          prefixIcon: const Icon(Icons.search, size: 14, color: Color(0xFF71717A)),
                          hintText: 'Search keys...',
                          hintStyle: const TextStyle(color: Color(0xFF52525B), fontSize: 11),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(3),
                            borderSide: const BorderSide(color: Color(0xFF27272A)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(3),
                            borderSide: const BorderSide(color: Color(0xFF52525B)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const Divider(color: Color(0xFF27272A), height: 1),

        // Table Header (Desktop only)
        if (isDesktop) ...[
          Container(
            height: 32,
            color: const Color(0xFF0C0C0E),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('NAME & URI', style: TextStyle(color: Color(0xFF71717A), fontSize: 10, fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text('TYPE & POLICY', style: TextStyle(color: Color(0xFF71717A), fontSize: 10, fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text('STATUS / LIFECYCLE', style: TextStyle(color: Color(0xFF71717A), fontSize: 10, fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text('ACTIONS', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF71717A), fontSize: 10, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1C1C20), height: 1),
        ],

        // Rows / Cards List
        Expanded(
          child: addresses.isEmpty
              ? const Center(
                  child: Text('No ingress keys match active filter.', style: TextStyle(color: Color(0xFF71717A), fontSize: 12)),
                )
              : (isDesktop
                  ? ListView.separated(
                      itemCount: addresses.length,
                      separatorBuilder: (_, __) => const Divider(color: Color(0xFF1C1C20), height: 1),
                      itemBuilder: (ctx, i) {
                        final addr = addresses[i];
                        final isSelected = addr.id == _selectedAddressId;
                        return InkWell(
                          onTap: () => setState(() => _selectedAddressId = addr.id),
                          child: Container(
                            color: isSelected ? const Color(0xFF15151A) : Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                // Name & URI
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(addr.label,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 12)),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1C1C22),
                                              borderRadius: BorderRadius.circular(2),
                                              border: Border.all(color: const Color(0xFF27272A)),
                                            ),
                                            child: Text(
                                              addr.isOneTime ? 'SINGLE-USE' : 'PERSISTENT',
                                              style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 9, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Text('mm://ing/${addr.id.substring(0, min(14, addr.id.length))}...',
                                              style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontFamily: 'JetBrains Mono')),
                                          const SizedBox(width: 4),
                                          InkWell(
                                            onTap: () {
                                              Clipboard.setData(ClipboardData(text: 'mm://ingress/${addr.id}'));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Copied ingress URI for "${addr.label}"')),
                                              );
                                            },
                                            child: const Icon(Icons.copy, size: 12, color: Color(0xFF71717A)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Type & Policy
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(addr.isOneTime ? 'Burn on 1st handshake' : 'Manual Authorization',
                                          style: const TextStyle(color: Color(0xFFE4E4E7), fontSize: 11, fontWeight: FontWeight.w500)),
                                      Text(addr.isOneTime ? 'Auto-destruct on ratchet' : 'Max 5 concurrent peers',
                                          style: const TextStyle(color: Color(0xFF71717A), fontSize: 10)),
                                    ],
                                  ),
                                ),
                                // Status / Lifecycle
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981)),
                                      ),
                                      const SizedBox(width: 6),
                                      const Text('Active • Ready',
                                          style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                                // Actions
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: const Color(0xFF18181C),
                                          side: const BorderSide(color: Color(0xFF27272A)),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                        onPressed: () => setState(() => _selectedAddressId = addr.id),
                                        child: const Text('Details', style: TextStyle(color: Color(0xFFD4D4D8), fontSize: 11)),
                                      ),
                                      const SizedBox(width: 6),
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1C1214),
                                          side: const BorderSide(color: Color(0xFF3F1D24)),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        ),
                                        onPressed: () => widget.chatService.deleteAddress(addr.id),
                                        child: const Text('Revoke', style: TextStyle(color: Color(0xFFF87171), fontSize: 11)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      itemCount: addresses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final addr = addresses[i];
                        final isSelected = addr.id == _selectedAddressId;
                        return _buildMobileAddressCard(addr, isSelected);
                      },
                    )),
        ),

        // Bottom status rail
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF0C0C0E),
            border: Border(top: BorderSide(color: Color(0xFF27272A))),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.security, size: 14, color: Color(0xFF10B981)),
                  SizedBox(width: 6),
                  Text('Zero-Persistence RAM Ledger: Address cryptographic roots exist exclusively in volatile memory.',
                      style: TextStyle(color: Color(0xFF71717A), fontSize: 11)),
                ],
              ),
              Text('Daemon: Active (Signaling Online)',
                  style: TextStyle(color: Color(0xFF52525B), fontSize: 10, fontFamily: 'JetBrains Mono')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterTab(String id, String label, int count) {
    final isSel = _selectedFilter == id;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF1F1F24) : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                  color: isSel ? Colors.white : const Color(0xFF71717A),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                )),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSel ? const Color(0xFF27272A) : const Color(0xFF1A1A1E),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(count.toString(),
                  style: const TextStyle(fontSize: 9, fontFamily: 'JetBrains Mono', color: Color(0xFFA1A1AA))),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // RIGHT PANE: KEY INSPECTOR & OPTICAL QR DRAWER
  // -------------------------------------------------------------
  Widget _buildInspectorView(UserAddress? addr) {
    final incomingCall = widget.chatService.incomingCall;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Inspector Title & Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.qr_code_2, size: 18, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('KEY INSPECTOR',
                          style: TextStyle(color: Color(0xFF71717A), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      Text(addr?.label ?? 'No Key Selected',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF141B18),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: const Color(0xFF1B3D2B)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, size: 5, color: Color(0xFF10B981)),
                    SizedBox(width: 5),
                    Text('Active • Ready', style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // PENDING CONNECTION OFFER ALERT BOX (when peer is calling this address)
          if (incomingCall != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF161512),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF423315)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFBBF24))),
                          const SizedBox(width: 8),
                          const Text('1 Inbound Connection Request',
                              style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const Text('Direct Hole-Punch',
                          style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 10, fontFamily: 'JetBrains Mono')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0D0B),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: const Color(0xFF2B2212)),
                    ),
                    child: Builder(
                      builder: (context) {
                        SavedContact? callerContact;
                        for (final c in widget.chatService.contacts) {
                          if (c.mailboxId == incomingCall.addressId) {
                            callerContact = c;
                            break;
                          }
                        }
                        return Column(
                          children: [
                            _buildCallField(
                              'Peer:',
                              callerContact != null ? callerContact.alias : 'Remote Mesh Node',
                            ),
                            _buildCallField('Via Ingress:', incomingCall.addressId),
                            _buildCallField('Transport:', 'WebRTC DataChannel'),
                            _buildCallField('Protocol:', 'Deniable Triple-DH (3DH)'),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check, size: 14, color: Color(0xFF09090B)),
                          label: const Text('Accept & Open Chat',
                              style: TextStyle(color: Color(0xFF09090B), fontSize: 11, fontWeight: FontWeight.w600)),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                          ),
                          onPressed: _isLoading ? null : () => _handleAcceptIncoming(incomingCall),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.close, size: 14, color: Color(0xFFF87171)),
                          label: const Text('Reject & Burn',
                              style: TextStyle(color: Color(0xFFF87171), fontSize: 11, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFF1F1315),
                            side: const BorderSide(color: Color(0xFF3F1D24)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                          ),
                          onPressed: () => widget.chatService.declineCall(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // OPTICAL VECTOR QR CODE MATRIX
          if (addr != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF121216),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Column(
                children: [
                  // White high-contrast optical QR code box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                    ),
                    child: QrImageView(
                      data: 'mm://ingress/${addr.id}',
                      version: QrVersions.auto,
                      size: 160.0,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Level H (30% redundancy)', style: TextStyle(color: Color(0xFF71717A), fontSize: 10, fontFamily: 'JetBrains Mono')),
                      Text('Volatile RAM Payload', style: TextStyle(color: Color(0xFF71717A), fontSize: 10, fontFamily: 'JetBrains Mono')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Ingress URI Copy Row
            const Text('CRYPTOGRAPHIC INGRESS URI',
                style: TextStyle(color: Color(0xFF71717A), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF121216),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      'mm://ingress/${addr.id}',
                      style: const TextStyle(color: Color(0xFFF4F4F5), fontSize: 11, fontFamily: 'JetBrains Mono'),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: 'mm://ingress/${addr.id}'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ingress URI copied to clipboard')),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F1F24),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFF2E2E36)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.copy, size: 12, color: Colors.white),
                          SizedBox(width: 4),
                          Text('Copy Link', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Launch Direct Mesh Chat with this Key Button
            SizedBox(
              width: double.infinity,
              height: 38,
              child: FilledButton.icon(
                icon: const Icon(Icons.forum_outlined, size: 14, color: Colors.white),
                label: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Launch Direct Mesh Chat',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward, size: 12, color: Color(0xFF10B981)),
                  ],
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF191920),
                  side: const BorderSide(color: Color(0xFF3F3F46)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                ),
                onPressed: () => setState(() => _activeWorkspaceTab = 'chat'),
              ),
            ),
            const SizedBox(height: 16),

            // Parameters Table
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF121216),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: const Color(0xFF101014),
                    child: const Text('CONFIGURATION & POLICY',
                        style: TextStyle(color: Color(0xFF71717A), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  ),
                  const Divider(color: Color(0xFF1C1C20), height: 1),
                  _buildParamRow('Key Type', addr.isOneTime ? 'Ephemeral Single-Use' : 'Persistent Inbound Gateway'),
                  _buildParamRow('Ciphersuite', 'X25519-3DH + AES-256-GCM'),
                  _buildParamRow('Auto-Burn Trigger', addr.isOneTime ? 'Post-Ratchet Confirmation' : 'Manual Authorization'),
                  _buildParamRow('Volatile Cache', '2-of-2 Secret Split (K = s₁ ⊕ s₂)'),
                  _buildParamRow('Identity Digest', 'SHA256:${addr.id.substring(min(6, addr.id.length))}'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCallField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF71717A), fontSize: 11)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'JetBrains Mono', fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildParamRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF71717A), fontSize: 11)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'JetBrains Mono', fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // =============================================================
  // NOTIFICATION PERMISSION PROMPT BANNER
  // =============================================================
  Widget _buildNotificationPermissionBanner() {
    return ValueListenableBuilder<String>(
      valueListenable: NotificationService().permissionState,
      builder: (_, perm, __) {
        if (perm == 'granted' || perm == 'unsupported' || _isNotificationBannerDismissed) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF1E3A8A)),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Icon(Icons.notifications_active_outlined, size: 16, color: Color(0xFF60A5FA)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INBOUND CALL NOTIFICATIONS',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF93C5FD),
                        letterSpacing: 0.8,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Allow notifications to receive encrypted incoming call prompts when this tab or app is minimized.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                ),
                onPressed: () async {
                  final granted = await NotificationService().requestPermissions();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(granted
                            ? 'Inbound call alerts enabled!'
                            : 'Notification permission was not granted.'),
                        backgroundColor: granted ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    );
                  }
                },
                child: const Text('Allow Notifications', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
                splashRadius: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () => setState(() => _isNotificationBannerDismissed = true),
              ),
            ],
          ),
        );
      },
    );
  }

  // =============================================================
  // MOBILE INGRESS KEY CARD & SEGMENT SWITCHER
  // =============================================================
  Widget _buildMobileSegmentButton(String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1F1F24) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected ? const Color(0xFF3F3F46) : const Color(0xFF27272A),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isSelected ? const Color(0xFF10B981) : const Color(0xFFA1A1AA)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFFA1A1AA),
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileAddressCard(UserAddress addr, bool isSelected) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF15151C) : const Color(0xFF101014),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected ? const Color(0xFF10B981) : const Color(0xFF27272A),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    addr.label,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C22),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: const Color(0xFF27272A)),
                ),
                child: Text(
                  addr.isOneTime ? 'SINGLE-USE' : 'PERSISTENT',
                  style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 9, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0C),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'mm://ing/${addr.id}',
                    style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 11, fontFamily: 'JetBrains Mono'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 13, color: Color(0xFF71717A)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: 'mm://ingress/${addr.id}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Copied ingress URI for "${addr.label}"')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_2_rounded, size: 13, color: Color(0xFF10B981)),
                  label: const Text('QR & Inspect', style: TextStyle(color: Color(0xFF10B981), fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F1B15),
                    side: const BorderSide(color: Color(0xFF1D4D32)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedAddressId = addr.id;
                      _mobileKeyView = 'inspector';
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, size: 13, color: Color(0xFFF87171)),
                label: const Text('Burn', style: TextStyle(color: Color(0xFFF87171), fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1214),
                  side: const BorderSide(color: Color(0xFF3F1D24)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                ),
                onPressed: () => widget.chatService.deleteAddress(addr.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
