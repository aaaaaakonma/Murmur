import 'dart:async';

/// Stub implementation of Web Notifications for non-web platforms (Android, iOS, Desktop).
class WebNotificationHelper {
  static bool get isSupported => false;

  static String get permissionStatus => 'unsupported';

  static Future<String> requestPermission() async => 'unsupported';

  static void showNotification({
    required String title,
    required String body,
    String? icon,
    String? tag,
    void Function()? onClick,
  }) {}

  static void playNotificationChime() {}
}
