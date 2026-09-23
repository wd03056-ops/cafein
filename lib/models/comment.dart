import '../core/constants.dart';

/// Single-level comment (no replies)
class Comment {
  final String id;
  final String postId;
  final String author;
  final String content;
  final DateTime createdAt;
  int likeCount;
  bool likedByMe;
  final String? experience;
  final String? cafeType;
  final String? authorId;
  final String? authorProfileImage;

  /// True when the author withdrew; never resolve live `users/{authorId}`.
  final bool authorWithdrawn;

  Comment({
    required this.id,
    required this.postId,
    required this.content,
    required this.createdAt,
    String? author,
    this.likeCount = 0,
    this.likedByMe = false,
    this.experience,
    this.cafeType,
    this.authorId,
    this.authorProfileImage,
    this.authorWithdrawn = false,
  }) : author = authorWithdrawn
            ? AppConstants.withdrawnAuthorNickname
            : (author ?? AppConstants.nicknameFor('comment:$id'));

  String get authorNickname => author;

  factory Comment.fromFirestore({
    required String id,
    required String postId,
    required Map<String, dynamic> data,
  }) {
    final createdAt = _parseDateTime(data['createdAt']) ?? DateTime.now();
    final authorWithdrawn = data['authorWithdrawn'] == true;
    final nickname = authorWithdrawn
        ? AppConstants.withdrawnAuthorNickname
        : ((data['authorNickname'] as String?)?.trim() ??
            (data['nickname'] as String?)?.trim() ??
            (data['author'] as String?)?.trim());
    final experienceRaw = (data['experience'] as String?)?.trim();
    final cafeTypeRaw = (data['cafeType'] as String?)?.trim();
    return Comment(
      id: id,
      postId: postId,
      content: (data['content'] as String?)?.trim() ?? '',
      createdAt: createdAt,
      author: nickname,
      authorId: (data['authorId'] as String?)?.trim(),
      authorProfileImage: authorWithdrawn
          ? null
          : ((data['authorProfileImage'] as String?)?.trim() ??
              (data['profileImage'] as String?)?.trim()),
      authorWithdrawn: authorWithdrawn,
      // Empty string must stay empty (no mock fallback) so UI can hide badge.
      experience: (experienceRaw == null || experienceRaw.isEmpty)
          ? ''
          : experienceRaw,
      cafeType:
          (cafeTypeRaw == null || cafeTypeRaw.isEmpty) ? '' : cafeTypeRaw,
      likeCount: _parseInt(data['likeCount']) ?? 0,
    );
  }

  Comment copyWith({
    String? id,
    String? postId,
    String? author,
    String? content,
    DateTime? createdAt,
    int? likeCount,
    bool? likedByMe,
    String? experience,
    String? cafeType,
    String? authorId,
    String? authorProfileImage,
    bool clearAuthorProfileImage = false,
    bool? authorWithdrawn,
  }) {
    return Comment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      author: author ?? this.author,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      experience: experience ?? this.experience,
      cafeType: cafeType ?? this.cafeType,
      authorId: authorId ?? this.authorId,
      authorProfileImage: clearAuthorProfileImage
          ? null
          : (authorProfileImage ?? this.authorProfileImage),
      authorWithdrawn: authorWithdrawn ?? this.authorWithdrawn,
    );
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

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
