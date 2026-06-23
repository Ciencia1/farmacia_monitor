import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_client.dart';
import '../config.dart';
import '../models/temp_reading.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  final MqttService mqtt;
  const SettingsScreen({super.key, required this.mqtt});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushEnabled = true;
  bool _emailAlertsEnabled = true;
  bool _monthlyReportEnabled = true;
  final _emailController = TextEditingController();
  bool _enviandoTest = false;
  int _pushDesconexionMin = 2;
  int _emailDesconexionMin = 25;

  @override
  void initState() {
    super.initState();
    _cargarEmail();
    _cargarTiemposAlerta();
  }

  Future<void> _cargarTiemposAlerta() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _pushDesconexionMin = prefs.getInt('push_desconexion_min') ?? 2;
        _emailDesconexionMin = prefs.getInt('email_desconexion_min') ?? 25;
      });
    }
  }

  Future<void> _guardarPushMinutos(int minutos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('push_desconexion_min', minutos);
    setState(() => _pushDesconexionMin = minutos);
    widget.mqtt.actualizarUmbralDesconexion(minutos);
  }

  Future<void> _guardarEmailMinutos(int minutos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('email_desconexion_min', minutos);
    setState(() => _emailDesconexionMin = minutos);
    _publicarMinutosAlertaMqtt(minutos);
  }

  void _publicarMinutosAlertaMqtt(int minutos) {
    try {
      final topic = 'farmacias/\${AppConfig.mqttUser}/config/alerta_minutos';
      final payload = MqttClientPayloadBuilder();
      payload.addString(minutos.toString());
      widget.mqtt.publishMessage(topic, payload);
    } catch (e) {
      debugPrint('Error publicando minutos alerta: \$e');
    }
  }

  Future<void> _cargarEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email_reportes') ?? '';
    if (mounted) setState(() => _emailController.text = email);
  }

  Future<void> _guardarEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ingresá un email válido'),
            backgroundColor: AppTheme.tempDanger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('email_reportes', email);
    _publicarEmailMqtt(email);
    if (mounted) {
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email guardado correctamente'),
          backgroundColor: AppTheme.tempOk,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _publicarEmailMqtt(String email) {
    try {
      final topic = 'farmacias/${AppConfig.mqttUser}/config/email';
      final payload = MqttClientPayloadBuilder();
      payload.addString(email);
      widget.mqtt.publishMessage(topic, payload);
    } catch (e) {
      debugPrint('Error publicando email MQTT: $e');
    }
  }

  Future<void> _enviarEmailTest() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email_reportes') ?? '';
    if (email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Primero guardá un email'),
            backgroundColor: AppTheme.tempDanger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    setState(() => _enviandoTest = true);
    try {
      final topic = 'farmacias/${AppConfig.mqttUser}/config/test_email';
      final payload = MqttClientPayloadBuilder();
      payload.addString(email);
      widget.mqtt.publishMessage(topic, payload);
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email de prueba enviado a $email'),
            backgroundColor: AppTheme.tempOk,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviandoTest = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.mqtt,
      builder: (context, _) {
        final heladeras = widget.mqtt.heladeras;
        final isConnected =
            widget.mqtt.status == ConnectionStatus.connected;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [

            // ── Heladeras ──────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('HELADERAS',
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                        letterSpacing: 0.1)),
                GestureDetector(
                  onTap: () => _showAddHeladeraDialog(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.tempOk.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: AppTheme.tempOk.withOpacity(0.4),
                          width: 0.5),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.add_rounded,
                            color: AppTheme.tempOk, size: 14),
                        SizedBox(width: 4),
                        Text('Agregar',
                            style: TextStyle(
                                color: AppTheme.tempOk, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (heladeras.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border, width: 0.5),
                ),
                child: const Center(
                  child: Text('Sin heladeras. Tocá "Agregar" para empezar.',
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 12)),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border, width: 0.5),
                ),
                child: Column(
                  children: heladeras.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final h = entry.value;
                    final isLast = idx == heladeras.length - 1;
                    return _HeladeraRow(
                      heladera: h,
                      isLast: isLast,
                      onEdit: () => _showEditDialog(context, h),
                      onDelete: heladeras.length > 1
                          ? () => _confirmDelete(context, h)
                          : null,
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 16),

            // ── Notificaciones ─────────────────────────
            const Text('NOTIFICACIONES Y REPORTES',
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    letterSpacing: 0.1)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: Column(
                children: [
                  _EmailRow(
                    controller: _emailController,
                    onSave: _guardarEmail,
                  ),
                  _ToggleRow(
                    label: 'Reporte PDF mensual',
                    subtitle: 'Primer día de cada mes',
                    value: _monthlyReportEnabled,
                    onChanged: (v) =>
                        setState(() => _monthlyReportEnabled = v),
                  ),
                  _ToggleRow(
                    label: 'Alertas por email',
                    subtitle: 'Temperatura fuera de rango',
                    value: _emailAlertsEnabled,
                    onChanged: (v) =>
                        setState(() => _emailAlertsEnabled = v),
                  ),
                  _ToggleRow(
                    label: 'Notificaciones push',
                    subtitle: 'Alertas en el celular',
                    value: _pushEnabled,
                    onChanged: (v) => setState(() => _pushEnabled = v),
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Tiempos de alerta ──────────────────────
            const Text('TIEMPOS DE ALERTA',
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    letterSpacing: 0.1)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: Column(
                children: [
                  _MinutosSelectorRow(
                    label: 'Notificación push',
                    subtitle: 'Avisar si no hay datos por más de',
                    opciones: const [2, 5, 10, 20],
                    valorActual: _pushDesconexionMin,
                    onSelect: _guardarPushMinutos,
                  ),
                  _MinutosSelectorRow(
                    label: 'Email de alerta',
                    subtitle: 'Enviar email si no hay datos por más de',
                    opciones: const [15, 25, 30, 60],
                    valorActual: _emailDesconexionMin,
                    onSelect: _guardarEmailMinutos,
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Estado ─────────────────────────────────
            const Text('ESTADO DEL SISTEMA',
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    letterSpacing: 0.1)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: Column(
                children: [
                  _InfoRow('Conexión',
                      isConnected ? 'Conectado' : 'Desconectado',
                      valueColor: isConnected
                          ? AppTheme.tempOk
                          : AppTheme.tempDanger),
                  _InfoRow('Servidor', AppConfig.mqttHost),
                  _InfoRow('Heladeras activas', '${heladeras.length}',
                      isLast: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Acciones ───────────────────────────────
            const Text('ACCIONES',
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    letterSpacing: 0.1)),
            const SizedBox(height: 8),
            _ActionButton(
              icon: Icons.email_outlined,
              label: _enviandoTest ? 'Enviando...' : 'Enviar email de prueba',
              onTap: _enviandoTest ? () {} : _enviarEmailTest,
            ),
            const SizedBox(height: 8),
            _ActionButton(
              icon: Icons.wifi_rounded,
              label: 'Reconectar',
              onTap: () {
                widget.mqtt.connect();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Reconectando...'),
                    backgroundColor: AppTheme.bgCard,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _ActionButton(
              icon: Icons.delete_outline_rounded,
              label: 'Limpiar historial',
              color: AppTheme.tempDanger,
              onTap: () => _confirmClearHistory(context),
            ),
            const SizedBox(height: 24),

            const Center(
              child: Text(
                'Farmacia Monitor v1.0.0',
                style:
                    TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Diálogos ──────────────────────────────────────────
  void _showAddHeladeraDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Nueva heladera',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Ej: Vacunas, Insulinas...',
            hintStyle: TextStyle(color: AppTheme.textMuted),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.border)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.tempOk)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final nombre = controller.text.trim();
              if (nombre.isNotEmpty) {
                widget.mqtt.addHeladera(nombre);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Agregar',
                style: TextStyle(color: AppTheme.tempOk)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, Heladera h) {
    final controller = TextEditingController(text: h.nombre);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Editar nombre',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.border)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.tempOk)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final nombre = controller.text.trim();
              if (nombre.isNotEmpty) {
                widget.mqtt.updateHeladeraName(h.id, nombre);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Guardar',
                style: TextStyle(color: AppTheme.tempOk)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Heladera h) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text('Eliminar ${h.nombre}',
            style: const TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
            '¿Eliminás esta heladera y su historial?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar',
                style: TextStyle(color: AppTheme.tempDanger)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      widget.mqtt.removeHeladera(h.id);
    }
  }

  void _confirmClearHistory(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Limpiar historial',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
            '¿Eliminás el historial de todas las heladeras?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Limpiar',
                style: TextStyle(color: AppTheme.tempDanger)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      widget.mqtt.clearAllHistory();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Historial eliminado'),
            backgroundColor: AppTheme.bgCard,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ── Fila de heladera ──────────────────────────────────
class _HeladeraRow extends StatelessWidget {
  final Heladera heladera;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _HeladeraRow({
    required this.heladera,
    required this.isLast,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.kitchen_rounded,
              color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(heladera.nombre,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13)),
                Text(heladera.id,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10)),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded,
                color: AppTheme.textMuted, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppTheme.tempDanger, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Widgets reutilizables ─────────────────────────────
class _ToggleRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final void Function(bool) onChanged;
  final bool isLast;

  const _ToggleRow({
    required this.label, required this.subtitle,
    required this.value, required this.onChanged, this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(
            bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 13)),
                Text(subtitle, style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value, onChanged: onChanged,
            activeColor: AppTheme.tempOk,
            activeTrackColor: AppTheme.tempOk.withOpacity(0.3),
            inactiveThumbColor: AppTheme.textMuted,
            inactiveTrackColor: AppTheme.border,
          ),
        ],
      ),
    );
  }
}

class _EmailRow extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSave;

  const _EmailRow({required this.controller, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Email de reportes',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'farmacia@ejemplo.com',
                    hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    isDense: true, contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => onSave(),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onSave,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.check_circle_outline_rounded,
                  color: AppTheme.tempOk, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isLast;

  const _InfoRow(this.label, this.value, {this.valueColor, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(
            bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 13)),
          Text(value, style: TextStyle(
              color: valueColor ?? AppTheme.textPrimary,
              fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionButton({required this.icon, required this.label,
      required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: (color ?? AppTheme.border).withOpacity(0.4), width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(
                color: c, fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: c.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}

class _MinutosSelectorRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final List<int> opciones;
  final int valorActual;
  final void Function(int) onSelect;
  final bool isLast;

  const _MinutosSelectorRow({
    required this.label,
    required this.subtitle,
    required this.opciones,
    required this.valorActual,
    required this.onSelect,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 13)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 11)),
          const SizedBox(height: 10),
          Row(
            children: opciones.map((min) {
              final selected = min == valorActual;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(min),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 8),
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
                      '$min min',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? AppTheme.tempOk
                            : AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
