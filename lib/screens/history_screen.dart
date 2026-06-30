import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/temp_reading.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import '../config.dart';

class HistoryScreen extends StatefulWidget {
  final MqttService mqtt;
  const HistoryScreen({super.key, required this.mqtt});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Rango fijo de historial: 48 horas (2 días). No es configurable por el usuario.
  static const int _hoursBack = 48;
  int _semanasReporte = 1;
  String? _selectedHeladeraId;

  // Datos desde API
  List<TempReading> _apiReadings = [];
  Map<String, dynamic>? _apiStats;
  bool _loadingApi = false;
  bool _usandoApi = false;
  String? _apiError;
  bool _enviandoReporte = false;

  static const String _apiBase = 'http://168.75.110.69:5000';

  @override
  void initState() {
    super.initState();
  }

  // Se llama automáticamente al construir la pantalla (primera vez) y al
  // cambiar de heladera, para que los datos siempre vengan del servidor
  // sin que el usuario tenga que tocar nada.
  void _cargarAutomaticoSiCorresponde(String heladeraId) {
    if (!_loadingApi && !_usandoApi) {
      // Evita reentradas durante el mismo build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_usandoApi && !_loadingApi) {
          _cargarDesdeApi(heladeraId);
        }
      });
    }
  }

  Future<void> _cargarDesdeApi(String heladeraId) async {
    setState(() { _loadingApi = true; _apiError = null; });
    try {
      final uri = Uri.parse(
        '$_apiBase/historial?farmacia=${AppConfig.mqttUser}&heladera=$heladeraId&horas=$_hoursBack'
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List<dynamic> datos = data['datos'];
        final readings = datos.map((d) => TempReading(
          temperatura: (d['temp'] as num).toDouble(),
          timestamp: DateTime.parse(d['time']).toLocal(),
          heladeraId: heladeraId,
          cliente: AppConfig.mqttUser,
        )).toList();

        // Stats
        final statsUri = Uri.parse(
          '$_apiBase/estadisticas?farmacia=${AppConfig.mqttUser}&heladera=$heladeraId&horas=$_hoursBack'
        );
        final statsRes = await http.get(statsUri).timeout(const Duration(seconds: 10));
        Map<String, dynamic>? stats;
        if (statsRes.statusCode == 200) {
          stats = json.decode(statsRes.body);
        }

        setState(() {
          _apiReadings = readings;
          _apiStats = stats;
          _usandoApi = true;
          _loadingApi = false;
        });
      } else {
        throw Exception('Error ${res.statusCode}');
      }
    } catch (e) {
      setState(() {
        _apiError = 'No se pudo conectar al servidor';
        _loadingApi = false;
        _usandoApi = false;
      });
    }
  }

  Future<void> _solicitarReporte(String heladeraId) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email_reportes') ?? '';
    if (email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurá un email en Ajustes primero'),
            backgroundColor: AppTheme.tempDanger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _enviandoReporte = true);
    try {
      final topic = 'farmacias/${AppConfig.mqttUser}/config/reporte_ahora';
      final payload = MqttClientPayloadBuilder();
      payload.addString(json.encode({
        'email': email,
        'heladera': heladeraId,
        'semanas': _semanasReporte,
      }));
      widget.mqtt.publishMessage(topic, payload);

      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reporte solicitado — llegará a $email en unos segundos'),
            backgroundColor: AppTheme.tempOk,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviandoReporte = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.mqtt,
      builder: (context, _) {
        final heladeras = widget.mqtt.state.heladeras;

        if (heladeras.isEmpty) {
          return const Center(
            child: Text('Sin heladeras configuradas',
                style: TextStyle(color: AppTheme.textMuted)),
          );
        }

        final selectedId = _selectedHeladeraId ?? heladeras.first.heladera.id;
        final heladeraState = widget.mqtt.state.getHeladera(selectedId) ?? heladeras.first;

        // Carga automática desde el servidor: la primera vez que se entra a
        // la pantalla y cada vez que se cambia de heladera.
        _cargarAutomaticoSiCorresponde(selectedId);

        // Usar datos de API si están disponibles, sino historial local
        final cutoff = DateTime.now().subtract(const Duration(hours: _hoursBack));
        final localFiltered = heladeraState.history
            .where((r) => r.timestamp.isAfter(cutoff))
            .toList();
        final filtered = _usandoApi ? _apiReadings : localFiltered;
        final temps = filtered.map((r) => r.temperatura).toList();
        final events = _buildEventLog(filtered);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [

            // ── Selector de heladera ───────────────────
            if (heladeras.length > 1) ...[
              _HeladeraSelector(
                heladeras: heladeras.map((h) => h.heladera).toList(),
                selectedId: selectedId,
                onSelect: (id) {
                  setState(() {
                    _selectedHeladeraId = id;
                    _usandoApi = false;
                    _apiReadings = [];
                    _apiStats = null;
                    // La carga automática se dispara solita en el próximo build
                    // (ver _cargarAutomaticoSiCorresponde), porque _usandoApi
                    // queda en false.
                  });
                },
              ),
              const SizedBox(height: 10),
            ],

            // ── Botones API y Reporte ──────────────────
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _loadingApi ? null : () {
                      setState(() { _usandoApi = false; });
                      _cargarDesdeApi(selectedId);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _usandoApi
                            ? AppTheme.tempOk.withOpacity(0.15)
                            : AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _usandoApi
                              ? AppTheme.tempOk.withOpacity(0.4)
                              : AppTheme.border,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_loadingApi)
                            const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.tempOk),
                            )
                          else
                            Icon(
                              Icons.refresh_rounded,
                              color: _usandoApi ? AppTheme.tempOk : AppTheme.textSecondary,
                              size: 16,
                            ),
                          const SizedBox(width: 6),
                          Text(
                            'Actualizar',
                            style: TextStyle(
                              color: _usandoApi ? AppTheme.tempOk : AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: _enviandoReporte ? null : () => _mostrarDialogoReporte(context, selectedId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border, width: 0.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_enviandoReporte)
                            const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.tempOk),
                            )
                          else
                            const Icon(Icons.email_outlined,
                                color: AppTheme.textSecondary, size: 16),
                          const SizedBox(width: 6),
                          const Text('Pedir reporte',
                              style: TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (_apiError != null) ...[
              const SizedBox(height: 8),
              Text(_apiError!,
                  style: TextStyle(
                      color: AppTheme.tempDanger.withOpacity(0.8),
                      fontSize: 11)),
            ],
            const SizedBox(height: 12),

            // ── Gráfico ────────────────────────────────
            Container(
              height: 200,
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _usandoApi ? 'Sin datos del servidor' : 'Sin datos para el período',
                        style: const TextStyle(color: AppTheme.textMuted),
                      ))
                  : TempHistoryChart(readings: filtered),
            ),
            const SizedBox(height: 12),

            // ── Stats ──────────────────────────────────
            if (_usandoApi && _apiStats != null && _apiStats!['ok'] == true)
              Row(
                children: [
                  Expanded(child: StatCard(
                    label: 'Promedio',
                    value: '${_apiStats!['promedio']}°C',
                    icon: Icons.analytics_outlined,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: StatCard(
                    label: 'Mínima',
                    value: '${_apiStats!['minima']}°C',
                    icon: Icons.arrow_downward_rounded,
                    valueColor: AppTheme.tempCold,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: StatCard(
                    label: 'Máxima',
                    value: '${_apiStats!['maxima']}°C',
                    icon: Icons.arrow_upward_rounded,
                    valueColor: AppTheme.tempDanger,
                  )),
                ],
              )
            else if (temps.isNotEmpty)
              Row(
                children: [
                  Expanded(child: StatCard(
                    label: 'Promedio',
                    value: '${(temps.reduce((a, b) => a + b) / temps.length).toStringAsFixed(1)}°C',
                    icon: Icons.analytics_outlined,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: StatCard(
                    label: 'Mínima',
                    value: '${temps.reduce((a, b) => a < b ? a : b).toStringAsFixed(1)}°C',
                    icon: Icons.arrow_downward_rounded,
                    valueColor: AppTheme.tempCold,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: StatCard(
                    label: 'Máxima',
                    value: '${temps.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}°C',
                    icon: Icons.arrow_upward_rounded,
                    valueColor: AppTheme.tempDanger,
                  )),
                ],
              ),
            const SizedBox(height: 16),

            // ── Registro de eventos ────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('REGISTRO DE EVENTOS',
                    style: TextStyle(color: AppTheme.textMuted,
                        fontSize: 10, letterSpacing: 0.1)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: events.isEmpty
                        ? AppTheme.tempOk.withOpacity(0.1)
                        : AppTheme.tempDanger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    events.isEmpty ? 'Sin eventos' : '${events.length}',
                    style: TextStyle(
                      color: events.isEmpty ? AppTheme.tempOk : AppTheme.tempDanger,
                      fontSize: 11, fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: events.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Column(children: [
                          Icon(Icons.check_circle_rounded,
                              color: AppTheme.tempOk, size: 32),
                          SizedBox(height: 8),
                          Text('Sin eventos en el período',
                              style: TextStyle(color: AppTheme.textSecondary)),
                        ]),
                      ),
                    )
                  : Column(
                      children: events.map((e) => _EventRow(event: e)).toList(),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _mostrarDialogoReporte(BuildContext context, String heladeraId) {
    int semanas = _semanasReporte;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: const Text('Solicitar reporte por email',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Período del reporte:',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [1, 2, 3, 4].map((s) {
                  final selected = semanas == s;
                  return GestureDetector(
                    onTap: () => setS(() => semanas = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.tempOk.withOpacity(0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? AppTheme.tempOk.withOpacity(0.5)
                              : AppTheme.border,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        s == 1 ? '1 sem' : '$s sem',
                        style: TextStyle(
                          color: selected ? AppTheme.tempOk : AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                setState(() => _semanasReporte = semanas);
                Navigator.pop(ctx);
                _solicitarReporte(heladeraId);
              },
              child: const Text('Enviar',
                  style: TextStyle(color: AppTheme.tempOk)),
            ),
          ],
        ),
      ),
    );
  }

  List<_TempEvent> _buildEventLog(List<TempReading> readings) {
    final events = <_TempEvent>[];
    bool wasOutOfRange = false;

    for (final r in readings) {
      if (r.isCritical && !wasOutOfRange) {
        events.add(_TempEvent(type: _EventType.outOfRange, reading: r));
        wasOutOfRange = true;
      } else if (r.isWarning && !wasOutOfRange) {
        events.add(_TempEvent(type: _EventType.warning, reading: r));
      } else if (!r.isCritical && !r.isWarning && wasOutOfRange) {
        events.add(_TempEvent(type: _EventType.stabilized, reading: r));
        wasOutOfRange = false;
      }
    }

    return events.reversed.toList();
  }
}

// ── Selector de heladera ──────────────────────────────
class _HeladeraSelector extends StatelessWidget {
  final List<Heladera> heladeras;
  final String selectedId;
  final void Function(String) onSelect;

  const _HeladeraSelector({
    required this.heladeras, required this.selectedId, required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: heladeras.map((h) {
          final isSelected = h.id == selectedId;
          return GestureDetector(
            onTap: () => onSelect(h.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.tempOk.withOpacity(0.15)
                    : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.tempOk.withOpacity(0.5)
                      : AppTheme.border,
                  width: 0.5,
                ),
              ),
              child: Text(h.nombre,
                  style: TextStyle(
                    color: isSelected ? AppTheme.tempOk : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  )),
            ),
          );
        }).toList(),
      ),
    );
  }
}

