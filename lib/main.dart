import 'package:flutter/material.dart';

import 'data/db.dart';
import 'services/app_lock.dart';
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
  // Ask once for notification permission (Android 13+).
  if (await db.getSetting('notif_asked') == null) {
    await db.setSetting('notif_asked', '1');
    await state.notifier.requestPermission();
    await state.rescheduleReminders();
  }
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

  final AppLock _lock = AppLock();
  late bool _locked;
  bool _authenticating = false;
  DateTime? _leftAt;

  /// Away longer than this and the app locks again.
  static const _relockAfter = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = state.lockEnabled;
    if (_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    _authenticating = true;
    final ok = await _lock.authenticate();
    _authenticating = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final dbx = state.dropbox;
    // The Face ID / fingerprint prompt itself makes the app inactive;
    // ignore that.
    if (!_authenticating) {
      if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
        _leftAt ??= DateTime.now();
      } else if (s == AppLifecycleState.resumed) {
        final left = _leftAt;
        _leftAt = null;
        if (state.lockEnabled &&
            !_locked &&
            left != null &&
            DateTime.now().difference(left) >= _relockAfter) {
          setState(() => _locked = true);
          _unlock();
        }
      }
    }
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
        builder: (context, child) => Stack(
          children: [
            child ?? const SizedBox(),
            if (_locked) _LockScreen(onUnlock: _unlock),
          ],
        ),
      ),
    );
  }
}

/// Covers the whole app until Face ID / fingerprint / passcode succeeds.
class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Material(
        color: scheme.surface,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 56, color: scheme.primary),
                const SizedBox(height: 16),
                Text('Money Tracker is locked',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                  onPressed: onUnlock,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
