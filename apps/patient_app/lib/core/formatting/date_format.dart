/// Formats a timestamp for display without pulling in a localisation package.
String formatShortDate(DateTime value) {
  const List<String> months = <String>[
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
  final DateTime local = value.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

/// Date plus clock time, for lists where several entries can share a date.
String formatShortDateTime(DateTime value) {
  final DateTime local = value.toLocal();
  final String minute = local.minute.toString().padLeft(2, '0');
  return '${formatShortDate(value)} · ${local.hour}:$minute';
}
