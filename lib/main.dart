import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'data/db.dart';
import 'util/format.dart';
import 'services/app_lock.dart';
import 'state/app_state.dart';
import 'ui/home.dart';
import 'ui/setup_screen.dart';
import 'ui/sms_inbox_screen.dart';
import 'ui/due_screen.dart';
import 'ui/transaction_edit.dart';
import 'data/models.dart';
import 'services/home_widgets.dart';
import 'l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en');
  await initializeDateFormatting('ar');
  // Western digits (0-9) in Arabic dates too.
  DateFormat.useNativeDigitsByDefaultFor('ar', false);
  final db = await AppDb.open();
  final state = AppState(db);
  await state.load();
  runApp(MoneyApp(state: state));
  // Update exchange rates in the background.
  state.autoRefreshRates();
  // Opening the app uploads the latest copy to Dropbox.
  state.dropbox.syncNow();
  // Ask once for notification permission (Android 13+).
  // (New installs are asked on the welcome screens instead.)
  if (!state.needsSetup && await db.getSetting('notif_asked') == null) {
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
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(tr('Updated with the newer data from Dropbox'))));
    }
    if (d.conflict != null && !_askingConflict && !_locked) _askConflict();
  }

  Future<void> _askConflict() async {
    final d = state.dropbox;
    final c = d.conflict;
    final ctx = _navKey.currentContext;
    if (c == null || ctx == null) return;
    _askingConflict = true;
    String remote = tr('Dropbox copy');
    try {
      final info = await AppDb.inspect(c.path);
      remote = '${info.transactions} transactions'
          '${info.last == null ? '' : tr(', latest ${shortDateFmt.format(info.last!)}')}'
          '${c.modified == null ? '' : tr('\nUploaded ${dayFmt.format(c.modified!)} ${TimeOfDay.fromDateTime(c.modified!).format(ctx)}')}';
    } catch (_) {}
    final (n, last) = await state.db.stats();
    final local = tr('$n transactions'
        '${last == null ? '' : tr(', latest ${shortDateFmt.format(last)}')}');
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: _navKey.currentContext!,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.sync_problem),
        title: Text(tr('Both Phones Have Changes')),
        content: Text(
          tr('Data changed on this phone and on your other phone since they '
          'last synced. Choose which copy to keep. The other one is saved '
          'in the Dropbox history folder, so nothing is lost.\n\n'
          'This phone:\n$local\n\nDropbox (other phone):\n$remote'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'local'),
              child: Text(tr('Keep This Phone'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'remote'),
              child: Text(tr('Use Dropbox Copy'))),
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
    // Bank messages: Android reads new SMS; iPhone Shortcuts send them in
    // as ewtracker://sms?from=…&text=…
    state.readAndroidSms();
    state.readIncomingSmsFile();
    HomeWidgets.update(state);
    _linkSub = AppLinks().uriLinkStream.listen(_onLink, onError: (_) {});
  }

  StreamSubscription<Uri>? _linkSub;

  /// Widgets open the app with ewtracker://add?type=expense,
  /// ewtracker://open?to=accounts|transactions|due.
  Future<void> _onWidgetLink(Uri uri) async {
    NavigatorState? nav;
    for (var i = 0; i < 20 && (nav = _navKey.currentState) == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (nav == null || state.needsSetup) return;
    nav.popUntil((r) => r.isFirst);
    if (uri.host == 'add') {
      final type = uri.queryParameters['type'] == 'income'
          ? TxType.income
          : TxType.expense;
      nav.push(MaterialPageRoute(
          builder: (_) => TransactionEditScreen(initialType: type)));
    } else if (uri.host == 'open') {
      switch (uri.queryParameters['to']) {
        case 'transactions':
          homeTab.value = HomeTabs.transactions;
        case 'due':
          homeTab.value = HomeTabs.transactions;
          if (state.dueOccurrences.isNotEmpty) {
            nav.push(MaterialPageRoute(builder: (_) => const DueScreen()));
          }
        default:
          homeTab.value = HomeTabs.accounts;
      }
    }
  }

  Future<void> _onLink(Uri uri) async {
    if (uri.scheme != 'ewtracker') return;
    if (uri.host == 'add' || uri.host == 'open') return _onWidgetLink(uri);
    final text = uri.queryParameters['text'] ?? uri.queryParameters['body'] ?? '';
    if (text.trim().isEmpty) return;
    final from = uri.queryParameters['from'] ?? '';
    final added = await state.addSms(from, text);
    final nav = _navKey.currentState;
    final ctx = _navKey.currentContext;
    if (nav == null || ctx == null) return;
    if (!added) {
      ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
          content: Text(tr('Not a new bank transaction (already added, or a code / declined message)'))));
      return;
    }
    nav.push(MaterialPageRoute(builder: (_) => const SmsInboxScreen()));
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
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    state.onSystemLocaleChanged();
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
      state.refreshForToday();
      state.readAndroidSms();
      state.readIncomingSmsFile();
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
      child: ValueListenableBuilder<String>(
        valueListenable: state.languageNotifier,
        builder: (context, lang, _) => MaterialApp(
        title: 'Expense & Wealth Tracker',
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
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
        // A new key rebuilds every screen in the new language.
        home: _Root(key: ValueKey(lang)),
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
                Text(tr('Expense & Wealth Tracker is locked'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.fingerprint),
                  label: Text(tr('Unlock')),
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

/// The welcome screens on a new install, the app afterwards.
class _Root extends StatelessWidget {
  const _Root({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScope.of(context).needsSetup
        ? const SetupScreen()
        : const HomeScreen();
  }
}
