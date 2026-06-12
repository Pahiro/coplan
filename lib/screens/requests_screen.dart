import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/custody_provider.dart';
import '../widgets/custody_request_tile.dart';

enum _RequestsView { upcoming, past }

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  _RequestsView _view = _RequestsView.upcoming;

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(custodyRequestsProvider);
    final myId = ref.watch(authProvider).valueOrNull?.userId ?? '';

    Future<void> refresh() async => ref.invalidate(custodyRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Requests')),
      body: requestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Error loading requests')),
        data: (allRequests) {
          // Upcoming is the action list (soonest first); Past is the history
          // of what was agreed (most recent first). Standing recurring
          // arrangements never appear here — future occurrences are expanded
          // virtually and past ones are frozen with a past date.
          final now   = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final upcoming = _view == _RequestsView.upcoming;
          final requests = allRequests
              .where((r) => upcoming
                  ? !r.date.isBefore(today)
                  : r.date.isBefore(today))
              .toList()
            ..sort((a, b) => upcoming
                ? a.date.compareTo(b.date)
                : b.date.compareTo(a.date));

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SegmentedButton<_RequestsView>(
                  segments: const [
                    ButtonSegment(
                      value: _RequestsView.upcoming,
                      icon: Icon(Icons.upcoming_outlined, size: 16),
                      label: Text('Upcoming'),
                    ),
                    ButtonSegment(
                      value: _RequestsView.past,
                      icon: Icon(Icons.history, size: 16),
                      label: Text('Past'),
                    ),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                  style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ),
              Expanded(
                child: requests.isEmpty
                    ? RefreshIndicator(
                        onRefresh: refresh,
                        child: ListView(
                          children: [
                            const SizedBox(height: 120),
                            Center(
                                child: Text(
                                    upcoming
                                        ? 'No upcoming requests.'
                                        : 'No past requests.',
                                    style:
                                        const TextStyle(color: Colors.grey))),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: refresh,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: requests.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => CustodyRequestTile(
                              request: requests[i], myId: myId),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
