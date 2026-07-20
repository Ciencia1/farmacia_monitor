class AppConfig {
  // ── Servidor ──────────────────────────────────────────
  static const String serverHost = '168.75.110.69';
  static const int mqttPort = 1883;
  static const String mqttClientId = 'farmacia_flutter_app';

  // ── Datos por sesión (se setean al loguearse, ver AuthService) ──
  static String mqttUser = '';
  static String mqttPassword = '';
  static String farmaciaId = '';
  static String farmaciaName = '';
  static double tempMin = 2.0;
  static double tempMax = 8.0;

  static void configurarSesion({
    required String id,
    required String nombre,
    required String mUser,
    required String mPassword,
    required double tMin,
    required double tMax,
  }) {
    farmaciaId = id;
    farmaciaName = nombre;
    mqttUser = mUser;
    mqttPassword = mPassword;
    tempMin = tMin;
    tempMax = tMax;
  }

  static void limpiarSesion() {
    farmaciaId = '';
    farmaciaName = '';
    mqttUser = '';
    mqttPassword = '';
    tempMin = 2.0;
    tempMax = 8.0;
  }

  static String topicTemperatura(String id) =>
      'farmacias/$farmaciaId/$id/temperatura';
  static String topicStatus(String id) =>
      'farmacias/$farmaciaId/$id/status';
  static String topicOnline(String id) =>
      'farmacias/$farmaciaId/$id/online';

  // ── Umbrales fijos de UI (no cambian por farmacia) ─────
  static const double tempWarnThreshold = 7.5;

  // ── Historial ─────────────────────────────────────────
  static const int maxHistoryPoints = 288;
  static const String prefKeyHistory = 'temp_history_v2';
  static const String prefKeyHeladeras = 'heladeras_config';

  // ── Conexión ──────────────────────────────────────────
  static const int reconnectDelaySeconds = 5;
  static const int keepAlivePeriod = 30;
  static const int disconnectNotifMinutes = 20;
}
