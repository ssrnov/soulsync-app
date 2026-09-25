import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';

// Local notifications so chat messages are all readable (WhatsApp-style inbox)
// instead of Android's "3 messages from 2 chats" summary. Chat pushes come as
// data-only messages; we build the notification ourselves and stack every
// message into ONE expandable notification.

final FlutterLocalNotificationsPlugin flnp = FlutterLocalNotificationsPlugin();
const int kChatNotifId = 4771;
const String kChatChannelId = 'chat_messages';

Future<void> initLocalNotifications({
  void Function(NotificationResponse)? onTap,
}) async {
  try {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await flnp.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: onTap,
    );
    await flnp
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          kChatChannelId,
          'Chat Messages',
          description: 'New messages from your partner',
          importance: Importance.high,
        ));
  } catch (_) {}
}

// Show a chat message, stacking all recent unread messages so each is readable.
// When [disguised] is true (disguise mode on) show a single plain notification
// with the given title/body — no stacking, nothing revealing.
Future<void> showChatNotification(String sender, String message, {bool disguised = false}) async {
  if (disguised) {
    final details = AndroidNotificationDetails(
      kChatChannelId, 'Chat Messages',
      importance: Importance.high, priority: Priority.high,
    );
    try { await flnp.show(kChatNotifId, sender, message, NotificationDetails(android: details), payload: 'chat'); } catch (_) {}
    return;
  }
  if (message.trim().isEmpty) message = '📩 New message';
  List<String> lines = [];
  try {
    final box = Hive.isBoxOpen('notif') ? Hive.box('notif') : await Hive.openBox('notif');
    lines = ((box.get('chat_lines') as List?) ?? []).map((e) => e.toString()).toList();
    lines.add("$sender: $message");
    if (lines.length > 8) lines = lines.sublist(lines.length - 8);
    await box.put('chat_lines', lines);
  } catch (_) {
    lines = ["$sender: $message"];
  }

  final many = lines.length > 1;
  final title = many ? "${lines.length} new messages" : sender;
  final inbox = InboxStyleInformation(
    lines,
    contentTitle: title,
    summaryText: many ? "SoulSync 💜" : null,
  );
  final details = AndroidNotificationDetails(
    kChatChannelId,
    'Chat Messages',
    channelDescription: 'New messages from your partner',
    importance: Importance.high,
    priority: Priority.high,
    styleInformation: inbox,
    groupKey: 'soulsync_chat',
    category: AndroidNotificationCategory.message,
  );
  try {
    await flnp.show(kChatNotifId, title, message,
        NotificationDetails(android: details), payload: 'chat');
  } catch (_) {}
}

// Clear the stacked chat notification once the user has read the chat.
Future<void> clearChatNotifications() async {
  try {
    final box = Hive.isBoxOpen('notif') ? Hive.box('notif') : await Hive.openBox('notif');
    await box.put('chat_lines', <String>[]);
  } catch (_) {}
  try {
    await flnp.cancel(kChatNotifId);
  } catch (_) {}
}
