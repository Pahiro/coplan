import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected bottom-navigation tab (0 Today, 1 Calendar, 2 Expenses), so a
/// screen — e.g. the Today summary card — can switch tabs.
final shellTabProvider = StateProvider<int>((ref) => 0);

enum ExpensesView { toBuy, expenses }

/// Which half of the Expenses tab is showing.
final expensesViewProvider =
    StateProvider<ExpensesView>((ref) => ExpensesView.expenses);
