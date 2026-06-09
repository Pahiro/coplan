import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../models/payment_details.dart';
import 'auth_provider.dart';
import 'household_provider.dart';

/// Provides the current user's payment details for the active household.
final myPaymentDetailsProvider =
    AsyncNotifierProvider<MyPaymentDetailsNotifier, PaymentDetails?>(
  MyPaymentDetailsNotifier.new,
);

class MyPaymentDetailsNotifier extends AsyncNotifier<PaymentDetails?> {
  @override
  Future<PaymentDetails?> build() async {
    final auth = ref.watch(authProvider).valueOrNull;
    final household = ref.watch(householdProvider).valueOrNull;
    if (auth == null || !auth.isLoggedIn || household == null) return null;

    final myId = auth.userId ?? '';
    if (myId.isEmpty) return null;

    try {
      final records = await pb.collection('payment_details').getFullList(
        filter: 'user = "$myId" && household = "${household.id}"',
      );
      if (records.isEmpty) return null;
      return PaymentDetails.fromRecord(records.first.toJson());
    } catch (_) {
      return null;
    }
  }

  /// Save (create or update) payment details.
  Future<void> save({
    String? bankName,
    String? accountHolder,
    String? accountNumber,
    String? branchCode,
    String? paymentLink,
    String? paymentReference,
    String? notes,
  }) async {
    final auth = ref.read(authProvider).valueOrNull;
    final household = ref.read(householdProvider).valueOrNull;
    if (auth == null || household == null) return;

    final myId = auth.userId ?? '';
    final body = {
      'household':        household.id,
      'user':             myId,
      'bank_name':        bankName ?? '',
      'account_holder':   accountHolder ?? '',
      'account_number':   accountNumber ?? '',
      'branch_code':      branchCode ?? '',
      'payment_link':     paymentLink ?? '',
      'payment_reference': paymentReference ?? '',
      'notes':            notes ?? '',
    };

    final current = state.valueOrNull;
    if (current != null) {
      await pb.collection('payment_details').update(current.id, body: body);
    } else {
      await pb.collection('payment_details').create(body: body);
    }
    ref.invalidateSelf();
  }
}

/// Fetch payment details for a specific user in the current household.
final userPaymentDetailsProvider =
    FutureProvider.family<PaymentDetails?, String>((ref, userId) async {
  final household = ref.watch(householdProvider).valueOrNull;
  if (household == null || userId.isEmpty) return null;

  try {
    final records = await pb.collection('payment_details').getFullList(
      filter: 'user = "$userId" && household = "${household.id}"',
    );
    if (records.isEmpty) return null;
    return PaymentDetails.fromRecord(records.first.toJson());
  } catch (_) {
    return null;
  }
});
