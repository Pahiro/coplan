import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/custody_provider.dart';
import 'providers/realtime_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/calendar_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/household_setup_screen.dart';
import 'screens/login_screen.dart';
import 'screens/requests_screen.dart';
import 'screens/settings_screen.dart';
import 'services/notification_service.dart';

class CoplanApp extends ConsumerWidget {
  const CoplanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth      = ref.watch(authProvider);
    final themeMode = ref.watch(themeProvider).valueOrNull ?? ThemeMode.system;

    const seed = Color(0xFF1565C0);

    return MaterialApp(
      scaffoldMessengerKey: NotificationService.messengerKey,
      title: 'CoPlan',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
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

/// Root scaffold with bottom navigation (Today | Calendar) and shared AppBar actions.
class _MainShell extends ConsumerStatefulWidget {
  const _MainShell();

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  int _tabIndex = 0;

  static const _titles = ['Today', 'Calendar', 'Expenses'];

  @override
  Widget build(BuildContext context) {
    // Activate real-time PocketBase subscription for notifications
    ref.watch(realtimeNotificationsProvider);
    // Keep connectivity watcher alive for the session
    ref.watch(connectivityWatcherProvider);

    final queuedCount  = ref.watch(pendingOpsCountProvider);
    final pendingCount = ref.watch(pendingCustodyCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tabIndex]),
        actions: [
          // Notification bell with badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Requests',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RequestsScreen()),
                ),
              ),
              if (pendingCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: Text('$pendingCount',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10)),
                  ),
                ),
            ],
          ),
          if (queuedCount > 0)
            Tooltip(
              message:
                  '$queuedCount action${queuedCount == 1 ? '' : 's'} queued — will sync when online',
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
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: const [
          DashboardScreen(),
          CalendarScreen(),
          ExpensesScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
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
