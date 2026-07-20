import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FarmaciaSession {
  final String id;
  final String nombre;
  final String mqttUser;
  final String mqttPassword;
  final double tempMin;
  final double tempMax;
  final List<Map<String, String>> heladeras;

  FarmaciaSession({
    required this.id,
    required this.nombre,
    required this.mqttUser,
    required this.mqttPassword,
    required this.tempMin,
    required this.tempMax,
    required this.heladeras,
  });

  factory FarmaciaSession.fromJson(Map<String, dynamic> j) {
    return FarmaciaSession(
      id: j['id'],
      nombre: j['nombre'],
      mqttUser: j['mqtt_user'],
      mqttPassword: j['mqtt_password'],
      tempMin: (j['temp_min'] as num).toDouble(),
      tempMax: (j['temp_max'] as num).toDouble(),
      heladeras: (j['heladeras'] as List)
          .map((h) => {
                'id': h['id'].toString(),
                'nombre': h['nombre'].toString(),
              })
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'mqtt_user': mqttUser,
        'mqtt_password': mqttPassword,
        'temp_min': tempMin,
        'temp_max': tempMax,
        'heladeras': heladeras,
      };
}

class AuthService {
  static const String _baseUrl = 'http://168.75.110.69:5000';
  static const String _keyToken = 'auth_token';
  static const String _keySession = 'auth_session';

  Future<FarmaciaSession> login(String email, String password) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/login'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));

    final data = json.decode(res.body) as Map<String, dynamic>;

    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['mensaje'] ?? 'Error de autenticación');
    }

    final session = FarmaciaSession.fromJson(data['farmacia']);
    final token = data['token'] as String;

    await _guardarSesion(token, session);
    return session;
  }

  Future<void> _guardarSesion(String token, FarmaciaSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keySession, json.encode(session.toJson()));
  }

  Future<FarmaciaSession?> sesionGuardada() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySession);
    if (raw == null) return null;
    try {
      return FarmaciaSession.fromJson(json.decode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<String?> token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keySession);
  }
}
