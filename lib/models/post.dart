import 'comment.dart';
import 'poll.dart';
import '../core/constants.dart';

/// Anonymous cafe community post
class Post {
  final String id;
  final String author;
  final String content;
  final DateTime createdAt;
  int likeCount;
  bool likedByMe;
  Poll? poll;
  List<Comment> comments;

  /// Legacy / display tag list. Prefer [topicId] + [topicName].
  final List<String> tags;
  final List<String> relatedPostIds;

  /// Firestore `topics/{id}` reference.
  final String? topicId;

  /// Denormalized topic display name for feed/detail.
  final String? topicName;

  /// Author work experience label from onboarding (e.g. '1~3년')
  final String? experience;

  /// Author cafe type from onboarding (e.g. '개인카페', '프랜차이즈')
  final String? cafeType;

  /// Optional title from Firestore (shown when present).
  final String? title;

  /// Author profile image URL from Kakao / Firestore.
  final String? authorProfileImage;

  /// Kakao / Firestore author uid.
  final String? authorId;

  /// Comment count from server when comments are not loaded locally.
  final int? remoteCommentCount;

  Post({
    required this.id,
    required this.content,
    required this.createdAt,
    String? author,
    this.likeCount = 0,
    this.likedByMe = false,
    this.poll,
    List<Comment>? comments,
    this.tags = const [],
    this.relatedPostIds = const [],
    this.topicId,
    this.topicName,
    String? experience,
    String? cafeType,
    this.title,
    this.authorProfileImage,
    this.authorId,
    this.remoteCommentCount,
  })  : author = author ?? AppConstants.nicknameFor('post:$id'),
        comments = comments ?? [],
        experience = experience ?? AppConstants.experienceFor('post:$id'),
        cafeType = cafeType ?? AppConstants.cafeTypeFor('post:$id');

  int get commentCount => remoteCommentCount ?? comments.length;

  /// Display topic: denormalized name, else first legacy tag.
  String? get topic {
    final named = topicName?.trim();
    if (named != null && named.isNotEmpty) return named;
    if (tags.isEmpty) return null;
    return tags.first;
  }

  /// Nickname alias used by Firestore field naming.
  String get authorNickname => author;

  /// Build from a Firestore `posts` document.
  factory Post.fromFirestore(String id, Map<String, dynamic> data) {
    final createdAt = _parseDateTime(data['createdAt']) ?? DateTime.now();
    final content = (data['content'] as String?)?.trim() ??
        (data['body'] as String?)?.trim() ??
        '';
    final title = (data['title'] as String?)?.trim();
    final author = (data['nickname'] as String?)?.trim() ??
        (data['author'] as String?)?.trim() ??
        (data['authorNickname'] as String?)?.trim();
    final profileImage = (data['authorProfileImage'] as String?)?.trim() ??
        (data['profileImage'] as String?)?.trim();
    final authorId = (data['authorId'] as String?)?.trim();
    final topicId = (data['topicId'] as String?)?.trim();
    final topicName = (data['topicName'] as String?)?.trim();
    var tags = _parseStringList(data['tags'] ?? data['topics']);
    if (tags.isEmpty && topicName != null && topicName.isNotEmpty) {
      tags = [topicName];
    }
    final likeCount = _parseInt(data['likeCount'] ?? data['likes']) ?? 0;
    final commentCount = _parseInt(data['commentCount']) ?? 0;
    final experience = (data['experience'] as String?)?.trim();
    final cafeType = (data['cafeType'] as String?)?.trim();

    return Post(
      id: id,
      content: content.isEmpty && title != null ? title : content,
      title: title,
      createdAt: createdAt,
      author: author,
      authorProfileImage: profileImage,
      authorId: authorId,
      likeCount: likeCount,
      tags: tags,
      topicId: topicId,
      topicName: topicName,
      experience: experience,
      cafeType: cafeType,
      remoteCommentCount: commentCount,
    );
  }

  Post copyWith({
    String? id,
    String? author,
    String? content,
    DateTime? createdAt,
    int? likeCount,
    bool? likedByMe,
    Poll? poll,
    bool clearPoll = false,
    List<Comment>? comments,
    List<String>? tags,
    List<String>? relatedPostIds,
    String? topicId,
    String? topicName,
    bool clearTopic = false,
    String? experience,
    String? cafeType,
    String? title,
    String? authorProfileImage,
    String? authorId,
    int? remoteCommentCount,
  }) {
    return Post(
      id: id ?? this.id,
      author: author ?? this.author,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      poll: clearPoll ? null : (poll ?? this.poll),
      comments: comments ?? this.comments,
      tags: clearTopic ? const [] : (tags ?? this.tags),
      relatedPostIds: relatedPostIds ?? this.relatedPostIds,
      topicId: clearTopic ? null : (topicId ?? this.topicId),
      topicName: clearTopic ? null : (topicName ?? this.topicName),
      experience: experience ?? this.experience,
      cafeType: cafeType ?? this.cafeType,
      title: title ?? this.title,
      authorProfileImage: authorProfileImage ?? this.authorProfileImage,
      authorId: authorId ?? this.authorId,
      remoteCommentCount: remoteCommentCount ?? this.remoteCommentCount,
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

  static List<String> _parseStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }
}

/// Post list sort order
enum PostSort { all, popular, latest }
