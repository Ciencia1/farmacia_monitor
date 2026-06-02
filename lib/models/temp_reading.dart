import 'dart:convert';
import '../config.dart';

class Heladera {
  final String id;
  final String nombre;

  const Heladera({required this.id, required this.nombre});

  Heladera copyWith({String? nombre}) =>
      Heladera(id: id, nombre: nombre ?? this.nombre);

  Map<String, dynamic> toJson() => {'id': id, 'nombre': nombre};

  factory Heladera.fromJson(Map<String, dynamic> map) =>
      Heladera(id: map['id'] as String, nombre: map['nombre'] as String);

  String get topicTemperatura =>
      'farmacias/${AppConfig.mqttUser}/$id/temperatura';
  String get topicStatus => 'farmacias/${AppConfig.mqttUser}/$id/status';
  String get topicOnline => 'farmacias/${AppConfig.mqttUser}/$id/online';
}

class TempReading {
  final double temperatura;
  final DateTime timestamp;
  final String heladeraId;
  final String cliente;

  const TempReading({
    required this.temperatura,
    required this.timestamp,
    required this.heladeraId,
    required this.cliente,
  });

  factory TempReading.fromMqttPayload(String payload, String heladeraId) {
    final map = json.decode(payload) as Map<String, dynamic>;
    return TempReading(
      temperatura: (map['temperatura'] as num).toDouble(),
      timestamp: DateTime.now(),
      heladeraId: heladeraId,
      cliente: map['cliente'] as String? ?? AppConfig.mqttUser,
    );
  }

  Map<String, dynamic> toJson() => {
        'temperatura': temperatura,
        'timestamp': timestamp.toIso8601String(),
        'heladeraId': heladeraId,
        'cliente': cliente,
      };

  factory TempReading.fromJson(Map<String, dynamic> map) => TempReading(
        temperatura: (map['temperatura'] as num).toDouble(),
        timestamp: DateTime.parse(map['timestamp'] as String),
        heladeraId: map['heladeraId'] as String? ??
            map['heladera'] as String? ?? 'heladera1',
        cliente: map['cliente'] as String? ?? '',
      );

  bool get isInRange =>
      temperatura >= AppConfig.tempMin && temperatura <= AppConfig.tempMax;
  bool get isWarning =>
      temperatura > AppConfig.tempWarnThreshold &&
      temperatura <= AppConfig.tempMax;
  bool get isCritical =>
      temperatura < AppConfig.tempMin || temperatura > AppConfig.tempMax;
}

enum BatteryLevel { ok, low, critical, unknown }

class DeviceStatus {
  final String heladeraId;
  final BatteryLevel batteryLevel;
  final double? voltaje;
  final bool sensorOk;
  final DateTime timestamp;

  const DeviceStatus({
    required this.heladeraId,
    this.batteryLevel = BatteryLevel.unknown,
    this.voltaje,
    this.sensorOk = true,
    required this.timestamp,
  });

  factory DeviceStatus.fromMqttPayload(String payload, String heladeraId) {
    final map = json.decode(payload) as Map<String, dynamic>;
    final nivelStr = map['nivel_bateria'] as String? ?? 'OK';
    BatteryLevel nivel;
    switch (nivelStr.toUpperCase()) {
      case 'OK': nivel = BatteryLevel.ok; break;
      case 'BAJA': nivel = BatteryLevel.low; break;
      case 'CRITICA': nivel = BatteryLevel.critical; break;
      default: nivel = BatteryLevel.unknown;
    }
    return DeviceStatus(
      heladeraId: heladeraId,
      batteryLevel: nivel,
      voltaje: map['voltaje_bateria'] != null
          ? double.tryParse(map['voltaje_bateria'].toString())
          : null,
      sensorOk: map['sensor_ok'] as bool? ?? true,
      timestamp: DateTime.now(),
    );
  }
}

class SensorOnlineStatus {
  final String heladeraId;
  final bool online;
  final DateTime timestamp;

  const SensorOnlineStatus({
    required this.heladeraId,
    required this.online,
    required this.timestamp,
  });

  factory SensorOnlineStatus.fromMqttPayload(String payload, String heladeraId) {
    final map = json.decode(payload) as Map<String, dynamic>;
    return SensorOnlineStatus(
      heladeraId: heladeraId,
      online: map['online'] as bool? ?? false,
      timestamp: DateTime.now(),
    );
  }
}

// Sentinel para distinguir null explícito de "no cambiar"
const _sentinel = Object();

class HeladeraState {
  final Heladera heladera;
  final TempReading? lastReading;
  final List<TempReading> history;
  final DeviceStatus? deviceStatus;
  final DateTime? lastUpdate;
  final bool sensorOnline;

  const HeladeraState({
    required this.heladera,
    this.lastReading,
    this.history = const [],
    this.deviceStatus,
    this.lastUpdate,
    this.sensorOnline = false,
  });

  HeladeraState copyWith({
    Object? lastReading = _sentinel,
    List<TempReading>? history,
    Object? deviceStatus = _sentinel,
    Object? lastUpdate = _sentinel,
    bool? sensorOnline,
  }) =>
      HeladeraState(
        heladera: heladera,
        lastReading: lastReading == _sentinel ? this.lastReading : lastReading as TempReading?,
        history: history ?? this.history,
        deviceStatus: deviceStatus == _sentinel ? this.deviceStatus : deviceStatus as DeviceStatus?,
        lastUpdate: lastUpdate == _sentinel ? this.lastUpdate : lastUpdate as DateTime?,
        sensorOnline: sensorOnline ?? this.sensorOnline,
      );
}

enum ConnectionStatus { disconnected, connecting, connected, error }

class AppState {
  final List<HeladeraState> heladeras;
  final ConnectionStatus connectionStatus;
  final String? errorMessage;

  const AppState({
    this.heladeras = const [],
    this.connectionStatus = ConnectionStatus.disconnected,
    this.errorMessage,
  });

  AppState copyWith({
    List<HeladeraState>? heladeras,
    ConnectionStatus? connectionStatus,
    String? errorMessage,
  }) =>
      AppState(
        heladeras: heladeras ?? this.heladeras,
        connectionStatus: connectionStatus ?? this.connectionStatus,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  HeladeraState? getHeladera(String id) {
    try {
      return heladeras.firstWhere((h) => h.heladera.id == id);
    } catch (_) {
      return null;
    }
  }
}
