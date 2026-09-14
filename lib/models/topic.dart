/// Community topic stored in Firestore `topics/{id}`,
/// also used as a lightweight local aggregate in [PostService].
class Topic {
  Topic({
    this.id = '',
    required this.name,
    int usageCount = 0,
    int? postCount,
    this.createdAt,
    this.updatedAt,
  }) : usageCount = postCount ?? usageCount;

  final String id;
  final String name;
  final int usageCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Alias for local aggregates / older UI.
  int get postCount => usageCount;

  factory Topic.fromFirestore(String id, Map<String, dynamic> data) {
    return Topic(
      id: id,
      name: (data['name'] as String?)?.trim() ?? id,
      usageCount: _asInt(data['usageCount']) ?? 0,
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _asDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {}
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Trim ends and collapse internal whitespace (same topic identity).
String normalizeTopicName(String raw) {
  return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Firestore-safe unique key for a topic name.
String topicNameKey(String raw) {
  return normalizeTopicName(raw).toLowerCase();
}
