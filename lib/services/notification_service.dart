import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  final Map<String, DateTime> _lastAlertTime = {};

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));

    const channel = AndroidNotificationChannel(
      'farmacia_alerts', 'Alertas de Temperatura',
      description: 'Notificaciones de temperatura y conexión',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  bool _canNotify(String key, {int minMinutes = 5}) {
    final last = _lastAlertTime[key];
    if (last == null) return true;
    return DateTime.now().difference(last).inMinutes >= minMinutes;
  }

  Future<void> showTempAlert(double temp, String heladeraName) async {
    final key = 'temp_${temp < AppConfig.tempMin ? "cold" : "hot"}';
    if (!_canNotify(key)) return;
    _lastAlertTime[key] = DateTime.now();

    final isCold = temp < AppConfig.tempMin;
    await _plugin.show(
      1,
      isCold
          ? '❄️ Temperatura baja — $heladeraName'
          : '🌡️ Temperatura alta — $heladeraName',
      isCold
          ? 'La temperatura es ${temp.toStringAsFixed(1)}°C. Mínimo permitido: ${AppConfig.tempMin}°C.'
          : 'La temperatura es ${temp.toStringAsFixed(1)}°C. Máximo permitido: ${AppConfig.tempMax}°C.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'farmacia_alerts', 'Alertas de Temperatura',
          importance: Importance.high, priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFFF87171),
          enableLights: true,
          ledColor: const Color(0xFFF87171),
          ledOnMs: 1000, ledOffMs: 500,
        ),
      ),
    );
  }

  Future<void> showWarningAlert(double temp, String heladeraName) async {
    final key = 'warning_$heladeraName';
    if (!_canNotify(key, minMinutes: 10)) return;
    _lastAlertTime[key] = DateTime.now();

    await _plugin.show(
      2,
      '⚠️ Atención — $heladeraName',
      'La temperatura es ${temp.toStringAsFixed(1)}°C, próxima al límite de ${AppConfig.tempMax}°C.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'farmacia_alerts', 'Alertas de Temperatura',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
          color: Color(0xFFFBBF24),
        ),
      ),
    );
  }

  Future<void> showDeviceDisconnected(String heladeraName) async {
    await _plugin.show(
      3,
      '📡 Sin señal — $heladeraName',
      'El dispositivo lleva más de ${AppConfig.disconnectNotifMinutes} minutos sin enviar datos. Verificar conexión.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'farmacia_alerts', 'Alertas de Temperatura',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  Future<void> showBatteryAlert(String heladeraName, double? voltaje) async {
    final key = 'battery_$heladeraName';
    if (!_canNotify(key, minMinutes: 60)) return;
    _lastAlertTime[key] = DateTime.now();

    final voltStr = voltaje != null ? ' (${voltaje.toStringAsFixed(2)}V)' : '';
    await _plugin.show(
      4,
      '🔋 Batería crítica — $heladeraName',
      'La batería del dispositivo está muy baja$voltStr. Conectar a cargador.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'farmacia_alerts', 'Alertas de Temperatura',
          importance: Importance.high, priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: Color(0xFFFBBF24),
        ),
      ),
    );
  }
}
