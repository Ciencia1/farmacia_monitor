class AppConfig {
  // ── MQTT ──────────────────────────────────────────────
  static const String mqttHost = '168.75.110.69';
  static const int mqttPort = 1883;
  static const String mqttUser = 'farmacia_lopez';
  static const String mqttPassword = 'MiClave123';
  static const String mqttClientId = 'farmacia_flutter_app';

  // Topics dinámicos por heladera
  static String topicTemperatura(String id) =>
      'farmacias/$mqttUser/$id/temperatura';
  static String topicStatus(String id) =>
      'farmacias/$mqttUser/$id/status';
  static String topicOnline(String id) =>
      'farmacias/$mqttUser/$id/online';

  // ── Umbrales ──────────────────────────────────────────
  static const double tempMin = 2.0;
  static const double tempMax = 8.0;
  static const double tempWarnThreshold = 7.5;

  // ── Historial ─────────────────────────────────────────
  static const int maxHistoryPoints = 288;
  static const String prefKeyHistory = 'temp_history_v2';
  static const String prefKeyHeladeras = 'heladeras_config';

  // ── Conexión ──────────────────────────────────────────
  static const int reconnectDelaySeconds = 5;
  static const int keepAlivePeriod = 30;
  static const int disconnectNotifMinutes = 20;

  // ── Info ──────────────────────────────────────────────
  static const String farmaciaName = 'Farmacia López';
}
