import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  int _hoursBack = 6;
  String? _selectedHeladeraId;

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

        // Seleccionar primera heladera por defecto
        final selectedId = _selectedHeladeraId ?? heladeras.first.heladera.id;
        final heladeraState = widget.mqtt.state.getHeladera(selectedId)
            ?? heladeras.first;

        final cutoff = DateTime.now().subtract(Duration(hours: _hoursBack));
        final filtered = heladeraState.history
            .where((r) => r.timestamp.isAfter(cutoff))
            .toList();
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
                onSelect: (id) => setState(() => _selectedHeladeraId = id),
              ),
              const SizedBox(height: 10),
            ],

            // ── Selector de rango temporal ─────────────
            _TimeRangeSelector(
              selected: _hoursBack,
              onSelect: (h) => setState(() => _hoursBack = h),
            ),
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
                  ? const Center(
                      child: Text('Sin datos para el período',
                          style: TextStyle(color: AppTheme.textMuted)))
                  : TempHistoryChart(readings: filtered),
            ),
            const SizedBox(height: 12),

            // ── Stats ──────────────────────────────────
            if (temps.isNotEmpty)
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
                          ? AppTheme.tempOk
                          : AppTheme.tempDanger,
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
                              style: TextStyle(
                                  color: AppTheme.textSecondary)),
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
          final isSelected = h.id == selectedId;
          return GestureDetector(
            onTap: () => onSelect(h.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 7),
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
              child: Text(
                h.nombre,
                style: TextStyle(
                  color: isSelected
                      ? AppTheme.tempOk
                      : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
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
            ? 'Temperatura alta'
            : 'Temperatura baja';
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
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppTheme.border, width: 0.5)),
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
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeRangeSelector extends StatelessWidget {
  final int selected;
  final void Function(int) onSelect;

  const _TimeRangeSelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final options = [(1, '1h'), (6, '6h'), (12, '12h'), (24, '24h')];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Row(
        children: options.map((opt) {
          final isSelected = opt.$1 == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.tempOk.withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: isSelected
                      ? Border.all(
                          color: AppTheme.tempOk.withOpacity(0.4),
                          width: 0.5)
                      : null,
                ),
                child: Text(opt.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.tempOk
                          : AppTheme.textMuted,
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
