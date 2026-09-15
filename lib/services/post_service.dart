import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../data/mock_posts.dart';
import '../models/comment.dart';
import '../models/poll.dart';
import '../models/post.dart';
import '../models/topic.dart';
import 'auth_service.dart';

/// Post / like / poll / comment / topic in-memory logic.
/// Currently mock only. Swap internals later; keep this API.
class PostService extends ChangeNotifier {
  PostService._() : _posts = createMockPosts();

  static final PostService instance = PostService._();

  final List<Post> _posts;
  final Set<String> _myPostIds = {};

  List<Post> get posts => List.unmodifiable(_posts);

  /// True if the signed-in Kakao user authored the post, or it was written
  /// in this session (`_myPostIds`).
  bool isMyPost(String postId, {Post? post}) {
    if (_myPostIds.contains(postId)) return true;
    final uid = AuthService.instance.kakaoUserId?.trim();
    if (uid == null || uid.isEmpty) return false;
    final resolved = post ?? getById(postId);
    final authorId = resolved?.authorId?.trim();
    return authorId != null && authorId.isNotEmpty && authorId == uid;
  }

  void markAsMyPost(String postId) {
    if (postId.isEmpty) return;
    _myPostIds.add(postId);
  }

  /// Posts authored by the current session user (tracked via write).
  List<Post> myPosts() {
    return _posts
        .where((p) => _myPostIds.contains(p.id))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<Post> postsSorted(PostSort sort) {
    final list = List<Post>.from(_posts);
    switch (sort) {
      case PostSort.all:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case PostSort.popular:
        list.sort((a, b) {
          // Testing: keep my posts visible near the top of popular.
          final aMine = _myPostIds.contains(a.id);
          final bMine = _myPostIds.contains(b.id);
          if (aMine != bMine) return aMine ? -1 : 1;

          final byLikes = b.likeCount.compareTo(a.likeCount);
          if (byLikes != 0) return byLikes;
          final byComments = b.commentCount.compareTo(a.commentCount);
          if (byComments != 0) return byComments;
          return b.createdAt.compareTo(a.createdAt);
        });
      case PostSort.latest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  Post? getById(String id) {
    try {
      return _posts.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Merge a remote (Firestore) post into the local cache for detail/actions.
  void upsertRemotePost(Post post) {
    final index = _posts.indexWhere((p) => p.id == post.id);
    if (index >= 0) {
      final local = _posts[index];
      _posts[index] = post.copyWith(
        comments: local.comments.isNotEmpty ? local.comments : post.comments,
        poll: post.poll ?? local.poll,
        authorProfileImage:
            post.authorProfileImage ?? local.authorProfileImage,
        authorId: post.authorId ?? local.authorId,
        title: post.title ?? local.title,
        topicId: post.topicId ?? local.topicId,
        topicName: post.topicName ?? local.topicName,
        tags: post.tags.isNotEmpty ? post.tags : local.tags,
      );
    } else {
      _posts.add(post);
    }
    notifyListeners();
  }

  List<Post> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return _posts.where((p) {
      final inContent = p.content.toLowerCase().contains(q);
      final inTags = p.tags.any((t) => t.toLowerCase().contains(q));
      final inPoll = p.poll?.question.toLowerCase().contains(q) ?? false;
      return inContent || inTags || inPoll;
    }).toList()
      ..sort((a, b) => b.likeCount.compareTo(a.likeCount));
  }

  List<Post> relatedPosts(Post post, {int limit = 8}) {
    final topic = post.topic?.trim();
    if (topic != null && topic.isNotEmpty) {
      final scored = <({Post post, int score})>[];
      for (final other in _posts) {
        if (other.id == post.id) continue;
        final otherTopic = other.topic?.trim();
        if (otherTopic == null || otherTopic.isEmpty) continue;

        final score = _topicSimilarityScore(topic, otherTopic);
        if (score <= 0) continue;
        scored.add((post: other, score: score));
      }

      scored.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final byLikes = b.post.likeCount.compareTo(a.post.likeCount);
        if (byLikes != 0) return byLikes;
        return b.post.createdAt.compareTo(a.post.createdAt);
      });

      if (scored.isNotEmpty) {
        return scored.take(limit).map((e) => e.post).toList();
      }
    }

    // Fallback: explicit related ids, then any overlapping tags.
    final byId = <Post>[];
    for (final id in post.relatedPostIds) {
      final p = getById(id);
      if (p != null && p.id != post.id) byId.add(p);
    }
    if (byId.isNotEmpty) return byId.take(limit).toList();

    return _posts
        .where(
          (p) =>
              p.id != post.id && p.tags.any((t) => post.tags.contains(t)),
        )
        .take(limit)
        .toList();
  }

  /// Exact match > containment (급여 ↔ 급여 문제) > shared token.
  int _topicSimilarityScore(String a, String b) {
    final left = _normalizeTopic(a);
    final right = _normalizeTopic(b);
    if (left.isEmpty || right.isEmpty) return 0;
    if (left == right) return 100;
    if (left.contains(right) || right.contains(left)) return 80;

    final leftTokens = _topicTokens(a);
    final rightTokens = _topicTokens(b);
    for (final token in leftTokens) {
      if (token.length < 2) continue;
      if (rightTokens.contains(token)) return 60;
      if (right.contains(token)) return 50;
    }
    for (final token in rightTokens) {
      if (token.length < 2) continue;
      if (left.contains(token)) return 50;
    }
    return 0;
  }

  String _normalizeTopic(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  Set<String> _topicTokens(String value) {
    return value
        .toLowerCase()
        .split(RegExp(r'[\s/·,\-_]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  /// Topics used across posts, sorted by usage count.
  List<Topic> popularTopics({int limit = 30}) {
    final topics = _topicCounts().entries
        .map((e) => Topic(name: e.key, postCount: e.value))
        .toList()
      ..sort((a, b) {
        final byCount = b.postCount.compareTo(a.postCount);
        if (byCount != 0) return byCount;
        return a.name.compareTo(b.name);
      });
    if (limit <= 0 || topics.length <= limit) return topics;
    return topics.take(limit).toList();
  }

  /// Search existing topics by substring. Does not force selection.
  List<Topic> searchTopics(String query, {int limit = 20}) {
    final q = query.trim().toLowerCase();
    final all = popularTopics(limit: 1000);
    if (q.isEmpty) return all.take(limit).toList();
    return all
        .where((t) => t.name.toLowerCase().contains(q))
        .take(limit)
        .toList();
  }

  List<Post> postsByTopic(String topicName, {PostSort sort = PostSort.latest}) {
    final name = topicName.trim();
    if (name.isEmpty) return const [];
    final list = _posts
        .where((p) => p.tags.any((t) => t == name))
        .toList();
    switch (sort) {
      case PostSort.all:
      case PostSort.latest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case PostSort.popular:
        list.sort((a, b) {
          // Testing: keep my posts visible near the top of popular.
          final aMine = _myPostIds.contains(a.id);
          final bMine = _myPostIds.contains(b.id);
          if (aMine != bMine) return aMine ? -1 : 1;

          final byLikes = b.likeCount.compareTo(a.likeCount);
          if (byLikes != 0) return byLikes;
          final byComments = b.commentCount.compareTo(a.commentCount);
          if (byComments != 0) return byComments;
          return b.createdAt.compareTo(a.createdAt);
        });
    }
    return list;
  }

  int postCountForTopic(String topicName) {
    final name = topicName.trim();
    if (name.isEmpty) return 0;
    return _posts.where((p) => p.tags.any((t) => t == name)).length;
  }

  void toggleLike(String postId) {
    final post = getById(postId);
    if (post == null) return;
    if (post.likedByMe) {
      post.likedByMe = false;
      post.likeCount = (post.likeCount - 1).clamp(0, 1 << 30);
    } else {
      post.likedByMe = true;
      post.likeCount += 1;
    }
    notifyListeners();
  }

  void toggleCommentLike(String postId, String commentId) {
    final post = getById(postId);
    if (post == null) return;
    final index = post.comments.indexWhere((c) => c.id == commentId);
    if (index < 0) return;
    final c = post.comments[index];
    if (c.likedByMe) {
      post.comments[index] = c.copyWith(
        likedByMe: false,
        likeCount: (c.likeCount - 1).clamp(0, 1 << 30),
      );
    } else {
      post.comments[index] = c.copyWith(
        likedByMe: true,
        likeCount: c.likeCount + 1,
      );
    }
    notifyListeners();
  }

  void vote(String postId, String optionId) {
    final post = getById(postId);
    final poll = post?.poll;
    if (post == null || poll == null) return;

    PollOption? previous;
    for (final option in poll.options) {
      if (option.selectedByMe) {
        previous = option;
        break;
      }
    }

    // Same option again — ignore
    if (previous?.id == optionId) return;

    if (previous != null) {
      previous.votes = (previous.votes - 1).clamp(0, 1 << 30);
      previous.selectedByMe = false;
    }

    for (final option in poll.options) {
      if (option.id == optionId) {
        option.votes += 1;
        option.selectedByMe = true;
        break;
      }
    }
    poll.hasVoted = true;
    notifyListeners();
  }

  void addComment(
    String postId,
    String content, {
    String? author,
    String? experience,
    String? cafeType,
  }) {
    final text = content.trim();
    if (text.isEmpty) return;
    final post = getById(postId);
    if (post == null) return;

    post.comments.add(
      Comment(
        id: 'c-${DateTime.now().millisecondsSinceEpoch}',
        postId: postId,
        content: text,
        createdAt: DateTime.now(),
        author: author ?? AppConstants.randomNickname(),
        experience: experience,
        cafeType: cafeType,
      ),
    );
    notifyListeners();
  }

  Post addPost({
    required String content,
    Poll? poll,
    List<String>? tags,
    String? author,
    String? experience,
    String? cafeType,
  }) {
    final cleanedTags = _normalizeTags(tags);
    final post = Post(
      id: 'p-${DateTime.now().millisecondsSinceEpoch}',
      content: content.trim(),
      createdAt: DateTime.now(),
      poll: poll,
      tags: cleanedTags,
      author: author ?? AppConstants.randomNickname(),
      experience: experience,
      cafeType: cafeType,
    );
    _posts.insert(0, post);
    _myPostIds.add(post.id);
    notifyListeners();
    return post;
  }

  /// Owner-only full post update (content / topic / poll).
  bool updatePost({
    required String postId,
    required String content,
    List<String>? tags,
    Poll? poll,
    bool clearPoll = false,
  }) {
    if (!isMyPost(postId)) return false;
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index < 0) return false;

    final cleaned = content.trim();
    if (cleaned.isEmpty) return false;

    final post = _posts[index];
    _posts[index] = post.copyWith(
      content: cleaned,
      tags: _normalizeTags(tags),
      poll: poll,
      clearPoll: clearPoll,
    );
    notifyListeners();
    return true;
  }

  /// Owner-only topic update. Returns false if not allowed / missing.
  bool updatePostTopic(String postId, String? topicName) {
    if (!isMyPost(postId)) return false;
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index < 0) return false;
    final post = _posts[index];
    final tags = _normalizeTags(
      topicName == null || topicName.trim().isEmpty
          ? const []
          : [topicName],
    );
    _posts[index] = post.copyWith(tags: tags);
    notifyListeners();
    return true;
  }

  /// Remove from local cache (ownership is checked by the caller / Firestore).
  bool deletePost(String postId) {
    final before = _posts.length;
    _posts.removeWhere((p) => p.id == postId);
    _myPostIds.remove(postId);
    if (_posts.length == before) return false;
    notifyListeners();
    return true;
  }

  void reportContent({
    required String targetType,
    required String targetId,
    required String reason,
  }) {
    debugPrint('report(mock): $targetType/$targetId -> $reason');
  }

  Map<String, int> _topicCounts() {
    final counts = <String, int>{};
    for (final post in _posts) {
      for (final tag in post.tags) {
        final name = tag.trim();
        if (name.isEmpty) continue;
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }
    return counts;
  }

  List<String> _normalizeTags(List<String>? tags) {
    if (tags == null || tags.isEmpty) return const [];
    final cleaned = <String>[];
    for (final tag in tags) {
      final name = tag.trim();
      if (name.isEmpty) continue;
      if (!cleaned.contains(name)) cleaned.add(name);
    }
    return cleaned;
  }
}
