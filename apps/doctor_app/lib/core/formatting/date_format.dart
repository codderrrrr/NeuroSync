/// Date formatting for the portal, without pulling in a localisation package.
///
/// The roster, the request list and the review queue all show dates, and they
/// show them the same way, so the month names live here once instead of in four
/// private copies. The output strings are unchanged from those copies.
///
/// The values are rendered exactly as the API sent them. Converting to local
/// time would shift every displayed date for a portal running outside UTC,
/// which is a behaviour change, not a formatting one, so it is deliberately not
/// done here.
library;

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Jan 3, 2026` — the roster and request lists.
String formatMonthDayYear(DateTime value) =>
    '${_months[value.month - 1]} ${value.day}, ${value.year}';

/// `Jan 3` — the dashboard, where the year is already obvious from context.
String formatMonthDay(DateTime value) =>
    '${_months[value.month - 1]} ${value.day}';

/// The review queue's date: a clock time when the entry is from today,
/// otherwise a short date.
///
/// The queue is read while working, so "today" without a time is the least
/// useful thing a row could show.
String formatQueueDate(DateTime value) {
  final DateTime now = DateTime.now();
  final bool sameDay = value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;
  if (sameDay) {
    return 'Today ${_clockTime(value)}';
  }
  return formatMonthDayYear(value);
}

String _clockTime(DateTime value) {
  final String hour = value.hour.toString().padLeft(2, '0');
  final String minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
