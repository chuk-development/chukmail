import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String channelBackgroundId = 'mail_background_connection';
  static const String channelBackgroundName = 'Hintergrundverbindung';
  static const String channelNewMailId = 'new_mail_notifications';
  static const String channelNewMailName = 'Neue E-Mails';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    // User-disablable foreground/background sync channel
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      channelBackgroundId,
      channelBackgroundName,
      description:
          'Persistent connection for IMAP IDLE and background mail sync. '
          'Can be disabled — new-mail alerts still arrive on the other channel.',
      importance: Importance.min,
      showBadge: false,
    ));

    // High-priority new-mail channel — should stay enabled
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      channelNewMailId,
      channelNewMailName,
      description: 'Alerts for newly received mail.',
      importance: Importance.high,
    ));

    _ready = true;
  }

  Future<void> showNewMail({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelNewMailId,
        channelNewMailName,
        channelDescription: 'Alerts for newly received mail.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(id, title, body, details);
  }

  Future<void> showBackgroundStatus({
    required int id,
    required String title,
    String? body,
  }) async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelBackgroundId,
        channelBackgroundName,
        channelDescription:
            'Persistent connection for IMAP IDLE and background mail sync.',
        importance: Importance.min,
        priority: Priority.min,
        ongoing: true,
        silent: true,
        showWhen: false,
        onlyAlertOnce: true,
      ),
    );
    await _plugin.show(id, title, body, details);
  }

  Future<void> cancelBackgroundStatus(int id) async {
    await _plugin.cancel(id);
  }
}
