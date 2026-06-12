import 'package:flutter/material.dart' show TimeOfDay;
import 'package:intl/intl.dart';

/// Shared date/time helpers — the single home for formats that were
/// previously re-implemented per file (`_fmt`, `_isoDate`, `_fmtTime`, …).

/// "2026-06-12" — the wire format used in PocketBase filters and fields.
String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "14:30" from a [TimeOfDay].
String fmtTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "14:30", or [fallback] when [t] is null.
String fmtTimeOr(TimeOfDay? t, [String fallback = '—']) =>
    t != null ? fmtTime(t) : fallback;

/// "Fri, 12 Jun 2026" — the long display format used by pickers/sheets.
String fmtDateLong(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);

/// True when [a] and [b] fall on the same calendar day.
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Parses "HH:mm" into a [TimeOfDay].
TimeOfDay parseHHmm(String hhmm) {
  final p = hhmm.split(':');
  return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
}
