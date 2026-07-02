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
  // Siempre muestra las últimas 24 horas desde el servidor
  static const int _horas = 24;

  String? _selectedHeladeraId;
  List<TempReading> _readings = [];
  Map<String, dynamic>? _stats;
  bool _loading = false;
  String? _error;
  bool _enviandoReporte = false;
  int _semanasReporte = 1;

  static const String _apiBase = 'http://168.75.110.69:5000';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final heladeras = widget.mqtt.state.heladeras;
      if (heladeras.isNotEmpty) {
        final id = _selectedHeladeraId ?? heladeras.first.heladera.id;
        _cargar(id);
      }
    });
  }

  Future<void> _cargar(String heladeraId) async {
    setState(() { _loading = true; _error = null; });
    try {
      // Historial
      final uri = Uri.parse(
        '$_apiBase/historial?farmacia=${AppConfig.mqttUser}'
        '&heladera=$heladeraId&horas=$_horas'
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception('Error ${res.statusCode}');

      final data = json.decode(res.body);
      final readings = (data['datos'] as List).map((d) => TempReading(
        temperatura: (d['temp'] as num).toDouble(),
        timestamp: DateTime.parse(d['time']).toLocal(),
        heladeraId: heladeraId,
        cliente: AppConfig.mqttUser,
      )).toList();

      // Estadísticas
      final statsUri = Uri.parse(
        '$_apiBase/estadisticas?farmacia=${AppConfig.mqttUser}'
        '&heladera=$heladeraId&horas=$_horas'
      );
      Map<String, dynamic>? stats;
      try {
        final sr = await http.get(statsUri).timeout(const Duration(seconds: 10));
        if (sr.statusCode == 200) stats = json.decode(sr.body);
      } catch (_) {}

      setState(() {
        _readings = readings;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No se pudo conectar al servidor';
        _loading = false;
        _readings = [];
      });
    }
  }

  Future<void> _solicitarReporte(String heladeraId) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email_reportes') ?? '';
    if (email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Configurá un email en Ajustes primero'),
          backgroundColor: AppTheme.tempDanger,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    setState(() => _enviandoReporte = true);
    try {
      final payload = MqttClientPayloadBuilder();
      payload.addString(json.encode({
        'email': email,
        'heladera': heladeraId,
        'semanas': _semanasReporte,
      }));
      widget.mqtt.publishMessage(
        'farmacias/${AppConfig.mqttUser}/config/reporte_ahora', payload);
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reporte enviado a $email'),
          backgroundColor: AppTheme.tempOk,
          behavior: SnackBarBehavior.floating,
        ));
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
          return const Center(child: Text('Sin heladeras configuradas',
              style: TextStyle(color: AppTheme.textMuted)));
        }

        final selectedId = _selectedHeladeraId ?? heladeras.first.heladera.id;
        final events = _buildEvents(_readings);
        final temps = _readings.map((r) => r.temperatura).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [

            // ── Selector de heladera ───────────────
            if (heladeras.length > 1) ...[
              _HeladeraSelector(
                heladeras: heladeras.map((h) => h.heladera).toList(),
                selectedId: selectedId,
                onSelect: (id) {
                  setState(() {
                    _selectedHeladeraId = id;
                    _readings = [];
                    _stats = null;
                  });
                  _cargar(id);
                },
              ),
              const SizedBox(height: 10),
            ],

            // ── Encabezado ─────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Icon(Icons.history_rounded,
                      color: AppTheme.textMuted, size: 14),
                  const SizedBox(width: 5),
                  const Text('Últimas 24 horas',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  if (_loading) ...[
                    const SizedBox(width: 8),
                    const SizedBox(width: 10, height: 10,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: AppTheme.tempOk)),
                  ],
                ]),
                GestureDetector(
                  onTap: _loading ? null : () => _cargar(selectedId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border, width: 0.5),
                    ),
                    child: const Row(children: [
                      Icon(Icons.refresh_rounded,
                          color: AppTheme.textSecondary, size: 13),
                      SizedBox(width: 4),
                      Text('Actualizar',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11)),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Botón reporte ──────────────────────
            GestureDetector(
              onTap: _enviandoReporte
                  ? null
                  : () => _mostrarDialogoReporte(context, selectedId),
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
                      const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.tempOk))
                    else
                      const Icon(Icons.email_outlined,
                          color: AppTheme.textSecondary, size: 16),
                    const SizedBox(width: 6),
                    const Text('Pedir reporte por email',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(
                      color: AppTheme.tempDanger.withOpacity(0.8),
                      fontSize: 11)),
            ],
            const SizedBox(height: 12),

            // ── Gráfico ────────────────────────────
            Container(
              height: 200,
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.tempOk))
                  : _readings.isEmpty
                      ? Center(child: Text(
                          _error != null
                              ? 'Sin conexión al servidor'
                              : 'Sin datos en las últimas 24 horas',
                          style: const TextStyle(color: AppTheme.textMuted)))
                      : TempHistoryChart(readings: _readings),
            ),
            const SizedBox(height: 12),

            // ── Stats ──────────────────────────────
            if (temps.isNotEmpty)
              Row(children: [
                Expanded(child: StatCard(
                  label: 'Promedio',
                  value: _stats?['ok'] == true
                      ? '${_stats!['promedio']}°C'
                      : '${(temps.reduce((a,b)=>a+b)/temps.length).toStringAsFixed(1)}°C',
                  icon: Icons.analytics_outlined,
                )),
                const SizedBox(width: 8),
                Expanded(child: StatCard(
                  label: 'Mínima',
                  value: _stats?['ok'] == true
                      ? '${_stats!['minima']}°C'
                      : '${temps.reduce((a,b)=>a<b?a:b).toStringAsFixed(1)}°C',
                  icon: Icons.arrow_downward_rounded,
                  valueColor: AppTheme.tempCold,
                )),
                const SizedBox(width: 8),
                Expanded(child: StatCard(
                  label: 'Máxima',
                  value: _stats?['ok'] == true
                      ? '${_stats!['maxima']}°C'
                      : '${temps.reduce((a,b)=>a>b?a:b).toStringAsFixed(1)}°C',
                  icon: Icons.arrow_upward_rounded,
                  valueColor: AppTheme.tempDanger,
                )),
              ]),
            const SizedBox(height: 16),

            // ── Registro de eventos ────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('REGISTRO DE EVENTOS',
                    style: TextStyle(color: AppTheme.textMuted,
                        fontSize: 10, letterSpacing: 0.1)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: events.isEmpty
                        ? AppTheme.tempOk.withOpacity(0.1)
                        : AppTheme.tempDanger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    events.isEmpty ? 'Sin eventos' : '${events.length}',
                    style: TextStyle(
                      color: events.isEmpty
                          ? AppTheme.tempOk : AppTheme.tempDanger,
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
                      child: Center(child: Column(children: [
                        Icon(Icons.check_circle_rounded,
                            color: AppTheme.tempOk, size: 32),
                        SizedBox(height: 8),
                        Text('Sin eventos en el período',
                            style: TextStyle(
                                color: AppTheme.textSecondary)),
                      ])))
                  : Column(
                      children: events.map((e) => _EventRow(event: e)).toList(),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _mostrarDialogoReporte(BuildContext ctx, String heladeraId) {
    int semanas = _semanasReporte;
    showDialog(
      context: ctx,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
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
                  final sel = semanas == s;
                  return GestureDetector(
                    onTap: () => setS(() => semanas = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppTheme.tempOk.withOpacity(0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: sel
                              ? AppTheme.tempOk.withOpacity(0.5)
                              : AppTheme.border,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        s == 1 ? '1 sem' : '$s sem',
                        style: TextStyle(
                          color: sel
                              ? AppTheme.tempOk : AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: sel
                              ? FontWeight.w600 : FontWeight.normal,
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
              onPressed: () => Navigator.pop(ctx2),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                setState(() => _semanasReporte = semanas);
                Navigator.pop(ctx2);
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

  List<_TempEvent> _buildEvents(List<TempReading> readings) {
    final events = <_TempEvent>[];
    bool wasOut = false;
    for (final r in readings) {
      if (r.isCritical && !wasOut) {
        events.add(_TempEvent(type: _EventType.outOfRange, reading: r));
        wasOut = true;
      } else if (r.isWarning && !wasOut) {
        events.add(_TempEvent(type: _EventType.warning, reading: r));
      } else if (!r.isCritical && !r.isWarning && wasOut) {
        events.add(_TempEvent(type: _EventType.stabilized, reading: r));
        wasOut = false;
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
    required this.heladeras,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: heladeras.map((h) {
          final sel = h.id == selectedId;
          return GestureDetector(
            onTap: () => onSelect(h.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: sel
                    ? AppTheme.tempOk.withOpacity(0.15)
                    : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: sel
                      ? AppTheme.tempOk.withOpacity(0.5)
                      : AppTheme.border,
                  width: 0.5,
                ),
              ),
              child: Text(h.nombre,
                  style: TextStyle(
                    color: sel
                        ? AppTheme.tempOk : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: sel
                        ? FontWeight.w600 : FontWeight.normal,
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
      case _EventType.warning:
        color = AppTheme.tempWarn;
        title = 'Advertencia';
        subtitle = 'Próximo al límite';
        icon = Icons.info_rounded;
      case _EventType.stabilized:
        color = AppTheme.tempOk;
        title = 'Sistema estabilizado';
        subtitle = 'Temperatura normalizada';
        icon = Icons.check_circle_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12, fontWeight: FontWeight.w500)),
            Text(subtitle, style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 10)),
          ],
        )),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${event.reading.temperatura.toStringAsFixed(1)}°C',
                style: TextStyle(
                    color: color,
                    fontSize: 13, fontWeight: FontWeight.w600)),
            Text(
              DateFormat('dd/MM HH:mm').format(event.reading.timestamp),
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 10),
            ),
          ],
        ),
      ]),
    );
  }
}
