import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/custody_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/realtime_provider.dart';
import 'providers/refresh.dart';
import 'providers/schedule_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/calendar_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/household_setup_screen.dart';
import 'screens/login_screen.dart';
import 'screens/requests_screen.dart';
import 'screens/settings_screen.dart';
import 'services/notification_service.dart';
import 'services/widget_cache_service.dart';
import 'utils/dates.dart';
import 'widgets/motion.dart';

class CoplanApp extends ConsumerWidget {
  const CoplanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth      = ref.watch(authProvider);
    final themeMode = ref.watch(themeProvider).valueOrNull ?? ThemeMode.system;

    const seed = Color(0xFF1565C0);

    // Shared-axis push/pop on every route. Applied per platform so web/desktop
    // match Android.
    final transitions = PageTransitionsTheme(builders: {
      for (final platform in TargetPlatform.values)
        platform: const SharedAxisPageTransitionsBuilder(
          transitionType: SharedAxisTransitionType.horizontal,
        ),
    });

    return MaterialApp(
      scaffoldMessengerKey: NotificationService.messengerKey,
      title: 'CoPlan',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        pageTransitionsTheme: transitions,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        pageTransitionsTheme: transitions,
      ),
      home: auth.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => const LoginScreen(),
        data: (state) {
          if (!state.isLoggedIn) return const LoginScreen();
          if (state.needsHousehold) return const HouseholdSetupScreen();
          return const _MainShell();
        },
      ),
    );
  }
}

/// Root scaffold with bottom navigation and the shared app bar. Also owns the
/// app-wide freshness: realtime subscriptions, the offline queue, catching up
/// after the app resumes, and rolling "today" over at midnight.
class _MainShell extends ConsumerStatefulWidget {
  const _MainShell();

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell>
    with WidgetsBindingObserver {
  static const _titles = ['Today', 'Calendar', 'Expenses'];

  Timer? _clock;
  DateTime _lastRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => _syncToday());
    WidgetCacheService.updateSoon();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _syncToday();
    // Catch up on anything the realtime connection missed in the background.
    // Throttled: pickers, the share sheet and the installer also resume us.
    if (DateTime.now().difference(_lastRefresh) > const Duration(seconds: 30)) {
      _lastRefresh = DateTime.now();
      refreshAppData(ref.invalidate);
    }
    WidgetCacheService.updateSoon();
  }

  void _syncToday() {
    final today = dateOnly(DateTime.now());
    final notifier = ref.read(todayProvider.notifier);
    if (notifier.state != today) notifier.state = today;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(realtimeNotificationsProvider);
    ref.watch(connectivityWatcherProvider);

    final tab          = ref.watch(shellTabProvider);
    final queuedCount  = ref.watch(pendingOpsCountProvider);
    final pendingCount = ref.watch(pendingCustodyCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[tab]),
        actions: [
          if (queuedCount > 0)
            Tooltip(
              message:
                  '$queuedCount change${queuedCount == 1 ? '' : 's'} waiting to sync',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Chip(
                  avatar: const Icon(Icons.cloud_off, size: 14),
                  label: Text('$queuedCount',
                      style: const TextStyle(fontSize: 12)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          IconButton(
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: 'Requests',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RequestsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: FadeThroughIndexedStack(
        index: tab,
        children: const [
          DashboardScreen(),
          CalendarScreen(),
          ExpensesScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) =>
            ref.read(shellTabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Expenses',
          ),
        ],
      ),
    );
  }
}
