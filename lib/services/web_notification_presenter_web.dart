import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

Future<void> showWebNotification({
  required String title,
  required String body,
  String? payload,
  void Function()? onClick,
}) async {
  final JSAny? notificationApi =
      web.window.getProperty<JSAny?>('Notification'.toJS);
  if (notificationApi == null || !notificationApi.isA<JSObject>()) return;

  try {
    if (web.Notification.permission != 'granted') return;
  } catch (_) {
    return;
  }

  final web.Notification notification;
  try {
    notification = web.Notification(
      title,
      web.NotificationOptions(
        body: body,
        icon: 'icons/Icon-192.png',
        data: payload?.toJS,
      ),
    );
  } catch (_) {
    return;
  }

  notification.onclick = ((web.Event _) {
    web.window.focus();
    onClick?.call();
    notification.close();
  }).toJS;
}
