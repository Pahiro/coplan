import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custody_request.dart';
import '../providers/custody_provider.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
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
    final cs = Theme.of(context).colorScheme;
    final requestsAsync = ref.watch(custodyRequestsProvider);

    Future<void> refresh() async {
      ref.invalidate(custodyRequestsProvider);
      await ref
          .read(custodyRequestsProvider.future)
          .catchError((_) => const <CustodyRequest>[]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Requests')),
      body: requestsAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (allRequests) {
          // Upcoming is the action list (soonest first); Past is the history
          // of what was agreed (most recent first). A swap is one entry and
          // stays upcoming until both of its days have passed.
          final today = dateOnly(DateTime.now());
          final upcoming = _view == _RequestsView.upcoming;
          final groups = groupRequests(allRequests)
              .where((g) => upcoming
                  ? !g.lastDate.isBefore(today)
                  : g.lastDate.isBefore(today))
              .toList()
            ..sort((a, b) => upcoming
                ? a.firstDate.compareTo(b.firstDate)
                : b.lastDate.compareTo(a.lastDate));

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
                child: RefreshIndicator(
                  onRefresh: refresh,
                  child: groups.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 120),
                            Center(
                              child: Text(
                                upcoming
                                    ? 'No upcoming requests.'
                                    : 'No past requests.',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: groups.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) =>
                              CustodyRequestTile(group: groups[i]),
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
