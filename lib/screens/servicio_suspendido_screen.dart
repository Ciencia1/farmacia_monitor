import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Pantalla de bloqueo que se muestra cuando el servidor indica que la
/// farmacia no está al día con el pago (respuesta 402 en cualquier
/// endpoint). Reemplaza a MainShell por completo mientras dure el
/// bloqueo — no se puede navegar a Temperatura/Historial/Ajustes desde
/// acá, solo cerrar sesión.
class ServicioSuspendidoScreen extends StatelessWidget {
  final String mensaje;
  final VoidCallback onLogout;
  final VoidCallback onReintentar;

  const ServicioSuspendidoScreen({
    super.key,
    required this.mensaje,
    required this.onLogout,
    required this.onReintentar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppTheme.tempWarn.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_clock_rounded,
                  color: AppTheme.tempWarn,
                  size: 44,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Servicio suspendido',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'El dispositivo en la heladera sigue midiendo la '
                'temperatura con normalidad; solo el acceso a esta app '
                'está pausado hasta regularizar el pago.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onReintentar,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Ya regularicé, reintentar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.tempOk,
                    side: const BorderSide(color: AppTheme.tempOk),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onLogout,
                  child: const Text(
                    'Cerrar sesión',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