enum _EventType { warning, outOfRange, stabilized }

class _TempEvent {
  final _EventType type;
  final TempReading reading;
  const _TempEvent({required this.type, required this.reading});
}

class _EventRow extends StatelessWidget {
  final _TempEvent event;
  const _EventRow({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    Color color;
    String title;
    String subtitle;
    IconData icon;

    switch (event.type) {
      case _EventType.outOfRange:
        color = AppTheme.tempDanger;
        title = event.reading.temperatura > AppConfig.tempMax
            ? 'Temperatura alta' : 'Temperatura baja';
        subtitle = 'Fuera de rango';
        icon = Icons.warning_rounded;
        break;
      case _EventType.warning:
        color = AppTheme.tempWarn;
        title = 'Advertencia';
        subtitle = 'Próximo al límite';
        icon = Icons.info_rounded;
        break;
      case _EventType.stabilized:
        color = AppTheme.tempOk;
        title = 'Sistema estabilizado';
        subtitle = 'Temperatura normalizada';
        icon = Icons.check_circle_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12, fontWeight: FontWeight.w500)),
                Text(subtitle, style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 10)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${event.reading.temperatura.toStringAsFixed(1)}°C',
                  style: TextStyle(color: color,
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text(
                DateFormat('dd/MM HH:mm').format(event.reading.timestamp),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


