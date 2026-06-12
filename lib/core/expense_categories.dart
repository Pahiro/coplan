import 'package:flutter/material.dart';

/// Single source of truth for expense categories — id, display label, icon.
/// Previously duplicated between the expenses list, the form, and the detail
/// screen.
class ExpenseCategory {
  final String id;
  final String label;
  final IconData icon;

  const ExpenseCategory(this.id, this.label, this.icon);

  static const all = [
    ExpenseCategory('education', 'Education', Icons.school),
    ExpenseCategory('sport',     'Sport',     Icons.sports_soccer),
    ExpenseCategory('medical',   'Medical',   Icons.local_hospital),
    ExpenseCategory('clothing',  'Clothing',  Icons.checkroom),
    ExpenseCategory('other',     'Other',     Icons.receipt_long),
  ];

  static IconData iconFor(String? id) => all
      .firstWhere((c) => c.id == id,
          orElse: () => all.last)
      .icon;
}
