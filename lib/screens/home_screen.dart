import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/temp_reading.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../config.dart';

class HomeScreen extends StatefulWidget {
  final MqttService mqtt;
  const HomeScreen({super.key, required this.mqtt});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _apiBase = 'http://168.75.110.69:5000';

  /// Último valor conocido por consulta HTTP directa, independiente de
  /// MqttService. Se usa solo mientras MQTT todavía no trajo nada (hs.
  /// lastReading == null); apenas MQTT entrega un dato real, ese pasa a
  /// mandar y esto queda de lado.
  final Map<String, TempReading> _prefetch = {};

  @override
  void initState() {
    super.initState();
    _fetchInicial();
  }

  Future<void> _fetchInicial() async {
    try {
      final uri =
          Uri.parse('$_apiBase/ultimos?farmacia=${AppConfig.mqttUser}');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = json.decode(res.body);
      if (data['ok'] != true) return;

      final Map<String, dynamic> heladerasData = data['heladeras'] ?? {};
      final nuevos = <String, TempReading>{};
      heladerasData.forEach((hid, info) {
        if (info == null || info['temperatura'] == null) return;
        nuevos[hid] = TempReading(
          temperatura: (info['temperatura'] as num).toDouble(),
          timestamp: DateTime.parse(info['time']).toLocal(),
          heladeraId: hid,
          cliente: AppConfig.mqttUser,
        );
      });

      if (mounted) setState(() => _prefetch.addAll(nuevos));
    } catch (e) {
      debugPrint('HomeScreen: no se pudo precargar /ultimos: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.mqtt,
      builder: (context, _) {
        final heladeras = widget.mqtt.state.heladeras;

        if (heladeras.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.kitchen_rounded,
                    color: AppTheme.textMuted, size: 48),
                const SizedBox(height: 16),
                const Text('Sin heladeras configuradas',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 15)),
                const SizedBox(height: 8),
                const Text('Agregá una desde Ajustes',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: heladeras.map((hs) {
            // Si MQTT todavía no trajo nada para esta heladera, usamos
            // el valor precargado por HTTP (si lo tenemos) para mostrar
            // algo real de inmediato en vez de esperar.
            final hsEfectivo = hs.lastReading == null &&
                    _prefetch.containsKey(hs.heladera.id)
                ? hs.copyWith(
                    lastReading: _prefetch[hs.heladera.id],
                    sensorOnline: true,
                  )
                : hs;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _HeladeraCard(heladeraState: hsEfectivo),
            );
          }).toList(),
        );
      },
    );
  }
}

class _HeladeraCard extends StatelessWidget {
  final HeladeraState heladeraState;
  const _HeladeraCard({required this.heladeraState});

  @override
  Widget build(BuildContext context) {
    final reading = heladeraState.lastReading;
    final temp = reading?.temperatura;
    final sensorOnline = heladeraState.sensorOnline;
    final deviceStatus = heladeraState.deviceStatus;

    // Si el sensor está offline mostramos estado especial
    final color = !sensorOnline
        ? AppTheme.textMuted
        : temp != null
            ? AppTheme.tempColor(temp)
            : AppTheme.textMuted;

    final statusText = !sensorOnline
        ? 'SIN SEÑAL'
        : temp != null
            ? AppTheme.tempStatus(temp)
            : 'Sin datos';

    final icon = !sensorOnline
        ? Icons.wifi_off_rounded
        : temp != null
            ? AppTheme.tempIcon(temp)
            : Icons.device_unknown;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.kitchen_rounded,
                  color: AppTheme.textSecondary, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  heladeraState.heladera.nombre.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    letterSpacing: 0.1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _SensorIndicator(online: sensorOnline),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 10),
              sensorOnline && temp != null
                  ? RichText(
                      text: TextSpan(children: [
                        TextSpan(
                          text: temp.toStringAsFixed(1),
                          style: TextStyle(
                            color: color,
                            fontSize: 52,
                            fontWeight: FontWeight.w200,
                            letterSpacing: -1,
                            height: 1,
                          ),
                        ),
                        TextSpan(
                          text: '°C',
                          style: TextStyle(
                            color: color.withOpacity(0.7),
                            fontSize: 22,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ]),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('—',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 52,
                              fontWeight: FontWeight.w200,
                            )),
                        if (!sensorOnline && reading != null)
                          Text(
                            'Último: ${reading.temperatura.toStringAsFixed(1)}°C',
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 11),
                          ),
                      ],
                    ),
              const Spacer(),
              if (deviceStatus != null && sensorOnline)
                _BatteryBadge(level: deviceStatus.batteryLevel),
            ],
          ),
          const SizedBox(height: 10),

          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: color.withOpacity(0.3), width: 0.5),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.08,
              ),
            ),
          ),

          if (heladeraState.lastUpdate != null) ...[
            const SizedBox(height: 8),
            Text(
              sensorOnline
                  ? 'Última lectura: ${DateFormat('HH:mm:ss').format(heladeraState.lastUpdate!)}'
                  : 'Sin señal desde: ${DateFormat('HH:mm:ss').format(heladeraState.lastUpdate!)}',
              style: TextStyle(
                color: sensorOnline
                    ? AppTheme.textMuted
                    : AppTheme.tempDanger.withOpacity(0.7),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SensorIndicator extends StatelessWidget {
  final bool online;
  const _SensorIndicator({required this.online});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: online
            ? AppTheme.tempOk.withOpacity(0.1)
            : AppTheme.tempDanger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: online
              ? AppTheme.tempOk.withOpacity(0.4)
              : AppTheme.tempDanger.withOpacity(0.4),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: online ? AppTheme.tempOk : AppTheme.tempDanger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            online ? 'En línea' : 'Sin señal',
            style: TextStyle(
              color: online ? AppTheme.tempOk : AppTheme.tempDanger,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BatteryBadge extends StatelessWidget {
  final BatteryLevel level;
  const _BatteryBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    switch (level) {
      case BatteryLevel.ok:
        color = AppTheme.tempOk;
        icon = Icons.battery_full_rounded;
        break;
      case BatteryLevel.low:
        color = AppTheme.tempWarn;
        icon = Icons.battery_2_bar_rounded;
        break;
      case BatteryLevel.critical:
        color = AppTheme.tempDanger;
        icon = Icons.battery_alert_rounded;
        break;
      default:
        return const SizedBox();
    }
    return Icon(icon, color: color, size: 22);
  }
}
