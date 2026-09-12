import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  // ── Estado de suspensión por falta de pago ──────────────
  bool servicioSuspendido = false;
  String? mensajeSuspension;

  /// Llamado desde cualquier consulta HTTP (de este servicio o de las
  /// pantallas) que reciba un 402 del servidor.
  void marcarComoSuspendido(String? mensaje) {
    if (servicioSuspendido && mensajeSuspension == mensaje) return; // sin cambios
    servicioSuspendido = true;
    mensajeSuspension = mensaje ?? 'Servicio suspendido por falta de pago.';
    notifyListeners();
  }

  /// Llamado cuando una consulta vuelve a responder 200 normalmente,
  /// para salir del estado de suspensión (ej. después de marcar el pago).
  void limpiarSuspension() {
    if (!servicioSuspendido) return;
    servicioSuspendido = false;
    mensajeSuspension = null;
    notifyListeners();
  }

  AppState get state => _state;
  List<Heladera> get heladeras => _heladeras;
  ConnectionStatus get status => _state.connectionStatus;

  /// [heladerasSesion] son las heladeras que devolvió el servidor en /login.
  /// Solo se usan para inicializar la primera vez (si no hay nada guardado
  /// localmente todavía); si el usuario ya las editó desde Ajustes, se
  /// respeta lo guardado en el dispositivo.
  Future<void> init({List<Map<String, String>>? heladerasSesion}) async {
    await _loadHeladeras(heladerasSesion: heladerasSesion);
    // NOTA: ya no se hace fetch de /ultimos aca. HomeScreen ahora hace
    // su propia consulta independiente al abrirse, para no bloquear la
    // transicion de Login -> MainShell esperando esta consulta primero.

    unawaited(_verificarEstadoServicio()); // chequeo rapido, en paralelo
    unawaited(_loadHistory());
    // Retrasamos el intento de conexion MQTT un par de segundos: si
    // arranca en simultaneo con el fetch HTTP de arriba, puede competir
    // por el isolate y demorar que la UI se actualice con el valor real
    // recien traido.
    Future.delayed(const Duration(seconds: 2), () {
      if (!_disposed) connect();
    });
    _startWatchdog();
    debugPrint('[DIAG] init() termina (UI deberia mostrarse ya): \${DateTime.now().difference(t0).inMilliseconds}ms');
  }

  static const String _apiBase = 'https://vigilanciatermica.duckdns.org';

  /// Consulta /ultimos (una sola vez, todas las heladeras juntas) y
  /// precarga los últimos valores reales conocidos, así la pantalla
  /// principal muestra algo de inmediato al abrir la app en vez de
  /// esperar al próximo mensaje MQTT o hacer N consultas separadas.
  Future<void> _fetchUltimosValores() async {
    try {
      final uri = Uri.parse('$_apiBase/ultimos?farmacia=${AppConfig.mqttUser}');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 402) {
        final data = json.decode(res.body);
        marcarComoSuspendido(data['mensaje'] as String?);
        return;
      }
      if (res.statusCode != 200) return;
      limpiarSuspension();
      final data = json.decode(res.body);
      if (data['ok'] != true) return;

      final Map<String, dynamic> heladerasData = data['heladeras'] ?? {};
      for (final h in _heladeras) {
        final info = heladerasData[h.id];
        if (info == null || info['temperatura'] == null) continue;

        final reading = TempReading(
          temperatura: (info['temperatura'] as num).toDouble(),
          timestamp: DateTime.parse(info['time']).toLocal(),
          heladeraId: h.id,
          cliente: AppConfig.mqttUser,
        );
        _updateHeladeraState(h.id, (s) => s.copyWith(lastReading: reading));
      }
    } catch (e) {
      // Silencioso: si falla, el valor llega igual con el próximo MQTT.
      debugPrint('No se pudieron precargar los últimos valores: $e');
    }
  }

  // ── Watchdog: verifica cada 30s si llegaron datos recientes ──
  int _umbralDesconexionSeg = 120; // default 2 min, configurable
  int get umbralDesconexionSeg => _umbralDesconexionSeg;

  Future<void> _cargarUmbralDesconexion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mins = prefs.getInt('push_desconexion_min') ?? 2;
      _umbralDesconexionSeg = mins * 60;
    } catch (_) {}
  }

  void actualizarUmbralDesconexion(int minutos) {
    _umbralDesconexionSeg = minutos * 60;
  }

  /// Chequeo liviano de si el servicio sigue habilitado. Reutiliza
  /// /ultimo (una sola heladera alcanza, no hace falta consultar todas)
  /// solo para leer el status code; no nos interesa el valor en sí acá,
  /// eso ya lo trae el MQTT en vivo.
  /// Wrapper público: permite forzar una reverificación manual (ej. desde
  /// el botón "Ya regularicé, reintentar" de la pantalla de suspensión),
  /// sin esperar a que pase el próximo ciclo del watchdog.
  Future<void> reverificarEstadoServicio() => _verificarEstadoServicio();

  Future<void> _verificarEstadoServicio() async {
    if (_heladeras.isEmpty) return;
    try {
      final uri = Uri.parse(
          '$_apiBase/ultimo?farmacia=${AppConfig.mqttUser}&heladera=${_heladeras.first.id}');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 402) {
        final data = json.decode(res.body);
        marcarComoSuspendido(data['mensaje'] as String?);
      } else if (res.statusCode == 200) {
        limpiarSuspension();
      }
      // Otros códigos (ej. 500, timeout): no tocamos el estado de
      // suspensión, puede ser un problema de red pasajero, no de pago.
    } catch (_) {
      // sin conexión: tampoco tocamos el estado, para no mostrar el
      // cartel de suspendido por un simple corte de internet momentáneo
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _cargarUmbralDesconexion();
    int ticks = 0;
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_disposed) return;

      // Cada 4 ticks (~2 min) revisamos si el servicio sigue habilitado.
      // No hace falta más seguido: si se bloquea, no es una emergencia
      // de temperatura, y así no generamos tráfico HTTP de más.
      ticks++;
      if (ticks % 4 == 0) {
        _verificarEstadoServicio();
      }

      final ahora = DateTime.now();
      for (final h in _heladeras) {
        final ultima = _lastDataTime[h.id];
        final hs = _state.getHeladera(h.id);
        if (ultima == null || hs == null) continue;
        final diff = ahora.difference(ultima).inSeconds;
        if (diff > _umbralDesconexionSeg && hs.sensorOnline) {
          _updateHeladeraState(h.id, (s) => s.copyWith(sensorOnline: false));
          if (_wasEverOnline[h.id] == true) {
            final mins = (diff / 60).round();
            NotificationService().showDeviceDisconnectedMins(h.nombre, mins);
          }
          debugPrint("Watchdog: ${h.id} sin datos por ${diff}s -> offline");
        }
        if (diff <= _umbralDesconexionSeg && !hs.sensorOnline && _wasEverOnline[h.id] == true) {
          _updateHeladeraState(h.id, (s) => s.copyWith(sensorOnline: true));
          debugPrint("Watchdog: ${h.id} volvio online");
        }
      }
    });
  }

  // ── Gestión de heladeras ──────────────────────────────
  Future<void> _loadHeladeras(
      {List<Map<String, String>>? heladerasSesion}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppConfig.prefKeyHeladeras);
      if (raw != null) {
        _heladeras = (json.decode(raw) as List)
            .map((e) => Heladera.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (heladerasSesion != null && heladerasSesion.isNotEmpty) {
        _heladeras = heladerasSesion
            .map((h) => Heladera(id: h['id']!, nombre: h['nombre']!))
            .toList();
        await _saveHeladeras();
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
      _client.subscribe(AppConfig.topicEstadoPago(newId), MqttQos.atLeastOnce);
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

    _client = MqttServerClient(AppConfig.serverHost, AppConfig.mqttClientId);
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
      _client.subscribe(AppConfig.topicEstadoPago(h.id), MqttQos.atLeastOnce);
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
      if (topic == AppConfig.topicEstadoPago(h.id)) {
        _processEstadoPago(raw, h.id); return;
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

  // ── Procesar estado de pago ────────────────────
  void _processEstadoPago(String raw, String heladeraId) {
    try {
      final ep = EstadoPago.fromMqttPayload(raw);
      _updateHeladeraState(
          heladeraId,
          (hs) => hs.copyWith(
                estadoPago: ep.estado,
                diasMora: ep.diasMora,
              ));
    } catch (e) {
      debugPrint('Error procesando estado de pago: $e');
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
          // Cargar el historial para la gráfica. lastReading/sensorOnline
          // NO se tocan acá: ya pueden venir seteados por
          // _fetchUltimosValores() con un valor real reciente del servidor.
          // Pisarlos con null (como se hacía antes) causaba que el valor
          // recién cargado desapareciera un instante después, hasta que
          // llegara el próximo mensaje MQTT.
          newStates.add(hs.copyWith(history: list));
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
