import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models/temp_reading.dart';
import 'notification_service.dart';

class MqttService extends ChangeNotifier {
  late MqttServerClient _client;
  AppState _state = const AppState();
  List<Heladera> _heladeras = [];

  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  final Map<String, Timer?> _disconnectTimers = {};
  final Map<String, bool> _wasEverOnline = {};
  final Map<String, DateTime?> _lastDataTime = {};
  final Map<String, DateTime> _sessionStart = {};

  bool _disposed = false;
  bool _mqttConnected = false;

  AppState get state => _state;
  List<Heladera> get heladeras => _heladeras;
  ConnectionStatus get status => _state.connectionStatus;

  Future<void> init() async {
    await _loadHeladeras();
    await _loadHistory();
    await connect();
    _startWatchdog();
  }

  // ── Watchdog: verifica cada 30s si llegaron datos recientes ──
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_disposed) return;
      final ahora = DateTime.now();
      for (final h in _heladeras) {
        final ultima = _lastDataTime[h.id];
        final hs = _state.getHeladera(h.id);
        if (ultima == null || hs == null) continue;
        final diff = ahora.difference(ultima).inSeconds;
        if (diff > 120 && hs.sensorOnline) {
          _updateHeladeraState(h.id, (s) => s.copyWith(sensorOnline: false));
          if (_wasEverOnline[h.id] == true) {
            NotificationService().showDeviceDisconnected(h.nombre);
          }
          debugPrint("Watchdog: ${h.id} sin datos por ${diff}s -> offline");
        }
        if (diff <= 120 && !hs.sensorOnline && _wasEverOnline[h.id] == true) {
          _updateHeladeraState(h.id, (s) => s.copyWith(sensorOnline: true));
          debugPrint("Watchdog: ${h.id} volvio online");
        }
      }
    });
  }

  // ── Gestión de heladeras ──────────────────────────────
  Future<void> _loadHeladeras() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppConfig.prefKeyHeladeras);
      if (raw != null) {
        _heladeras = (json.decode(raw) as List)
            .map((e) => Heladera.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _heladeras = [const Heladera(id: 'heladera1', nombre: 'Heladera 1')];
        await _saveHeladeras();
      }
      _initHeladeraStates();
    } catch (e) {
      _heladeras = [const Heladera(id: 'heladera1', nombre: 'Heladera 1')];
      _initHeladeraStates();
    }
  }

  void _initHeladeraStates() {
    final states = _heladeras.map((h) => HeladeraState(heladera: h)).toList();
    _setState(_state.copyWith(heladeras: states));
  }

  Future<void> _saveHeladeras() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.prefKeyHeladeras,
        json.encode(_heladeras.map((h) => h.toJson()).toList()));
  }

  Future<void> addHeladera(String nombre) async {
    final existingIds = _heladeras.map((h) => h.id).toList();
    int num = _heladeras.length + 1;
    String newId = 'heladera$num';
    while (existingIds.contains(newId)) {
      num++;
      newId = 'heladera$num';
    }
    final nueva = Heladera(id: newId, nombre: nombre);
    _heladeras.add(nueva);
    await _saveHeladeras();

    _setState(_state.copyWith(
      heladeras: [..._state.heladeras, HeladeraState(heladera: nueva)],
    ));

    if (_mqttConnected) {
      _client.subscribe(AppConfig.topicTemperatura(newId), MqttQos.atLeastOnce);
      _client.subscribe(AppConfig.topicStatus(newId), MqttQos.atLeastOnce);
      _client.subscribe(AppConfig.topicOnline(newId), MqttQos.atLeastOnce);
    }
  }

  Future<void> updateHeladeraName(String id, String nombre) async {
    _heladeras = _heladeras
        .map((h) => h.id == id ? h.copyWith(nombre: nombre) : h)
        .toList();
    await _saveHeladeras();

    final newStates = _state.heladeras.map((hs) {
      if (hs.heladera.id != id) return hs;
      return HeladeraState(
        heladera: hs.heladera.copyWith(nombre: nombre),
        lastReading: hs.lastReading,
        history: hs.history,
        deviceStatus: hs.deviceStatus,
        lastUpdate: hs.lastUpdate,
        sensorOnline: hs.sensorOnline,
      );
    }).toList();
    _setState(_state.copyWith(heladeras: newStates));
  }

  Future<void> removeHeladera(String id) async {
    _heladeras.removeWhere((h) => h.id == id);
    await _saveHeladeras();
    _disconnectTimers[id]?.cancel();
    _disconnectTimers.remove(id);
    _wasEverOnline.remove(id);
    _setState(_state.copyWith(
      heladeras: _state.heladeras.where((hs) => hs.heladera.id != id).toList(),
    ));
  }

  // ── Conexión MQTT ─────────────────────────────────────
  Future<void> connect() async {
    _setState(_state.copyWith(
        connectionStatus: ConnectionStatus.connecting, errorMessage: null));

    _client = MqttServerClient(AppConfig.mqttHost, AppConfig.mqttClientId);
    _client.port = AppConfig.mqttPort;
    _client.keepAlivePeriod = AppConfig.keepAlivePeriod;
    _client.onDisconnected = _onDisconnected;
    _client.onConnected = _onConnected;
    _client.logging(on: kDebugMode);

    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(AppConfig.mqttClientId)
        .authenticateAs(AppConfig.mqttUser, AppConfig.mqttPassword)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    try {
      await _client.connect();
    } catch (e) {
      _onError('Error: $e');
      return;
    }

    if (_client.connectionStatus?.state == MqttConnectionState.connected) {
      _subscribe();
    } else {
      _onError('No se pudo conectar');
    }
  }

  void _subscribe() {
    for (final h in _heladeras) {
      _client.subscribe(AppConfig.topicTemperatura(h.id), MqttQos.atLeastOnce);
      _client.subscribe(AppConfig.topicStatus(h.id), MqttQos.atLeastOnce);
      _client.subscribe(AppConfig.topicOnline(h.id), MqttQos.atLeastOnce);
    }

    _client.updates?.listen((messages) {
      for (final msg in messages) {
        final payload = msg.payload as MqttPublishMessage;
        final raw = MqttPublishPayload.bytesToStringAsString(
            payload.payload.message);
        _routeMessage(msg.topic, raw);
      }
    });
  }

  void _routeMessage(String topic, String raw) {
    for (final h in _heladeras) {
      if (topic == AppConfig.topicTemperatura(h.id)) {
        _processTemperature(raw, h.id); return;
      }
      if (topic == AppConfig.topicStatus(h.id)) {
        _processStatus(raw, h.id); return;
      }
      if (topic == AppConfig.topicOnline(h.id)) {
        _processOnline(raw, h.id); return;
      }
    }
  }

  // ── Procesar temperatura ──────────────────────────────
  void _processTemperature(String raw, String heladeraId) {
    try {
      final reading = TempReading.fromMqttPayload(raw, heladeraId);
      final current = _state.getHeladera(heladeraId);
      final oldHistory = current?.history ?? [];
      final newHistory = [...oldHistory, reading];
      final trimmed = newHistory.length > AppConfig.maxHistoryPoints
          ? newHistory.sublist(newHistory.length - AppConfig.maxHistoryPoints)
          : newHistory;

      // Marcar sensor como online al recibir datos
      _wasEverOnline[heladeraId] = true;
      _lastDataTime[heladeraId] = DateTime.now();
      // Registrar inicio de sesión (primera vez que llegan datos tras arrancar)
      _sessionStart.putIfAbsent(heladeraId, () => DateTime.now());
      _resetDisconnectTimer(heladeraId);

      _updateHeladeraState(heladeraId, (hs) => hs.copyWith(
            lastReading: reading,
            history: trimmed,
            lastUpdate: DateTime.now(),
            sensorOnline: true,
          ));

      _saveHistoryForHeladera(heladeraId, trimmed);
      _checkTempAlerts(reading, heladeraId);
    } catch (e) {
      debugPrint('Error procesando temperatura: $e');
    }
  }

  // ── Procesar status (batería) ─────────────────────────
  void _processStatus(String raw, String heladeraId) {
    try {
      final status = DeviceStatus.fromMqttPayload(raw, heladeraId);
      _updateHeladeraState(
          heladeraId, (hs) => hs.copyWith(deviceStatus: status));

      if (status.batteryLevel == BatteryLevel.critical) {
        final h = _heladeras.firstWhere((h) => h.id == heladeraId,
            orElse: () => Heladera(id: heladeraId, nombre: heladeraId));
        NotificationService().showBatteryAlert(h.nombre, status.voltaje);
      }
    } catch (e) {
      debugPrint('Error procesando status: $e');
    }
  }

  // ── Procesar online/offline ───────────────────────────
  void _processOnline(String raw, String heladeraId) {
    try {
      final onlineStatus = SensorOnlineStatus.fromMqttPayload(raw, heladeraId);
      final h = _heladeras.firstWhere((h) => h.id == heladeraId,
          orElse: () => Heladera(id: heladeraId, nombre: heladeraId));

      if (onlineStatus.online) {
        // Sensor volvió online
        _wasEverOnline[heladeraId] = true;
        _resetDisconnectTimer(heladeraId);
        _updateHeladeraState(
            heladeraId, (hs) => hs.copyWith(sensorOnline: true));
      } else {
        // Sensor se cayó — LWT del broker
        _disconnectTimers[heladeraId]?.cancel();
        _updateHeladeraState(
            heladeraId, (hs) => hs.copyWith(sensorOnline: false));

        // Notificación inmediata
        if (_wasEverOnline[heladeraId] == true) {
          NotificationService().showDeviceDisconnected(h.nombre);
        }
      }
    } catch (e) {
      debugPrint('Error procesando online: $e');
    }
  }

  // ── Publicar mensaje MQTT ────────────────────────────
  void publishMessage(String topic, MqttClientPayloadBuilder payload) {
    try {
      if (_mqttConnected) {
        _client.publishMessage(topic, MqttQos.atLeastOnce, payload.payload!);
        debugPrint('MQTT publicado: $topic');
      } else {
        debugPrint('MQTT no conectado, no se pudo publicar: $topic');
      }
    } catch (e) {
      debugPrint('Error publicando mensaje MQTT: $e');
    }
  }

  // ── Timer de desconexión por heladera ─────────────────
  // Backup por si el LWT no llega (pérdida de WiFi sin desconexión limpia)
  void _resetDisconnectTimer(String heladeraId) {
    _disconnectTimers[heladeraId]?.cancel();
    _disconnectTimers[heladeraId] = Timer(
      Duration(minutes: AppConfig.disconnectNotifMinutes),
      () {
        if (_disposed) return;
        _updateHeladeraState(
            heladeraId, (hs) => hs.copyWith(sensorOnline: false));
        if (_wasEverOnline[heladeraId] == true) {
          final h = _heladeras.firstWhere((h) => h.id == heladeraId,
              orElse: () => Heladera(id: heladeraId, nombre: heladeraId));
          NotificationService().showDeviceDisconnected(h.nombre);
        }
      },
    );
  }

  // ── Alertas de temperatura ────────────────────────────
  void _checkTempAlerts(TempReading reading, String heladeraId) {
    final h = _heladeras.firstWhere((h) => h.id == heladeraId,
        orElse: () => Heladera(id: heladeraId, nombre: heladeraId));
    if (reading.isCritical) {
      NotificationService().showTempAlert(reading.temperatura, h.nombre);
    } else if (reading.isWarning) {
      NotificationService().showWarningAlert(reading.temperatura, h.nombre);
    }
  }

  // ── Callbacks MQTT ────────────────────────────────────
  void _onConnected() {
    _mqttConnected = true;
    _reconnectTimer?.cancel();
    _setState(_state.copyWith(
        connectionStatus: ConnectionStatus.connected, errorMessage: null));
  }

  void _onDisconnected() {
    if (_disposed) return;
    _mqttConnected = false;
    _setState(
        _state.copyWith(connectionStatus: ConnectionStatus.disconnected));
    _scheduleReconnect();
  }

  void _onError(String message) {
    _setState(_state.copyWith(
        connectionStatus: ConnectionStatus.error, errorMessage: message));
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: AppConfig.reconnectDelaySeconds),
      () { if (!_disposed) connect(); },
    );
  }

  // ── Helpers ───────────────────────────────────────────
  void _updateHeladeraState(
      String id, HeladeraState Function(HeladeraState) updater) {
    final newStates = _state.heladeras.map((hs) {
      if (hs.heladera.id == id) return updater(hs);
      return hs;
    }).toList();
    _setState(_state.copyWith(heladeras: newStates));
  }

  void _setState(AppState newState) {
    _state = newState;
    if (!_disposed) notifyListeners();
  }

  DateTime? sessionStart(String heladeraId) => _sessionStart[heladeraId];

  String get connectionLabel {
    switch (_state.connectionStatus) {
      case ConnectionStatus.connected: return 'Conectado';
      case ConnectionStatus.connecting: return 'Conectando...';
      case ConnectionStatus.disconnected: return 'Desconectado';
      case ConnectionStatus.error: return 'Error';
    }
  }

  // ── Persistencia ──────────────────────────────────────
  Future<void> _saveHistoryForHeladera(
      String id, List<TempReading> readings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${AppConfig.prefKeyHistory}_$id',
          json.encode(readings.map((r) => r.toJson()).toList()));
    } catch (e) {
      debugPrint('Error guardando historial: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final newStates = <HeladeraState>[];
      for (final hs in _state.heladeras) {
        final raw =
            prefs.getString('${AppConfig.prefKeyHistory}_${hs.heladera.id}');
        if (raw != null) {
          final list = (json.decode(raw) as List)
              .map((e) => TempReading.fromJson(e as Map<String, dynamic>))
              .toList();
          // Cargar historial para la grafica pero NO mostrar temperatura
          // ni marcar online hasta recibir datos reales
          newStates.add(hs.copyWith(
            history: list,
            lastReading: null,   // sin valor hasta recibir dato real
            debugPrint('ARRANQUE: ${hs.heladera.id} lastReading seteado a null'),
            sensorOnline: false, // sin señal hasta recibir dato real
            lastUpdate: null,
          ));
        } else {
          newStates.add(hs);
        }
      }
      _setState(_state.copyWith(heladeras: newStates));
    } catch (e) {
      debugPrint('Error cargando historial: $e');
    }
  }

  Future<void> clearHistory(String heladeraId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${AppConfig.prefKeyHistory}_$heladeraId');
    _updateHeladeraState(heladeraId, (hs) => hs.copyWith(history: []));
  }

  Future<void> clearAllHistory() async {
    for (final h in _heladeras) {
      await clearHistory(h.id);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _watchdogTimer?.cancel();
    for (final t in _disconnectTimers.values) t?.cancel();
    _client.disconnect();
    super.dispose();
  }
}

