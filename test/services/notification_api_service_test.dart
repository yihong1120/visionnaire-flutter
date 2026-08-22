import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/services/notification_api_service.dart';

void main() {
  group('AppNotification', () {
    test('parses canonical notification payload', () {
      final AppNotification notification = AppNotification.fromJson(
        <String, dynamic>{
          'id': 12,
          'type': 'signature',
          'title': '文件待簽核',
          'body': 'DOC-001 需要簽核',
          'deep_link': '/sign_tasks?task_id=456',
          'is_read': false,
          'created_at': '2026-06-19T12:00:00Z',
          'metadata': <String, dynamic>{'task_id': 456},
        },
      );

      expect(notification.id, '12');
      expect(notification.type, 'signature');
      expect(notification.title, '文件待簽核');
      expect(notification.body, 'DOC-001 需要簽核');
      expect(notification.deepLink, '/sign_tasks?task_id=456');
      expect(notification.isRead, isFalse);
      expect(notification.metadata['task_id'], 456);
    });

    test('falls back to metadata deep link and alternate read field', () {
      final AppNotification notification = AppNotification.fromJson(
        <String, dynamic>{
          'notification_id': 'abc',
          'notification_type': 'violation',
          'message': '違規提醒',
          'read': true,
          'data': <String, dynamic>{
            'deepLink': '/violations?violation_id=99',
          },
        },
      );

      expect(notification.id, 'abc');
      expect(notification.type, 'violation');
      expect(notification.body, '違規提醒');
      expect(notification.deepLink, '/violations?violation_id=99');
      expect(notification.isRead, isTrue);
    });

    test('routes legacy violation query links to violation detail', () {
      final AppNotification notification = AppNotification.fromJson(
        <String, dynamic>{
          'id': 'legacy-violation',
          'type': 'violation',
          'title': '違規提醒',
          'deep_link': '/violations?violation_id=99',
        },
      );

      expect(
        NotificationAPIService.routeForNotification(notification),
        '/violations/99',
      );
    });

    test('routes violation metadata to violation detail when link is generic',
        () {
      final AppNotification notification = AppNotification.fromJson(
        <String, dynamic>{
          'id': 'metadata-violation',
          'type': 'violation',
          'title': '違規提醒',
          'deep_link': '/violations',
          'metadata': <String, dynamic>{'violation_id': 123},
        },
      );

      expect(
        NotificationAPIService.routeForNotification(notification),
        '/violations/123',
      );
    });

    test('routes site alert metadata to violation detail', () {
      final AppNotification notification = AppNotification.fromJson(
        <String, dynamic>{
          'id': 'site-alert',
          'type': 'site_alert',
          'title': '警示通知',
          'metadata': <String, dynamic>{'violation_record_id': 'abc-123'},
        },
      );

      expect(
        NotificationAPIService.routeForNotification(notification),
        '/violations/abc-123',
      );
    });

    test('routes FCM violation payload to violation detail', () {
      expect(
        NotificationAPIService.debugRouteFromNotificationData(
          <String, dynamic>{'violation_id': 456},
        ),
        '/violations/456',
      );
    });
  });
}
