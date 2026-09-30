import 'package:flutter/material.dart';

import 'data/db.dart';
import 'util/format.dart';
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

  final _navKey = GlobalKey<NavigatorState>();
  bool _askingConflict = false;
  DateTime? _shownUpdate;

  /// Reacts to sync events: asks when both phones changed, and says when
  /// newer data came from the other phone.
  void _onDropbox() {
    final d = state.dropbox;
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    if (d.updatedFromDropbox != null && d.updatedFromDropbox != _shownUpdate) {
      _shownUpdate = d.updatedFromDropbox;
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Updated with the newer data from Dropbox')));
    }
    if (d.conflict != null && !_askingConflict && !_locked) _askConflict();
  }

  Future<void> _askConflict() async {
    final d = state.dropbox;
    final c = d.conflict;
    final ctx = _navKey.currentContext;
    if (c == null || ctx == null) return;
    _askingConflict = true;
    String remote = 'Dropbox copy';
    try {
      final info = await AppDb.inspect(c.path);
      remote = '${info.transactions} transactions'
          '${info.last == null ? '' : ', latest ${shortDateFmt.format(info.last!)}'}'
          '${c.modified == null ? '' : '\nUploaded ${dayFmt.format(c.modified!)} ${TimeOfDay.fromDateTime(c.modified!).format(ctx)}'}';
    } catch (_) {}
    final (n, last) = await state.db.stats();
    final local = '$n transactions'
        '${last == null ? '' : ', latest ${shortDateFmt.format(last)}'}';
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: _navKey.currentContext!,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.sync_problem),
        title: const Text('Both Phones Have Changes'),
        content: Text(
          'Data changed on this phone and on your other phone since they '
          'last synced. Choose which copy to keep. The other one is saved '
          'in the Dropbox history folder, so nothing is lost.\n\n'
          'This phone:\n$local\n\nDropbox (other phone):\n$remote',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'local'),
              child: const Text('Keep This Phone')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'remote'),
              child: const Text('Use Dropbox Copy')),
        ],
      ),
    );
    if (choice == 'local') {
      await d.keepThisPhone();
    } else if (choice == 'remote') {
      await d.useDropboxCopy();
    }
    _askingConflict = false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state.dropbox.addListener(_onDropbox);
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
    if (ok && mounted) {
      setState(() => _locked = false);
      if (state.dropbox.conflict != null) _onDropbox();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.dropbox.removeListener(_onDropbox);
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
      // Coming back to the app: pick up changes from the other phone
      // (at most once a minute) or send waiting ones.
      if (DateTime.now().difference(_lastResume).inSeconds >= 60 || dbx.pending) {
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
        navigatorKey: _navKey,
        home: const HomeScreen(),
        builder: (context, child) => Stack(
          children: [
            // Keep every screen above Android's navigation buttons /
            // gesture bar (the strip below uses the screen colour).
            ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: child ?? const SizedBox(),
              ),
            ),
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
