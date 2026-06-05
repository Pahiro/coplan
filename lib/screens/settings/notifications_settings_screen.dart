import 'package:flutter/material.dart';

import '../../services/notification_service.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> with WidgetsBindingObserver {
  bool? _isOptimized;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final v = await NotificationService.isBatteryOptimized();
    if (mounted) setState(() => _isOptimized = v);
  }

  @override
  Widget build(BuildContext context) {
    final isOk = _isOptimized == false;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isOk ? Icons.notifications_active : Icons.notifications_off,
                        color: isOk ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isOk
                            ? 'Background notifications on'
                            : 'Background notifications may be blocked',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isOk ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isOk
                        ? 'CoPlan is exempt from battery optimisation and will '
                          'receive notifications even when not in use.'
                        : 'Android may pause CoPlan in the background, preventing '
                          'notifications from arriving when the app is not open. '
                          'Tap below to allow it to run unrestricted.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  if (!isOk) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await NotificationService.requestBatteryExemption();
                        },
                        icon: const Icon(Icons.battery_saver_outlined, size: 18),
                        label: const Text('Allow background activity'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
