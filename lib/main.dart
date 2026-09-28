import 'package:flutter/material.dart';

import 'data/db.dart';
import 'state/app_state.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDb.open();
  final state = AppState(db);
  await state.load();
  runApp(MoneyApp(state: state));
  // Update exchange rates in the background.
  state.autoRefreshRates();
  // Opening the app uploads the latest copy to Dropbox.
  state.dropbox.syncNow();
}

class MoneyApp extends StatefulWidget {
  const MoneyApp({super.key, required this.state});

  final AppState state;

  @override
  State<MoneyApp> createState() => _MoneyAppState();
}

class _MoneyAppState extends State<MoneyApp> with WidgetsBindingObserver {
  AppState get state => widget.state;
  DateTime _lastResume = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final dbx = state.dropbox;
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      // Leaving the app: send any change that is still waiting.
      dbx.flush();
    } else if (s == AppLifecycleState.resumed) {
      // Coming back to the app counts as opening it (at most every 5 min).
      if (DateTime.now().difference(_lastResume).inMinutes >= 5 || dbx.pending) {
        dbx.syncNow();
      }
      _lastResume = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Money Tracker',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF00796B),
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF00796B),
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
