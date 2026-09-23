import '../core/time_format.dart';

/// Inbox notification from Firestore `notifications/{id}`.
///
/// Written by Cloud Functions [writeInbox] — Flutter does not create these docs.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.recipientUserId,
    required this.actorUserId,
    required this.type,
    required this.message,
    required this.isRead,
    this.postId = '',
    this.commentId = '',
    this.actorNickname = '',
    this.postPreview = '',
    this.commentPreview = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String recipientUserId;
  final String actorUserId;

  /// `comment` | `like` | `comment_like` | `report_result`
  final String type;
  final String message;
  final bool isRead;
  final String postId;
  final String commentId;

  /// Actor display name denormalized by CF. Empty on legacy docs.
  final String actorNickname;

  /// Short post snapshot (comment / like). Empty on legacy / comment_like.
  final String postPreview;

  /// Short comment snapshot (comment_like). Empty on legacy / other types.
  final String commentPreview;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AppNotification copyWith({
    bool? isRead,
    String? actorNickname,
    String? message,
  }) {
    return AppNotification(
      id: id,
      recipientUserId: recipientUserId,
      actorUserId: actorUserId,
      type: type,
      message: message ?? this.message,
      isRead: isRead ?? this.isRead,
      postId: postId,
      commentId: commentId,
      actorNickname: actorNickname ?? this.actorNickname,
      postPreview: postPreview,
      commentPreview: commentPreview,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory AppNotification.fromFirestore(String id, Map<String, dynamic> data) {
    return AppNotification(
      id: id,
      recipientUserId: (data['recipientUserId'] as String?)?.trim() ?? '',
      actorUserId: (data['actorUserId'] as String?)?.trim() ?? '',
      type: (data['type'] as String?)?.trim() ?? '',
      message: (data['message'] as String?)?.trim() ?? '',
      isRead: data['isRead'] == true,
      postId: (data['postId'] as String?)?.trim() ?? '',
      commentId: (data['commentId'] as String?)?.trim() ?? '',
      actorNickname: (data['actorNickname'] as String?)?.trim() ?? '',
      postPreview: (data['postPreview'] as String?)?.trim() ?? '',
      commentPreview: (data['commentPreview'] as String?)?.trim() ?? '',
      createdAt: _parseDate(data['createdAt']),
      updatedAt: _parseDate(data['updatedAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {}
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// UI label for stored [type] (DB value unchanged).
String notificationTypeLabel(String type) {
  switch (type.trim().toLowerCase()) {
    case 'comment':
      return '댓글';
    case 'like':
      return '공감';
    case 'comment_like':
      return '댓글 공감';
    case 'report_result':
      return '신고 처리 결과';
    default:
      return '알림';
  }
}

String notificationFallbackMessage(String type) {
  switch (type.trim().toLowerCase()) {
    case 'comment':
      return '게시글에 댓글이 달렸어요.';
    case 'like':
      return '게시글에 공감이 눌렸어요.';
    case 'comment_like':
      return '댓글에 공감이 눌렸어요.';
    case 'report_result':
      return '신고 처리 결과가 도착했어요.';
    default:
      return '새 알림이 있어요.';
  }
}

/// Compose inbox display text from live [actorNickname] + preview.
///
/// Prefers current nickname (caller should resolve from users/). Falls back to
/// stored [AppNotification.message] when preview/type cannot be composed
/// (legacy docs / report_result).
String composeNotificationDisplayMessage(AppNotification n) {
  final type = n.type.trim().toLowerCase();
  final nick = n.actorNickname.trim().isNotEmpty
      ? n.actorNickname.trim()
      : '누군가';

  switch (type) {
    case 'comment':
      final preview = n.postPreview.trim();
      if (preview.isEmpty && n.message.trim().isNotEmpty) {
        return n.message.trim();
      }
      return preview.isEmpty
          ? '$nick님이 게시글에 댓글을 남겼습니다.'
          : '$nick님이 "$preview" 게시글에 댓글을 남겼습니다.';
    case 'like':
      final preview = n.postPreview.trim();
      if (preview.isEmpty && n.message.trim().isNotEmpty) {
        return n.message.trim();
      }
      return preview.isEmpty
          ? '$nick님이 게시글에 공감을 남겼습니다.'
          : '$nick님이 "$preview" 게시글에 공감을 남겼습니다.';
    case 'comment_like':
      final preview = n.commentPreview.trim().isNotEmpty
          ? n.commentPreview.trim()
          : n.postPreview.trim();
      if (preview.isEmpty && n.message.trim().isNotEmpty) {
        return n.message.trim();
      }
      return preview.isEmpty
          ? '$nick님이 댓글에 공감을 남겼습니다.'
          : '$nick님이 "$preview" 댓글에 공감을 남겼습니다.';
    default:
      if (n.message.trim().isNotEmpty) return n.message.trim();
      return notificationFallbackMessage(type);
  }
}

String formatNotificationTime(DateTime dateTime, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(dateTime);
  if (diff.inDays >= 30) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    return '$y.$m.$d';
  }
  final relative = formatRelativeTime(dateTime, now: current);
  if (relative == '방금') return '방금 전';
  return '$relative 전';
}
