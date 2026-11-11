import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Web implementation of Notification API and Audio chime via modern package:web.
class WebNotificationHelper {
  static bool get isSupported {
    try {
      return web.Notification.permission.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static String get permissionStatus {
    try {
      return web.Notification.permission;
    } catch (_) {
      return 'unsupported';
    }
  }

  static Future<String> requestPermission() async {
    try {
      final perm = await web.Notification.requestPermission().toDart;
      return perm.toDart;
    } catch (e) {
      return 'denied';
    }
  }

  static void showNotification({
    required String title,
    required String body,
    String? icon,
    String? tag,
    void Function()? onClick,
  }) {
    try {
      if (web.Notification.permission != 'granted') return;

      final options = web.NotificationOptions(
        body: body,
        icon: icon ?? 'favicon.png',
        tag: tag ?? '',
      );

      final notif = web.Notification(title, options);
      if (onClick != null) {
        notif.onclick = ((web.Event _) {
          web.window.focus();
          onClick();
          notif.close();
        }).toJS;
      }

      playNotificationChime();
    } catch (_) {}
  }

  /// Synthesize an audio alert chime using Web Audio API
  static void playNotificationChime() {
    try {
      final ctx = web.AudioContext();
      final now = ctx.currentTime;
      final dest = ctx.destination;

      // Pulse 1: 880 Hz (A5)
      final osc1 = ctx.createOscillator();
      final gain1 = ctx.createGain();
      osc1.type = 'sine';
      osc1.frequency.setValueAtTime(880, now);
      gain1.gain.setValueAtTime(0.2, now);
      gain1.gain.exponentialRampToValueAtTime(0.001, now + 0.15);
      osc1.connect(gain1);
      gain1.connect(dest);
      osc1.start(now);
      osc1.stop(now + 0.15);

      // Pulse 2: 1320 Hz (E6 - high quint)
      final osc2 = ctx.createOscillator();
      final gain2 = ctx.createGain();
      osc2.type = 'sine';
      osc2.frequency.setValueAtTime(1320, now + 0.18);
      gain2.gain.setValueAtTime(0.25, now + 0.18);
      gain2.gain.exponentialRampToValueAtTime(0.001, now + 0.45);
      osc2.connect(gain2);
      gain2.connect(dest);
      osc2.start(now + 0.18);
      osc2.stop(now + 0.45);
    } catch (_) {}
  }
}
