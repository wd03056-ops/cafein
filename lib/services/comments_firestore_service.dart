import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../models/comment.dart';
import 'auth_service.dart';
import 'nickname_lookup_cache.dart';
import 'user_firestore_service.dart';

/// Firestore comments under `posts/{postId}/comments`.
class CommentsFirestoreService {
  CommentsFirestoreService._();
  static final CommentsFirestoreService instance = CommentsFirestoreService._();

  /// In-memory TTL for comment lists (same window as feed cache).
  static const Duration memoryCacheTtl = Duration(minutes: 5);

  final _firestore = FirebaseFirestore.instance;

  /// commentId → likedByMe for current uid (legacy like-doc fallback).
  final Map<String, bool> _likeCache = {};
  String? _likeCacheUid;

  /// authorId → cafeType/experience (avoid re-get on every comment snapshot).
  final Map<String, ({String cafeType, String experience})> _profileCache = {};

  /// postId → comment list memory.
  final Map<String, _CommentsCacheEntry> _commentsMemory = {};

  CollectionReference<Map<String, dynamic>> _commentsRef(String postId) {
    return _firestore.collection('posts').doc(postId).collection('comments');
  }

  CollectionReference<Map<String, dynamic>> _commentLikesRef(
    String postId,
    String commentId,
  ) {
    return _commentsRef(postId).doc(commentId).collection('likes');
  }

  void _ensureLikeCacheUid(String? uid) {
    if (uid == null || uid.isEmpty) {
      _likeCache.clear();
      _likeCacheUid = null;
      return;
    }
    if (_likeCacheUid != uid) {
      _likeCache.clear();
      _likeCacheUid = uid;
    }
  }

  bool? _likedByMeFromMap(Map<String, dynamic> data, String uid) {
    if (!data.containsKey('likedBy')) return null;
    final likedBy = data['likedBy'];
    if (likedBy is! Map) return false;
    return likedBy[uid] == true;
  }

  void rememberComments(String postId, List<Comment> comments) {
    final id = postId.trim();
    if (id.isEmpty) return;
    _commentsMemory[id] = _CommentsCacheEntry(
      sortedNewestFirst(comments),
      DateTime.now(),
    );
  }

