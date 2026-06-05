import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/household_provider.dart';
import 'settings/account_settings_screen.dart';
import 'settings/appearance_settings_screen.dart';
import 'settings/custody_settings_screen.dart';
import 'settings/household_settings_screen.dart';
import 'settings/notifications_settings_screen.dart';
import 'settings/schedule_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household     = ref.watch(householdProvider).valueOrNull;
    final householdMode = household?.mode ?? 'custody';

    void push(Widget screen) => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => screen),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifications'),
                  subtitle: const Text('Background activity & battery optimisation'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(const NotificationsSettingsScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Appearance'),
                  subtitle: const Text('Theme and parent / child colours'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(const AppearanceSettingsScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Household'),
                  subtitle: const Text('Members, mode, and children'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(const HouseholdSettingsScreen()),
                ),
                if (householdMode == 'custody') ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: const Text('Schedule'),
                    subtitle: const Text('Rotation, handover times, and recurring rules'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => push(const ScheduleSettingsScreen()),
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.swap_horiz_outlined),
                  title: const Text('Custody'),
                  subtitle: const Text('Holiday periods and absences'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(const CustodySettingsScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('Account'),
                  subtitle: const Text('Password, export, and app info'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(const AccountSettingsScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Version footer
          Center(
            child: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) {
                final info    = snap.data;
                final version = info != null
                    ? 'v${info.version}+${info.buildNumber}'
                    : '...';
                return Text(
                  'CoPlan $version',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
