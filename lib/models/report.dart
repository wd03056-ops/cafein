/// Firestore `reports/{id}` moderation status.
///
/// Stored as lowercase snake strings matching these enum names.
enum ReportStatus {
  pending,
  reviewing,
  resolved,
  dismissed;

  static const String firestorePending = 'pending';
  static const String firestoreReviewing = 'reviewing';
  static const String firestoreResolved = 'resolved';
  static const String firestoreDismissed = 'dismissed';

  String get firestoreValue {
    switch (this) {
      case ReportStatus.pending:
        return firestorePending;
      case ReportStatus.reviewing:
        return firestoreReviewing;
      case ReportStatus.resolved:
        return firestoreResolved;
      case ReportStatus.dismissed:
        return firestoreDismissed;
    }
  }

  /// Legacy docs without [status] are treated as [pending].
  static ReportStatus fromFirestore(dynamic raw) {
    final value = (raw as String?)?.trim().toLowerCase() ?? '';
    switch (value) {
      case firestoreReviewing:
        return ReportStatus.reviewing;
      case firestoreResolved:
        return ReportStatus.resolved;
      case firestoreDismissed:
        return ReportStatus.dismissed;
      case firestorePending:
      default:
        return ReportStatus.pending;
    }
  }
}

/// Moderation action taken on a report.
enum ReportAction {
  none,
  contentDeleted,
  userWarned,
  userSuspended;

  static const String firestoreNone = 'none';
  static const String firestoreContentDeleted = 'content_deleted';
  static const String firestoreUserWarned = 'user_warned';
  static const String firestoreUserSuspended = 'user_suspended';

  String get firestoreValue {
    switch (this) {
      case ReportAction.none:
        return firestoreNone;
      case ReportAction.contentDeleted:
        return firestoreContentDeleted;
      case ReportAction.userWarned:
        return firestoreUserWarned;
      case ReportAction.userSuspended:
        return firestoreUserSuspended;
    }
  }

  /// Legacy docs without [action] are treated as [none].
  static ReportAction fromFirestore(dynamic raw) {
    final value = (raw as String?)?.trim().toLowerCase() ?? '';
    switch (value) {
      case firestoreContentDeleted:
        return ReportAction.contentDeleted;
      case firestoreUserWarned:
        return ReportAction.userWarned;
      case firestoreUserSuspended:
        return ReportAction.userSuspended;
      case firestoreNone:
      default:
        return ReportAction.none;
    }
  }
}

/// Full `reports/{id}` document used for moderation / Console review.
///
/// Existing create fields (unchanged):
/// - reporterId, targetType, targetId, targetAuthorId, reason, createdAt, updatedAt
/// - parentPostId (comments)
///
/// Content preservation (written at report create):
/// - targetSnapshot, parentPostSnapshot (optional maps)
///
/// Moderation fields (written by Cloud Functions Admin SDK only):
/// - status, action, reviewedBy, reviewedAt, adminNote,
///   reporterNotified, reportedUserNotified
class Report {
  const Report({
    required this.id,
    required this.reporterId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    this.targetAuthorId = '',
    this.parentPostId,
    this.targetSnapshot,
    this.parentPostSnapshot,
    this.status = ReportStatus.pending,
    this.action = ReportAction.none,
    this.reviewedBy,
    this.reviewedAt,
    this.adminNote,
    this.reporterNotified = false,
    this.reportedUserNotified = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String reporterId;
  final String targetType;
  final String targetId;
  final String targetAuthorId;

  /// For `targetType == comment`: parent `posts/{id}` (needed to delete).
  final String? parentPostId;

  /// Snapshot of the reported post/comment/user at report time.
  final ReportContentSnapshot? targetSnapshot;

  /// For comment reports: parent post snapshot at report time.
  final ReportContentSnapshot? parentPostSnapshot;

  final String reason;
  final ReportStatus status;
  final ReportAction action;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? adminNote;
  final bool reporterNotified;
  final bool reportedUserNotified;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Report.fromFirestore(String id, Map<String, dynamic> data) {
    return Report(
      id: id,
      reporterId: (data['reporterId'] as String?)?.trim() ?? '',
      targetType: (data['targetType'] as String?)?.trim() ?? '',
      targetId: (data['targetId'] as String?)?.trim() ?? '',
      targetAuthorId: (data['targetAuthorId'] as String?)?.trim() ?? '',
      parentPostId: _nullableTrim(data['parentPostId']),
      targetSnapshot: ReportContentSnapshot.tryParse(data['targetSnapshot']),
      parentPostSnapshot:
          ReportContentSnapshot.tryParse(data['parentPostSnapshot']),
      reason: (data['reason'] as String?)?.trim() ?? '',
      status: ReportStatus.fromFirestore(data['status']),
      action: ReportAction.fromFirestore(data['action']),
      reviewedBy: _nullableTrim(data['reviewedBy']),
      reviewedAt: _parseDateTime(data['reviewedAt']),
      adminNote: _nullableTrim(data['adminNote']),
      reporterNotified: data['reporterNotified'] == true,
      reportedUserNotified: data['reportedUserNotified'] == true,
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }

  static String? _nullableTrim(dynamic value) {
    final s = (value as String?)?.trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {}
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Denormalized content captured when a report is filed.
///
/// Stored under `reports/{id}.targetSnapshot` / `parentPostSnapshot`.
class ReportContentSnapshot {
  const ReportContentSnapshot({
    this.content = '',
    this.topicName = '',
    this.authorDisplayName = '',
    this.createdAt,
    this.pollQuestion = '',
    this.pollOptions = const [],
  });

  final String content;
  final String topicName;
  final String authorDisplayName;
  final DateTime? createdAt;
  final String pollQuestion;
  final List<String> pollOptions;

  bool get hasDisplayableContent {
    if (content.trim().isNotEmpty) return true;
    if (pollQuestion.trim().isNotEmpty) return true;
    if (pollOptions.any((o) => o.trim().isNotEmpty)) return true;
    if (authorDisplayName.trim().isNotEmpty) return true;
    return false;
  }

  static ReportContentSnapshot? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final optionsRaw = map['pollOptions'];
    final options = <String>[];
    if (optionsRaw is List) {
      for (final item in optionsRaw) {
        final s = item?.toString().trim() ?? '';
        if (s.isNotEmpty) options.add(s);
      }
    }
    final snap = ReportContentSnapshot(
      content: (map['content'] as String?)?.trim() ?? '',
      topicName: (map['topicName'] as String?)?.trim() ?? '',
      authorDisplayName: (map['authorDisplayName'] as String?)?.trim() ?? '',
      createdAt: Report._parseDateTime(map['createdAt']),
      pollQuestion: (map['pollQuestion'] as String?)?.trim() ?? '',
      pollOptions: options,
    );
    return snap.hasDisplayableContent ? snap : snap;
  }

  /// Firestore-friendly map (createdAt as DateTime — caller may convert).
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'content': content,
      'authorDisplayName': authorDisplayName,
    };
    if (topicName.isNotEmpty) map['topicName'] = topicName;
    if (createdAt != null) map['createdAt'] = createdAt;
    if (pollQuestion.isNotEmpty) map['pollQuestion'] = pollQuestion;
    if (pollOptions.isNotEmpty) map['pollOptions'] = pollOptions;
    return map;
  }
}

