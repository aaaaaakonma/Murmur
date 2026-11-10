import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef NotificationTapCallback = void Function(String? payload);

/// Manages cross-platform (Web & Android) blind notifications for Murmur.
/// Supports zero-knowledge envelope notifications when vault is locked,
/// and contact-resolved notifications when vault is unlocked.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  NotificationTapCallback? onNotificationTapped;

  static const String channelId = 'murmur_inbound_calls';
  static const String channelName = 'Inbound Encrypted Connections';
  static const String channelDesc =
      'Alerts for incoming direct P2P mesh connection requests';

  Future<void> initialize({NotificationTapCallback? onTap}) async {
    if (_isInitialized) return;
    onNotificationTapped = onTap;

    // Android settings (using app launcher icon)
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Darwin (iOS / macOS) settings
    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Linux settings
    const LinuxInitializationSettings linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open');

    final InitializationSettings initSettings = const InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    try {
      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('[Notification] Tapped with payload: ${response.payload}');
          onNotificationTapped?.call(response.payload);
        },
      );

      // Create Android Notification Channel
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );

        await androidImplementation.createNotificationChannel(channel);
        await androidImplementation.requestNotificationsPermission();
      }

      _isInitialized = true;
      debugPrint('[Notification] Service initialized successfully.');
    } catch (e) {
      debugPrint('[Notification] Initialization warning: $e');
    }
  }

  /// Request notification permissions (useful for prompt on user action)
  Future<bool> requestPermissions() async {
    try {
      if (!kIsWeb) {
        final androidImplementation = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidImplementation != null) {
          final granted =
              await androidImplementation.requestNotificationsPermission();
          return granted ?? false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('[Notification] Permission request error: $e');
      return false;
    }
  }

  /// Show an incoming connection notification (Blind or Resolved)
  Future<void> showInboundCallNotification({
    required String callId,
    required String addressId,
    String? callerAlias,
    required bool isVaultLocked,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Zero-Knowledge Blind Envelope vs Contact-Resolved Title/Body
    final String title = isVaultLocked
        ? 'MURMUR — INCOMING ENCRYPTED CONNECTION'
        : (callerAlias != null
            ? 'CALL FROM ${callerAlias.toUpperCase()}'
            : 'INCOMING DIRECT MESH CALL');

    final String body = isVaultLocked
        ? 'Inbound P2P mesh connection request received. Unlock vault to answer.'
        : (callerAlias != null
            ? '$callerAlias is requesting a direct Triple-DH session. Tap to answer.'
            : 'Inbound direct session request on $addressId. Tap to answer.');

    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.call,
        ticker: 'Inbound P2P call',
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(body),
        fullScreenIntent: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      // Notification ID derived from callId hash
      final int notifId = callId.hashCode & 0x7FFFFFFF;
      await _notificationsPlugin.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: '$addressId/$callId',
      );
      debugPrint('[Notification] Inbound call notification displayed: $title');
    } catch (e) {
      debugPrint('[Notification] Failed to show notification: $e');
    }
  }

  /// Cancel an active notification when call answered or declined
  Future<void> cancelCallNotification(String callId) async {
    try {
      final int notifId = callId.hashCode & 0x7FFFFFFF;
      await _notificationsPlugin.cancel(id: notifId);
    } catch (e) {
      debugPrint('[Notification] Failed to cancel notification: $e');
    }
  }
}
