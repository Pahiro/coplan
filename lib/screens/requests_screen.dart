import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/custody_provider.dart';
import '../widgets/custody_request_tile.dart';

class RequestsScreen extends ConsumerWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(custodyRequestsProvider);
    final myId = ref.watch(authProvider).valueOrNull?.userId ?? '';

    Future<void> refresh() async => ref.invalidate(custodyRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Requests')),
      body: requestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Error loading requests')),
        data: (requests) {
          if (requests.isEmpty) {
            return const Center(
                child: Text('No requests yet.',
                    style: TextStyle(color: Colors.grey)));
          }
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) =>
                  CustodyRequestTile(request: requests[i], myId: myId),
            ),
          );
        },
      ),
    );
  }
}
