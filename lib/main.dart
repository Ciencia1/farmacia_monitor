import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'models/temp_reading.dart';
import 'services/mqtt_service.dart';
import 'services/notification_service.dart';
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

  final mqtt = MqttService();
  await mqtt.init();

  runApp(FarmaciaApp(mqtt: mqtt));
}

class FarmaciaApp extends StatelessWidget {
  final MqttService mqtt;
  const FarmaciaApp({super.key, required this.mqtt});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.farmaciaName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: MainShell(mqtt: mqtt),
    );
  }
}

class MainShell extends StatefulWidget {
  final MqttService mqtt;
  const MainShell({super.key, required this.mqtt});

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
          SettingsScreen(mqtt: widget.mqtt),
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
