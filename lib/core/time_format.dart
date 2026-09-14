/// 상대 시간 표시 (SNS 피드용)
String formatRelativeTime(DateTime dateTime, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(dateTime);

  if (diff.inSeconds < 60) return '방금';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분';
  if (diff.inHours < 24) return '${diff.inHours}시간';
  if (diff.inDays < 7) return '${diff.inDays}일';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}주';
  return '${dateTime.month}/${dateTime.day}';
}