  /// Newest [Comment.createdAt] first. Safe for equal/missing-ish timestamps.
  static List<Comment> sortedNewestFirst(Iterable<Comment> comments) {
    final list = List<Comment>.from(comments);
    list.sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      if (byTime != 0) return byTime;
      return b.id.compareTo(a.id);
    });
    return list;
  }

  List<Comment>? peekCachedComments(
    String postId, {
    bool allowStale = false,
  }) {
    final id = postId.trim();
    if (id.isEmpty) return null;
    final entry = _commentsMemory[id];
    if (entry == null) return null;
    if (!allowStale && entry.isExpired(memoryCacheTtl)) return null;
    return List<Comment>.from(entry.comments);
  }

  void invalidateComments(String postId) {
    _commentsMemory.remove(postId.trim());
  }

  /// Soft-remap denormalized author nicknames after a profile rename.
  void remapAuthorNickname(String authorId, String nickname) {
    final uid = authorId.trim();
    final nick = nickname.trim();
    if (uid.isEmpty || nick.isEmpty) return;
    for (final entry in _commentsMemory.entries.toList()) {
      final updated = [
        for (final c in entry.value.comments)
          c.authorId?.trim() == uid && !c.authorWithdrawn
              ? c.copyWith(author: nick)
              : c,
      ];
      _commentsMemory[entry.key] = _CommentsCacheEntry(
        updated,
        entry.value.fetchedAt,
      );
    }
  }

  /// After withdrawal CF: remap cached comments from Kakao uid → deleted id.
  void applyAuthorWithdrawalInCache({
    required String oldAuthorId,
    required String deletedAuthorId,
    required String displayNickname,
  }) {
    final oldId = oldAuthorId.trim();
    final deletedId = deletedAuthorId.trim();
    final nick = displayNickname.trim();
    if (oldId.isEmpty || deletedId.isEmpty || nick.isEmpty) return;

    for (final entry in _commentsMemory.entries.toList()) {
      final updated = [
        for (final c in entry.value.comments)
          c.authorId?.trim() == oldId
              ? c.copyWith(
                  authorId: deletedId,
                  author: nick,
                  authorWithdrawn: true,
                  clearAuthorProfileImage: true,
                )
              : c,
      ];
      _commentsMemory[entry.key] = _CommentsCacheEntry(
        updated,
        entry.value.fetchedAt,
      );
    }
  }

  void appendCachedComment(String postId, Comment comment) {
    final id = postId.trim();
    final current = peekCachedComments(id, allowStale: true) ?? const [];
    if (current.any((c) => c.id == comment.id)) {
      rememberComments(id, [
        for (final c in current) c.id == comment.id ? comment : c,
      ]);
      return;
    }
    // Newest-first: insert then sort by createdAt DESC.
    rememberComments(id, [comment, ...current]);
  }

  void removeCachedComment(String postId, String commentId) {
    final id = postId.trim();
    final current = peekCachedComments(id, allowStale: true);
    if (current == null) return;
    rememberComments(
      id,
      current.where((c) => c.id != commentId).toList(),
    );
  }

  void patchCachedComment(String postId, Comment comment) {
    appendCachedComment(postId, comment);
  }

  /// One-shot comment list. Cache-first within [memoryCacheTtl].
  ///
  /// [forceRefresh] true → Firestore server get; memory is updated from
  /// server. Soft-update race guards apply only when not forcing, so
  /// pull-to-refresh cannot be blocked by a stale local list.
  Future<List<Comment>> fetchComments(
    String postId, {
    bool forceRefresh = false,
  }) async {
    final id = postId.trim();
    if (id.isEmpty) return const [];

    if (!forceRefresh) {
      final cached = peekCachedComments(id);
      if (cached != null) {
        debugPrint('comments memory hit ($id, ${cached.length})');
        debugPrint('[REFRESH_DEBUG] CACHE USED');
        return cached;
      }
    } else {
      debugPrint('[REFRESH_DEBUG] refresh start');
      debugPrint('[REFRESH_DEBUG] forceRefresh=true comments postId=$id');
    }

    final fetchStartedAt = DateTime.now();
    debugPrint('[REFRESH_DEBUG] Firestore fetch start');
    final snap = await _commentsRef(id)
        .orderBy('createdAt', descending: true)
        .get(
          forceRefresh
              ? const GetOptions(source: Source.server)
              : const GetOptions(),
        );

    if (!forceRefresh) {
      final localDuringFetch = _commentsMemory[id];
      if (localDuringFetch != null &&
          localDuringFetch.fetchedAt.isAfter(fetchStartedAt)) {
        debugPrint('comments keep local soft update ($id)');
        return List<Comment>.from(localDuringFetch.comments);
      }
    }

    final comments = await _mapDocsToComments(id, snap.docs);

    if (!forceRefresh) {
      final localAfterMap = _commentsMemory[id];
      if (localAfterMap != null &&
          localAfterMap.fetchedAt.isAfter(fetchStartedAt)) {
        debugPrint('comments keep local soft update after map ($id)');
        return List<Comment>.from(localAfterMap.comments);
      }
    }

    rememberComments(id, comments);
    if (forceRefresh) {
      debugPrint('[REFRESH_DEBUG] comments count=${comments.length}');
      debugPrint('[REFRESH_DEBUG] cache updated');
      debugPrint('[REFRESH_DEBUG] Firestore fetch success');
      debugPrint('[REFRESH_DEBUG] refresh complete');
    }
    return comments;
  }

  /// Compatibility: one-shot stream (no live `snapshots()` listener).
  Stream<List<Comment>> watchComments(String postId) {
    return Stream.fromFuture(fetchComments(postId));
  }

  Future<List<Comment>> _mapDocsToComments(
    String postId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final uid = AuthService.instance.kakaoUserId?.trim();
    _ensureLikeCacheUid(uid);
    final comments = <Comment>[];

    final pendingLike = <int, Future<bool>>{};
    final pendingProfile =
        <int, Future<({String cafeType, String experience})?>>{};

    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      final data = doc.data();
      var comment = Comment.fromFirestore(
        id: doc.id,
        postId: postId,
        data: data,
      );

      final needsProfile = (comment.cafeType == null ||
              comment.cafeType!.isEmpty) ||
          (comment.experience == null || comment.experience!.isEmpty);
      final authorId = comment.authorId?.trim() ?? '';
      if (needsProfile && authorId.isNotEmpty) {
        final cached = _profileCache[authorId];
        if (cached != null) {
          comment = comment.copyWith(
            cafeType: (comment.cafeType == null || comment.cafeType!.isEmpty)
                ? cached.cafeType
                : comment.cafeType,
            experience:
                (comment.experience == null || comment.experience!.isEmpty)
                    ? cached.experience
                    : comment.experience,
          );
        } else {
          pendingProfile[i] = _loadAuthorProfile(authorId);
        }
      }

      if (uid != null && uid.isNotEmpty) {
        final fromMap = _likedByMeFromMap(data, uid);
        if (fromMap != null) {
          comment = comment.copyWith(likedByMe: fromMap);
          _likeCache[comment.id] = fromMap;
        } else if (_likeCache.containsKey(comment.id)) {
          comment = comment.copyWith(likedByMe: _likeCache[comment.id]!);
        } else {
          pendingLike[i] = _commentLikesRef(postId, comment.id)
              .doc(uid)
              .get()
              .then((s) => s.exists);
        }
      }

      comments.add(comment);
    }

    if (pendingProfile.isNotEmpty || pendingLike.isNotEmpty) {
      await Future.wait([
        ...pendingProfile.values,
        ...pendingLike.values,
      ]);
      for (final e in pendingProfile.entries) {
        final profile = await e.value;
        if (profile == null) continue;
        final c = comments[e.key];
        comments[e.key] = c.copyWith(
          cafeType: (c.cafeType == null || c.cafeType!.isEmpty)
              ? profile.cafeType
              : c.cafeType,
          experience: (c.experience == null || c.experience!.isEmpty)
              ? profile.experience
              : c.experience,
        );
      }
      for (final e in pendingLike.entries) {
        final liked = await e.value;
        final c = comments[e.key];
        _likeCache[c.id] = liked;
        comments[e.key] = c.copyWith(likedByMe: liked);
      }
    }

    return applyLiveAuthorNicknames(comments);
  }

  /// Replace denormalized author with current `users/{authorId}.nickname`.
  /// Skips withdrawn authors — always keep [AppConstants.withdrawnAuthorNickname].
  Future<List<Comment>> applyLiveAuthorNicknames(List<Comment> comments) async {
    if (comments.isEmpty) return comments;
    final resolved = [
      for (final c in comments)
        c.authorWithdrawn
            ? (c.author == AppConstants.withdrawnAuthorNickname
                ? c
                : c.copyWith(author: AppConstants.withdrawnAuthorNickname))
            : c,
    ];
    final lookupIds = resolved
        .where((c) => !c.authorWithdrawn)
        .map((c) => c.authorId ?? '');
    final map = await NicknameLookupCache.instance.resolveMany(lookupIds);
    if (map.isEmpty) return resolved;
    final out = <Comment>[];
    for (final c in resolved) {
      if (c.authorWithdrawn) {
        out.add(c);
        continue;
      }
      final live = map[c.authorId?.trim() ?? ''];
      if (live != null && live.isNotEmpty && live != c.author) {
        out.add(c.copyWith(author: live));
      } else {
        out.add(c);
      }
    }
    return out;
  }

  Future<({String cafeType, String experience})?> _loadAuthorProfile(
    String authorId,
  ) async {
    try {
      final userSnap = await _firestore.collection('users').doc(authorId).get();
      final data = userSnap.data();
      if (data == null) return null;
      final nick = (data['nickname'] as String?)?.trim() ??
          (data['kakaoNickname'] as String?)?.trim() ??
          '';
      if (nick.isNotEmpty) {
        NicknameLookupCache.instance.put(authorId, nick);
      }
      final profile = (
        cafeType: (data['cafeType'] as String?)?.trim() ?? '',
        experience: (data['experience'] as String?)?.trim() ?? '',
      );
      _profileCache[authorId] = profile;
      return profile;
    } catch (e) {
      debugPrint('댓글 작성자 프로필 보강 실패: $e');
      return null;
    }
  }

  /// Creates a comment and returns the local [Comment] for soft UI update.
  Future<Comment> addComment({
    required String postId,
    required String content,
    required String authorId,
    required String authorNickname,
    String authorProfileImage = '',
    String? experience,
    String? cafeType,
  }) async {
    AuthService.instance.requireKakaoWriter();

    final text = content.trim();
    if (text.isEmpty) {
      throw ArgumentError('댓글 내용이 비어 있어요.');
    }
    if (authorId.trim().isEmpty) {
      throw ArgumentError('로그인이 필요해요.');
    }

    final nickname =
        authorNickname.trim().isEmpty ? '익명' : authorNickname.trim();

    String profileImage = authorProfileImage.trim();
    var exp = experience?.trim() ?? '';
    var cafe = cafeType?.trim() ?? '';

    try {
      final userDoc = await UserDocCache.instance.get(authorId);
      final data = userDoc?.data();
      if (data != null) {
        if (profileImage.isEmpty) {
          profileImage =
              (data['profileImage'] as String?)?.trim() ?? '';
        }
        if (exp.isEmpty) {
          exp = (data['experience'] as String?)?.trim() ?? '';
        }
        if (cafe.isEmpty) {
          cafe = (data['cafeType'] as String?)?.trim() ?? '';
        }
      }
    } catch (e) {
      debugPrint('댓글 작성자 프로필 조회 실패: $e');
    }

    // Prefer in-memory Auth profile when Firestore user doc is incomplete.
    final auth = AuthService.instance;
    if (exp.isEmpty) exp = auth.experience?.trim() ?? '';
    if (cafe.isEmpty) cafe = auth.cafeType?.trim() ?? '';

    final payload = <String, dynamic>{
      'content': text,
      'authorId': authorId,
      'authorNickname': nickname,
      'authorProfileImage': profileImage,
      'experience': exp,
      'cafeType': cafe,
      'likeCount': 0,
      'likedBy': <String, dynamic>{},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestore.batch();
    final commentRef = _commentsRef(postId).doc();
    batch.set(commentRef, payload);
    batch.update(_firestore.collection('posts').doc(postId), {
      'commentCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        await commentRef.set(payload);
      } else {
        rethrow;
      }
    }

    final created = Comment(
      id: commentRef.id,
      postId: postId,
      content: text,
      createdAt: DateTime.now(),
      author: nickname,
      authorId: authorId,
      authorProfileImage: profileImage,
      experience: exp,
      cafeType: cafe,
      likeCount: 0,
      likedByMe: false,
    );
    appendCachedComment(postId, created);
    return created;
  }

  /// Toggle comment like. Doc id = Kakao user id under
  /// `posts/{postId}/comments/{commentId}/likes/{uid}`.
  Future<Comment> toggleCommentLike({
    required String postId,
    required String commentId,
    String? userId,
  }) async {
    AuthService.instance.requireKakaoWriter();
    final uid = (userId ?? AuthService.instance.kakaoUserId)?.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('카카오 로그인 후 이용해 주세요.');
    }

    late Comment result;
    await _firestore.runTransaction((tx) async {
      final commentRef = _commentsRef(postId).doc(commentId);
      final likeRef = _commentLikesRef(postId, commentId).doc(uid);
      final commentSnap = await tx.get(commentRef);
      final likeSnap = await tx.get(likeRef);

      if (!commentSnap.exists || commentSnap.data() == null) {
        throw StateError('댓글을 찾을 수 없어요.');
      }

      final data = commentSnap.data()!;
      final current = (data['likeCount'] as num?)?.toInt() ?? 0;
      var comment = Comment.fromFirestore(
        id: commentId,
        postId: postId,
        data: data,
      );

      if (likeSnap.exists) {
        final nextCount = (current - 1).clamp(0, 1 << 30);
        tx.delete(likeRef);
        tx.update(commentRef, {
          'likeCount': nextCount,
          'likedBy.$uid': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        result = comment.copyWith(likedByMe: false, likeCount: nextCount);
      } else {
        final nextCount = current + 1;
        tx.set(likeRef, {
          'userId': uid,
          'postId': postId,
          'commentId': commentId,
          'kakaoUserId': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(commentRef, {
          'likeCount': FieldValue.increment(1),
          'likedBy.$uid': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        result = comment.copyWith(likedByMe: true, likeCount: nextCount);
      }
    });

    _ensureLikeCacheUid(uid);
    _likeCache[commentId] = result.likedByMe;
    patchCachedComment(postId, result);
    return result;
  }

  /// Owner-only content update.
  Future<Comment> updateComment({
    required String postId,
    required String commentId,
    required String content,
  }) async {
    AuthService.instance.requireKakaoWriter();
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('로그인이 필요해요.');
    }
    final text = content.trim();
    if (text.isEmpty) {
      throw StateError('댓글 내용을 입력해주세요.');
    }

    final commentRef = _commentsRef(postId).doc(commentId);
    final snap = await commentRef.get();
    if (!snap.exists || snap.data() == null) {
      throw StateError('댓글을 찾을 수 없어요.');
    }
    final data = snap.data()!;
    final authorId = (data['authorId'] as String?)?.trim() ?? '';
    if (authorId != uid) {
      throw StateError('본인 댓글만 수정할 수 있어요.');
    }

    await commentRef.update({
      'content': text,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final updated = Comment.fromFirestore(
      id: commentId,
      postId: postId,
      data: {
        ...data,
        'content': text,
      },
    );
    Comment result = updated;
    final cached = peekCachedComments(postId, allowStale: true);
    if (cached != null) {
      for (final c in cached) {
        if (c.id == commentId) {
          result = updated.copyWith(
            likeCount: c.likeCount,
            likedByMe: c.likedByMe,
          );
          break;
        }
      }
    }
    patchCachedComment(postId, result);
    return result;
  }

  /// Owner-only delete by default. Decrements post `commentCount` (never below 0).
  ///
  /// Set [bypassOwnerCheck] for admin moderation (same cleanup path).
  Future<void> deleteComment({
    required String postId,
    required String commentId,
    bool bypassOwnerCheck = false,
  }) async {
    AuthService.instance.requireKakaoWriter();
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('로그인이 필요해요.');
    }

    final commentRef = _commentsRef(postId).doc(commentId);
    final postRef = _firestore.collection('posts').doc(postId);

    // Best-effort: remove like docs before deleting the comment.
    try {
      final likes =
          await _commentLikesRef(postId, commentId).limit(200).get();
      if (likes.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final d in likes.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('댓글 공감 정리 실패(무시): $e');
    }

    await _firestore.runTransaction((tx) async {
      final commentSnap = await tx.get(commentRef);
      if (!commentSnap.exists || commentSnap.data() == null) {
        throw StateError('댓글을 찾을 수 없어요.');
      }
      final authorId =
          (commentSnap.data()?['authorId'] as String?)?.trim() ?? '';
      if (!bypassOwnerCheck && authorId != uid) {
        throw StateError('본인 댓글만 삭제할 수 있어요.');
      }

      final postSnap = await tx.get(postRef);
      final current =
          (postSnap.data()?['commentCount'] as num?)?.toInt() ?? 0;

      tx.delete(commentRef);
      if (postSnap.exists) {
        tx.update(postRef, {
          'commentCount': (current - 1).clamp(0, 1 << 30),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    removeCachedComment(postId, commentId);
  }
}

class _CommentsCacheEntry {
  _CommentsCacheEntry(this.comments, this.fetchedAt);

  final List<Comment> comments;
  final DateTime fetchedAt;

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(fetchedAt) > ttl;
}
