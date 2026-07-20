import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'models/temp_reading.dart';
import 'services/auth_service.dart';
import 'services/mqtt_service.dart';
import 'services/notification_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  final notif = NotificationService();
  await notif.init();
  await notif.requestPermissions();

  runApp(const FarmaciaApp());
}

/// Widget raíz: decide si mostrar Login o la app según haya sesión guardada.
class FarmaciaApp extends StatefulWidget {
  const FarmaciaApp({super.key});

  @override
  State<FarmaciaApp> createState() => _FarmaciaAppState();
}

class _FarmaciaAppState extends State<FarmaciaApp> {
  final _authService = AuthService();

  bool _checkingSession = true;
  MqttService? _mqtt;

  @override
  void initState() {
    super.initState();
    _restaurarSesion();
  }

  Future<void> _restaurarSesion() async {
    final session = await _authService.sesionGuardada();
    if (session != null) {
      await _iniciarSesionEnApp(session);
    } else {
      setState(() => _checkingSession = false);
    }
  }

  Future<void> _iniciarSesionEnApp(FarmaciaSession session) async {
    AppConfig.configurarSesion(
      id: session.id,
      nombre: session.nombre,
      mUser: session.mqttUser,
      mPassword: session.mqttPassword,
      tMin: session.tempMin,
      tMax: session.tempMax,
    );

    final mqtt = MqttService();
    await mqtt.init(heladerasSesion: session.heladeras);

    setState(() {
      _mqtt = mqtt;
      _checkingSession = false;
    });
  }

  Future<void> _logout() async {
    await _authService.logout();
    AppConfig.limpiarSesion();
    setState(() {
      _mqtt?.dispose();
      _mqtt = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (_checkingSession) {
      home = const Scaffold(
        backgroundColor: AppTheme.bgDark,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.tempOk),
        ),
      );
    } else if (_mqtt == null) {
      home = LoginScreen(
        onLoginSuccess: (session) => _iniciarSesionEnApp(session),
      );
    } else {
      home = MainShell(mqtt: _mqtt!, onLogout: _logout);
    }

    return MaterialApp(
      title: 'Farmacia Monitor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: home,
    );
  }
}

class MainShell extends StatefulWidget {
  final MqttService mqtt;
  final VoidCallback onLogout;
  const MainShell({super.key, required this.mqtt, required this.onLogout});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _tab = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.mqtt.status != ConnectionStatus.connected) {
        widget.mqtt.connect();
      }
    }
  }

  void _onTabTapped(int index) {
    setState(() => _tab = index);
    _pageController.animateToPage(index,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  static const _navItems = [
    BottomNavigationBarItem(
        icon: Icon(Icons.thermostat_rounded), label: 'Temperatura'),
    BottomNavigationBarItem(
        icon: Icon(Icons.show_chart_rounded), label: 'Historial'),
    BottomNavigationBarItem(
        icon: Icon(Icons.settings_outlined), label: 'Ajustes'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppConfig.farmaciaName,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const Text('Monitoreo de temperatura',
                style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: AnimatedBuilder(
              animation: widget.mqtt,
              builder: (context, _) => ConnectionBadge(
                label: widget.mqtt.connectionLabel,
                connected: widget.mqtt.status == ConnectionStatus.connected,
              ),
            ),
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _tab = i),
        children: [
          HomeScreen(mqtt: widget.mqtt),
          HistoryScreen(mqtt: widget.mqtt),
          SettingsScreen(mqtt: widget.mqtt, onLogout: widget.onLogout),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _tab,
          onTap: _onTabTapped,
          items: _navItems,
        ),
      ),
    );
  }
}
