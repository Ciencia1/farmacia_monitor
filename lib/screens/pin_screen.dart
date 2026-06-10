import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class PinScreen extends StatefulWidget {
  final bool isSetup; // true = crear PIN, false = ingresar PIN
  final VoidCallback onSuccess;

  const PinScreen({super.key, required this.isSetup, required this.onSuccess});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> with SingleTickerProviderStateMixin {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  int _intentosFallidos = 0;
  bool _bloqueado = false;
  int _segundosBloqueado = 0;
  String _error = '';

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (_bloqueado) return;
    final current = widget.isSetup && _isConfirming ? _confirmPin : _pin;
    if (current.length >= 4) return;

    setState(() {
      _error = '';
      if (widget.isSetup && _isConfirming) {
        _confirmPin += digit;
        if (_confirmPin.length == 4) _validarSetup();
      } else {
        _pin += digit;
        if (_pin.length == 4) {
          if (widget.isSetup) {
            setState(() => _isConfirming = true);
          } else {
            _validarIngreso();
          }
        }
      }
    });
  }

  void _onDelete() {
    if (_bloqueado) return;
    setState(() {
      _error = '';
      if (widget.isSetup && _isConfirming) {
        if (_confirmPin.isNotEmpty) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        }
      } else {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      }
    });
  }

  Future<void> _validarSetup() async {
    if (_pin == _confirmPin) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_pin', _pin);
      widget.onSuccess();
    } else {
      _shakeController.forward(from: 0);
      setState(() {
        _error = 'Los PINs no coinciden. Intentá de nuevo.';
        _pin = '';
        _confirmPin = '';
        _isConfirming = false;
      });
    }
  }

  Future<void> _validarIngreso() async {
    final prefs = await SharedPreferences.getInstance();
    final pinGuardado = prefs.getString('app_pin') ?? '';
    if (_pin == pinGuardado) {
      await prefs.setInt('intentos_fallidos', 0);
      widget.onSuccess();
    } else {
      _shakeController.forward(from: 0);
      _intentosFallidos++;
      await prefs.setInt('intentos_fallidos', _intentosFallidos);
      setState(() {
        _pin = '';
        if (_intentosFallidos >= 3) {
          _bloqueado = true;
          _error = '';
          _iniciarBloqueo();
        } else {
          _error = 'PIN incorrecto. ${3 - _intentosFallidos} intento${3 - _intentosFallidos == 1 ? "" : "s"} restante${3 - _intentosFallidos == 1 ? "" : "s"}.';
        }
      });
    }
  }

  void _iniciarBloqueo() {
    _segundosBloqueado = 60;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _segundosBloqueado--);
      if (_segundosBloqueado <= 0) {
        setState(() {
          _bloqueado = false;
          _intentosFallidos = 0;
          _error = '';
        });
        return false;
      }
      return true;
    });
  }

  String get _titulo {
    if (widget.isSetup) {
      return _isConfirming ? 'Confirmá tu PIN' : 'Creá un PIN de 4 dígitos';
    }
    return 'Ingresá tu PIN';
  }

  String get _currentPin =>
      widget.isSetup && _isConfirming ? _confirmPin : _pin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),

            // Ícono
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppTheme.tempOk.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.tempOk.withOpacity(0.3)),
              ),
              child: const Icon(Icons.lock_rounded,
                  color: AppTheme.tempOk, size: 36),
            ),
            const SizedBox(height: 24),

            // Título
            Text(_titulo,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),

            Text(
              widget.isSetup
                  ? 'Este PIN protege el acceso a la app'
                  : 'Farmacia Monitor',
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 48),

            // Puntos del PIN
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                final offset = _shakeController.isAnimating
                    ? 12 * (0.5 - _shakeAnimation.value).abs() * 2
                    : 0.0;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _currentPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? AppTheme.tempOk
                          : Colors.transparent,
                      border: Border.all(
                        color: filled
                            ? AppTheme.tempOk
                            : AppTheme.textMuted,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 20),

            // Error o bloqueo
            SizedBox(
              height: 32,
              child: _bloqueado
                  ? Text(
                      'Bloqueado por $_segundosBloqueado segundos',
                      style: TextStyle(
                          color: AppTheme.tempDanger.withOpacity(0.9),
                          fontSize: 13),
                    )
                  : Text(
                      _error,
                      style: TextStyle(
                          color: AppTheme.tempDanger.withOpacity(0.9),
                          fontSize: 13),
                    ),
            ),

            const Spacer(),

            // Teclado numérico
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                children: [
                  _buildRow(['1', '2', '3']),
                  const SizedBox(height: 16),
                  _buildRow(['4', '5', '6']),
                  const SizedBox(height: 16),
                  _buildRow(['7', '8', '9']),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(width: 72),
                      _DigitButton(digit: '0', onTap: () => _onDigit('0'), bloqueado: _bloqueado),
                      _DeleteButton(onTap: _onDelete, bloqueado: _bloqueado),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((d) => _DigitButton(
        digit: d,
        onTap: () => _onDigit(d),
        bloqueado: _bloqueado,
      )).toList(),
    );
  }
}

class _DigitButton extends StatelessWidget {
  final String digit;
  final VoidCallback onTap;
  final bool bloqueado;

  const _DigitButton({required this.digit, required this.onTap, required this.bloqueado});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: bloqueado ? null : onTap,
      child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bloqueado
              ? AppTheme.bgCard.withOpacity(0.3)
              : AppTheme.bgCard,
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Center(
          child: Text(digit,
              style: TextStyle(
                color: bloqueado ? AppTheme.textMuted : AppTheme.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w300,
              )),
        ),
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool bloqueado;

  const _DeleteButton({required this.onTap, required this.bloqueado});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: bloqueado ? null : onTap,
      child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(color: Colors.transparent),
        ),
        child: Center(
          child: Icon(Icons.backspace_outlined,
              color: bloqueado ? AppTheme.textMuted : AppTheme.textSecondary,
              size: 24),
        ),
      ),
    );
  }
}
