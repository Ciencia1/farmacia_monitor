import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/temp_reading.dart';
import '../theme/app_theme.dart';
import '../config.dart';

// ── Badge de conexión al broker ───────────────────────
class ConnectionBadge extends StatelessWidget {
  final String label;
  final bool connected;

  const ConnectionBadge({super.key, required this.label, required this.connected});

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppTheme.tempOk : AppTheme.tempDanger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: color, fontSize: 11,
                  fontWeight: FontWeight.w500, letterSpacing: 0.05)),
        ],
      ),
    );
  }
}

// ── Mini stat card ────────────────────────────────────
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  const StatCard({super.key, required this.label, required this.value,
      this.valueColor, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: AppTheme.textMuted, size: 12),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(label.toUpperCase(),
                    style: const TextStyle(color: AppTheme.textMuted,
                        fontSize: 9, letterSpacing: 0.06),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? AppTheme.textPrimary,
                  fontSize: 18, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Gráfico de historial ─────────────────────────────
// Cuando el sensor está offline, la línea se interrumpe
class TempHistoryChart extends StatelessWidget {
  final List<TempReading> readings;
  final bool sensorOnline;

  const TempHistoryChart({
    super.key,
    required this.readings,
    this.sensorOnline = true,
  });

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return const Center(
        child: Text('Sin datos de historial',
            style: TextStyle(color: AppTheme.textMuted)),
      );
    }

    final pts = readings.length > 60
        ? readings.sublist(readings.length - 60)
        : readings;

    final spots = pts.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.temperatura))
        .toList();

    final minY =
        (pts.map((r) => r.temperatura).reduce((a, b) => a < b ? a : b) - 1)
            .clamp(-6.0, 0.0);
    final maxY =
        (pts.map((r) => r.temperatura).reduce((a, b) => a > b ? a : b) + 1)
            .clamp(9.0, 16.0);

    // Color de la línea: gris si offline, verde si online
    final lineColor = sensorOnline ? AppTheme.tempOk : AppTheme.textMuted;

    return Stack(
      children: [
        LineChart(
          LineChartData(
            minY: minY, maxY: maxY,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              show: true, drawVerticalLine: false, horizontalInterval: 2,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppTheme.border, strokeWidth: 0.5),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true, reservedSize: 30, interval: 2,
                  getTitlesWidget: (val, _) => Text('${val.toInt()}°',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 10)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true, reservedSize: 20,
                  interval: (pts.length / 4).ceilToDouble(),
                  getTitlesWidget: (val, _) {
                    final idx = val.toInt();
                    if (idx < 0 || idx >= pts.length) return const SizedBox();
                    return Text(DateFormat('HH:mm').format(pts[idx].timestamp),
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 9));
                  },
                ),
              ),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
            ),
            extraLinesData: ExtraLinesData(horizontalLines: [
              HorizontalLine(
                y: AppConfig.tempMax,
                color: AppTheme.tempDanger.withOpacity(0.5),
                strokeWidth: 1, dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true, alignment: Alignment.topRight,
                  labelResolver: (_) => '8°C',
                  style: const TextStyle(color: AppTheme.tempDanger, fontSize: 10),
                ),
              ),
              HorizontalLine(
                y: AppConfig.tempMin,
                color: AppTheme.tempCold.withOpacity(0.5),
                strokeWidth: 1, dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true, alignment: Alignment.bottomRight,
                  labelResolver: (_) => '2°C',
                  style: const TextStyle(color: AppTheme.tempCold, fontSize: 10),
                ),
              ),
            ]),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true, curveSmoothness: 0.3,
                color: lineColor,
                barWidth: 2, isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, _, __, ___) {
                    final temp = spot.y;
                    final c = sensorOnline
                        ? AppTheme.tempColor(temp)
                        : AppTheme.textMuted;
                    final showDot = sensorOnline &&
                        (temp < AppConfig.tempMin ||
                            temp > AppConfig.tempWarnThreshold);
                    return FlDotCirclePainter(
                      radius: showDot ? 4 : 0,
                      color: c,
                      strokeWidth: showDot ? 2 : 0,
                      strokeColor: Colors.white,
                    );
                  },
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      lineColor.withOpacity(0.18),
                      lineColor.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => AppTheme.bgCard,
                tooltipBorder: const BorderSide(color: AppTheme.border),
                getTooltipItems: (spots) => spots.map((s) {
                  final idx = s.spotIndex;
                  final reading = idx < pts.length ? pts[idx] : null;
                  final time = reading != null
                      ? DateFormat('HH:mm').format(reading.timestamp)
                      : '';
                  return LineTooltipItem(
                    '${s.y.toStringAsFixed(1)}°C\n',
                    TextStyle(
                        color: sensorOnline
                            ? AppTheme.tempColor(s.y)
                            : AppTheme.textMuted,
                        fontWeight: FontWeight.w600, fontSize: 13),
                    children: [
                      TextSpan(text: time,
                          style: const TextStyle(color: AppTheme.textMuted,
                              fontSize: 10, fontWeight: FontWeight.normal)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        // Banner de "sin señal" sobre el gráfico cuando está offline
        if (!sensorOnline)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: AppTheme.tempDanger.withOpacity(0.15),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off_rounded,
                      color: AppTheme.tempDanger, size: 12),
                  SizedBox(width: 4),
                  Text('Sensor sin señal — último dato conocido',
                      style: TextStyle(
                          color: AppTheme.tempDanger,
                          fontSize: 10,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
