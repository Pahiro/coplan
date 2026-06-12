import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/colors_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/color_setting_row.dart';


class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode  = ref.watch(themeProvider).valueOrNull ?? ThemeMode.system;
    final colors     = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final myUserId   = ref.watch(authProvider).valueOrNull?.userId ?? '';
    final household  = ref.watch(householdProvider).valueOrNull;
    final children   = ref.watch(householdChildNamesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          // Theme
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Theme',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined),
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (s) =>
                        ref.read(themeProvider.notifier).setMode(s.first),
                  ),
                ],
              ),
            ),
          ),

          // Parent / helper colours
          ...(household?.parents ?? const []).map((m) => ColorSettingRow(
            label: m.displayName,
            description: "Shown on ${m.displayName}'s events and calendar blocks",
            current: colors.parentColor(m.displayName),
            isEditable: myUserId == m.userId,
            onChanged: (c) =>
                ref.read(colorsProvider.notifier).updateMyColor(c),
          )),
          if ((household?.helpers ?? const []).isNotEmpty)
            ...household!.helpers.map((m) => ColorSettingRow(
              label: m.displayName,
              description: 'Shown when ${m.displayName} is covering a pickup',
              current: colors.parentColor(m.displayName),
              isEditable: myUserId == m.userId,
              onChanged: (c) =>
                  ref.read(colorsProvider.notifier).updateMyColor(c),
            )),

          // Child colours
          if (children.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text(
                'Children',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ...children.map((child) => ColorSettingRow(
              label: child.name,
              description: 'Shown on ${child.name}-specific events',
              current: colors.childColor(child.name),
              isEditable: true,
              onChanged: (c) => ref
                  .read(colorsProvider.notifier)
                  .updateChildColor(child.id, c),
            )),
          ],
        ],
      ),
    );
  }
}
