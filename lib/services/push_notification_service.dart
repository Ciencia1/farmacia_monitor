import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'notification_service.dart';

/// Maneja las notificaciones push (Firebase Cloud Messaging).
/// Estas SI llegan aunque la app este cerrada del todo, a diferencia de
/// las locales de NotificationService (que solo funcionan con la app
/// corriendo en memoria).
class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  String? _token;
  String? get token => _token;

  Future<void> init() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    _token = await _fcm.getToken();
    debugPrint('FCM token: $_token');

    _fcm.onTokenRefresh.listen((nuevoToken) {
      _token = nuevoToken;
      debugPrint('FCM token renovado: $_token');
      onTokenChanged?.call(nuevoToken);
    });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('Push recibido (app abierta): ${message.notification?.title}');
      final title = message.notification?.title ?? 'Farmacia Monitor';
      final body = message.notification?.body ?? '';
      NotificationService().showGenericAlert(title, body);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('Push tocado (app en background): ${message.notification?.title}');
    });
  }

  void Function(String nuevoToken)? onTokenChanged;
}
