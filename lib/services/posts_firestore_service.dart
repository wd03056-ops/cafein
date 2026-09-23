import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../models/poll.dart';
import '../models/post.dart';
import '../models/topic.dart';
import 'auth_service.dart';
import 'firebase_auth_bridge.dart';
import 'nickname_lookup_cache.dart';
import 'post_service.dart';
import 'topics_firestore_service.dart';

/// Firestore-backed feed for the `posts` collection.
class PostsFirestoreService {
  PostsFirestoreService._();
  static final PostsFirestoreService instance = PostsFirestoreService._();

  /// Caps home / refresh queries so billing does not scale with total posts.
  static const int feedPageSize = 30;

  /// Max newest posts scanned for client-side keyword search.
  static const int searchScanLimit = 120;

  /// In-memory TTL for detail / author-list / similar caches.
  static const Duration memoryCacheTtl = Duration(minutes: 5);

  final _firestore = FirebaseFirestore.instance;
  final _topics = TopicsFirestoreService.instance;

  /// Memory cache: postId → likedByMe for the signed-in user (legacy fallback).
  final Map<String, bool> _likeCache = {};
  String? _likeCacheUid;

  /// postId → last known post (detail / revisit without re-get).
  final Map<String, _MemoryCacheEntry<Post>> _postMemory = {};

  /// authorId → author posts list.
  final Map<String, _MemoryCacheEntry<List<Post>>> _authorListMemory = {};

  /// topicId → topic posts list.
  final Map<String, _MemoryCacheEntry<List<Post>>> _topicListMemory = {};

  /// Home feed (latest page).
  _MemoryCacheEntry<List<Post>>? _feedMemory;

  /// "$topicId|$excludeId|$limit" → similar posts.
  final Map<String, _MemoryCacheEntry<List<Post>>> _similarMemory = {};

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('posts');

  CollectionReference<Map<String, dynamic>> _votesRef(String postId) =>
      _posts.doc(postId).collection('poll_votes');

  CollectionReference<Map<String, dynamic>> _likesRef(String postId) =>
      _posts.doc(postId).collection('likes');

  CollectionReference<Map<String, dynamic>> _commentsRef(String postId) =>
      _posts.doc(postId).collection('comments');

  // ── Local memory cache (detail / author lists) ─────────────────────────

  /// Store or refresh a post in the detail memory cache (no network).
  void rememberPost(Post post) {
    final id = post.id.trim();
    if (id.isEmpty) return;
    _postMemory[id] = _MemoryCacheEntry(post, DateTime.now());
  }

  void rememberPosts(Iterable<Post> posts) {
    for (final p in posts) {
      rememberPost(p);
    }
  }

  /// Soft-update one post in detail + feed memory (no network).
  /// Used by optimistic like UI so home/list rebuild without a re-get.
  void applyLocalPostUpdate(Post post) {
    rememberPost(post);
    final feed = _feedMemory?.value;
    if (feed == null) return;
    final id = post.id.trim();
    if (!feed.any((p) => p.id == id)) return;
    // Write feed entry directly — avoid rememberFeed re-merge clobber.
    _feedMemory =
        _MemoryCacheEntry([
          for (final p in feed) p.id == id ? post : p,
        ], DateTime.now());
  }

  /// Persist optimistic / confirmed likedByMe so a later one-shot get
  /// cannot reset the heart icon while a write is in flight or just done.
  void setLikedByMeCache(String postId, bool likedByMe) {
    final id = postId.trim();
    if (id.isEmpty) return;
    final uid = AuthService.instance.kakaoUserId?.trim();
    _ensureLikeCacheUid(uid);
    if (uid == null || uid.isEmpty) return;
    _likeCache[id] = likedByMe;
  }

  /// Persist home feed page in memory (also warms per-post cache).
  ///
  /// [preferServerCounts]: when true (explicit pull-to-refresh), never
  /// replace Firestore likeCount/commentCount with stale memory values.
  void rememberFeed(
    List<Post> posts, {
    bool preferServerCounts = false,
  }) {
    final merged = [
      for (final p in posts)
        preferServerCounts ? p : _withLocalLikeOverride(p),
    ];
    _feedMemory =
        _MemoryCacheEntry(List<Post>.from(merged), DateTime.now());
    rememberPosts(merged);
  }

  /// Keep only MY likedByMe from optimistic cache.
  /// Never overwrite server [likeCount] — that includes other users' likes.
  Post _withLocalLikeOverride(Post post) {
    final liked = _likeCache[post.id];
    if (liked == null || post.likedByMe == liked) return post;
    return post.copyWith(likedByMe: liked);
  }

  /// Valid home feed within [memoryCacheTtl].
  List<Post>? peekCachedFeed() {
    final entry = _feedMemory;
    if (entry == null || entry.isExpired(memoryCacheTtl)) return null;
    return List<Post>.from(entry.value);
  }

  /// Home feed ignoring TTL (UI seed / merge with StreamBuilder).
  List<Post>? peekCachedFeedStale() {
    final entry = _feedMemory;
    if (entry == null) return null;
    return List<Post>.from(entry.value);
  }

  void invalidateFeed() {
    _feedMemory = null;
  }

  /// Soft-remap denormalized author nicknames after a profile rename.
  void remapAuthorNickname(String authorId, String nickname) {
    final uid = authorId.trim();
    final nick = nickname.trim();
    if (uid.isEmpty || nick.isEmpty) return;

    final feed = _feedMemory?.value;
    if (feed != null) {
      _feedMemory = _MemoryCacheEntry(
        [
          for (final p in feed)
            p.authorId?.trim() == uid && !p.authorWithdrawn
                ? p.copyWith(author: nick)
                : p,
        ],
        _feedMemory!.fetchedAt,
      );
    }

    for (final e in _postMemory.entries.toList()) {
      final p = e.value.value;
      if (p.authorId?.trim() == uid && !p.authorWithdrawn) {
        _postMemory[e.key] = _MemoryCacheEntry(
          p.copyWith(author: nick),
          e.value.fetchedAt,
        );
      }
    }
  }

  /// After withdrawal CF: remap cached posts from Kakao uid → deleted id.
  void applyAuthorWithdrawalInCache({
    required String oldAuthorId,
    required String deletedAuthorId,
    required String displayNickname,
  }) {
    final oldId = oldAuthorId.trim();
    final deletedId = deletedAuthorId.trim();
    final nick = displayNickname.trim();
    if (oldId.isEmpty || deletedId.isEmpty || nick.isEmpty) return;

    Post mapPost(Post p) {
      if (p.authorId?.trim() != oldId) return p;
      return p.copyWith(
        authorId: deletedId,
        author: nick,
        authorWithdrawn: true,
        clearAuthorProfileImage: true,
      );
    }

    final feed = _feedMemory?.value;
    if (feed != null) {
      _feedMemory = _MemoryCacheEntry(
        [for (final p in feed) mapPost(p)],
        _feedMemory!.fetchedAt,
      );
    }

    for (final e in _postMemory.entries.toList()) {
      final next = mapPost(e.value.value);
      if (!identical(next, e.value.value)) {
        _postMemory[e.key] = _MemoryCacheEntry(next, e.value.fetchedAt);
      }
    }

    invalidateAuthorPosts(oldId);
  }

  /// Soft-insert after create so feed UI updates without a server re-read.
  void prependToFeedCache(Post post) {
    final current = _feedMemory?.value ?? const <Post>[];
    final next = <Post>[
      post,
      ...current.where((p) => p.id != post.id),
    ];
    rememberFeed(next.take(feedPageSize).toList());
  }

  void removeFromFeedCache(String postId) {
    final id = postId.trim();
    final current = _feedMemory?.value;
    if (current == null || id.isEmpty) return;
    rememberFeed(current.where((p) => p.id != id).toList());
  }

  void invalidateTopicPosts([String? topicId]) {
    final id = topicId?.trim() ?? '';
    if (id.isEmpty) {
      _topicListMemory.clear();
    } else {
      _topicListMemory.remove(id);
    }
  }

  /// Valid cached post within [memoryCacheTtl], or null.
  Post? peekCachedPost(String postId) {
    final id = postId.trim();
    if (id.isEmpty) return null;
    final entry = _postMemory[id];
    if (entry == null || entry.isExpired(memoryCacheTtl)) return null;
    return entry.value;
  }

  /// Any cached post ignoring TTL (stale-while-revalidate UI seed).
  Post? peekCachedPostStale(String postId) {
    final id = postId.trim();
    if (id.isEmpty) return null;
    return _postMemory[id]?.value;
  }

  void invalidatePost(String postId) {
    final id = postId.trim();
    _postMemory.remove(id);
    removeFromFeedCache(id);
    _similarMemory.removeWhere((key, _) => key.contains(id));
  }

  void invalidateAuthorPosts([String? authorId]) {
    final id = authorId?.trim() ?? '';
    if (id.isEmpty) {
      _authorListMemory.clear();
    } else {
      _authorListMemory.remove(id);
    }
  }

  void invalidateSimilarForTopic(String? topicId) {
    final tid = topicId?.trim() ?? '';
    if (tid.isEmpty) {
      _similarMemory.clear();
      return;
    }
    _similarMemory.removeWhere((key, _) => key.startsWith('$tid|'));
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

  /// `likedBy` map on the post (same idea as `pollVoters`). null = legacy.
  bool? _likedByMeFromMap(Map<String, dynamic> data, String uid) {
    if (!data.containsKey('likedBy')) return null;
    final likedBy = data['likedBy'];
    if (likedBy is! Map) return false;
    return likedBy[uid] == true;
  }

  /// Latest posts first (`createdAt` descending).
  ///
  /// Cache-first: within [memoryCacheTtl] emits memory only (0 reads).
  /// On miss, performs a one-shot fetch and caches the page (no long-lived
  /// snapshot listener — pull-to-refresh / TTL expiry revalidate instead).
  Stream<List<Post>> watchPosts() {
    final cached = peekCachedFeed();
    if (cached != null) {
      debugPrint('home feed memory hit (${cached.length})');
      return Stream<List<Post>>.value(cached);
    }

    return Stream.fromFuture(
      fetchLatestPosts(forceRefresh: true, fromServer: true),
    );
  }

  /// One-shot fetch (pull-to-refresh). Cache-first within TTL unless forced.
  ///
  /// [forceRefresh] true → always hit Firestore server, update memory cache.
  /// Soft-update race guards apply only to non-forced fetches so optimistic
  /// taps are not clobbered; explicit refresh treats server as source of truth.
  Future<List<Post>> fetchLatestPosts({
    bool fromServer = true,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = peekCachedFeed();
      if (cached != null) {
        debugPrint('home feed refresh memory hit (${cached.length})');
        debugPrint('[REFRESH_DEBUG] CACHE USED');
        return cached;
      }
    } else {
      debugPrint('[REFRESH_DEBUG] refresh start');
      debugPrint('[REFRESH_DEBUG] forceRefresh=true');
      debugPrint('[POLL_REFRESH_DEBUG] refresh start');
    }

    final fetchStartedAt = DateTime.now();
    try {
      debugPrint('[REFRESH_DEBUG] Firestore fetch start');
      if (forceRefresh) {
        debugPrint('[POLL_REFRESH_DEBUG] Firestore poll fetch start');
      }
      final snap = await _posts
          .orderBy('createdAt', descending: true)
          .limit(feedPageSize)
          .get(
            fromServer || forceRefresh
                ? const GetOptions(source: Source.server)
                : const GetOptions(),
          );

      // Non-forced only: keep in-flight optimistic patches.
      if (!forceRefresh) {
        final localDuringFetch = _feedMemory;
        if (localDuringFetch != null &&
            localDuringFetch.fetchedAt.isAfter(fetchStartedAt)) {
          debugPrint('home feed keep local soft update');
          return List<Post>.from(localDuringFetch.value);
        }
      }

      final posts = await _mapAndEnrich(snap);

      if (!forceRefresh) {
        final localAfterMap = _feedMemory;
        if (localAfterMap != null &&
            localAfterMap.fetchedAt.isAfter(fetchStartedAt)) {
          final localById = {
            for (final p in localAfterMap.value) p.id: p,
          };
          final merged = [
            for (final p in posts) localById[p.id] ?? p,
          ];
          rememberFeed(merged);
          return merged;
        }
      }

      // Force refresh: server wins for counts; sync like cache from docs.
      rememberFeed(posts, preferServerCounts: forceRefresh);
      if (forceRefresh) {
        debugPrint('[REFRESH_DEBUG] Firestore fetch success');
        for (final p in posts) {
          debugPrint(
            '[REFRESH_DEBUG] postId=${p.id} likeCount=${p.likeCount} '
            'commentCount=${p.commentCount} '
            'poll=${p.poll?.options.map((o) => o.votes).toList()}',
          );
          _logPollRefresh(p, phase: 'feed');
        }
        debugPrint('[POLL_REFRESH_DEBUG] poll cache updated');
        debugPrint('[REFRESH_DEBUG] cache updated');
        debugPrint('[REFRESH_DEBUG] refresh complete');
        debugPrint('[POLL_REFRESH_DEBUG] refresh complete');
      }
      return posts;
    } on FirebaseException catch (e) {
      // Offline / unavailable → fall back to cache.
      if (fromServer &&
          (e.code == 'unavailable' || e.code == 'cloud-firestore')) {
        debugPrint('서버 새로고침 실패, 캐시 사용: $e');
        final stale = peekCachedFeedStale();
        if (stale != null) return stale;
        return fetchLatestPosts(fromServer: false, forceRefresh: true);
      }
      rethrow;
    }
  }

  /// Client-side keyword search over recent Firestore posts.
  ///
  /// Scans up to [searchScanLimit] newest posts (paginated), then filters by
  /// content / tags / poll question — same match rules as the old local search.
  /// Does not invent mock rows; empty query → empty list.
  Future<List<Post>> searchPosts(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final pool = <Post>[];
    DocumentSnapshot<Map<String, dynamic>>? last;
    try {
      while (pool.length < searchScanLimit) {
        final remaining = searchScanLimit - pool.length;
        final pageLimit =
            remaining < feedPageSize ? remaining : feedPageSize;
        Query<Map<String, dynamic>> qRef = _posts
            .orderBy('createdAt', descending: true)
            .limit(pageLimit);
        if (last != null) {
          qRef = qRef.startAfterDocument(last);
        }
        final snap = await qRef.get();
        if (snap.docs.isEmpty) break;

        final mapped = await _mapAndEnrich(snap);
        pool.addAll(mapped);
        last = snap.docs.last;
        if (snap.size < pageLimit) break;
      }
    } catch (e, st) {
      debugPrint('검색 게시글 조회 실패: $e');
      debugPrint('$st');
      rethrow;
    }

    final matched = pool.where((p) => _matchesSearchQuery(p, q)).toList()
      ..sort((a, b) => b.likeCount.compareTo(a.likeCount));
    return matched;
  }

  static bool _matchesSearchQuery(Post p, String q) {
    final inContent = p.content.toLowerCase().contains(q);
    final inTags = p.tags.any((t) => t.toLowerCase().contains(q));
    final inPoll = p.poll?.question.toLowerCase().contains(q) ?? false;
    return inContent || inTags || inPoll;
  }

  /// Lightweight check: 1-doc server read of the newest post vs feed cache.
  /// Does not load or replace the feed. Returns true when newer content exists.
  Future<bool> hasNewerPostsThanCache() async {
    final cached = peekCachedFeedStale();
    if (cached == null || cached.isEmpty) return false;

    // Prefer chronological newest in cache (not display sort order).
    var newestCached = cached.first;
    for (final p in cached) {
      if (p.createdAt.isAfter(newestCached.createdAt)) {
        newestCached = p;
      }
    }

    try {
      final snap = await _posts
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (snap.docs.isEmpty) return false;

      final doc = snap.docs.first;
      final latestId = doc.id;
      final raw = doc.data()['createdAt'];
      DateTime? serverCreated;
      if (raw is Timestamp) {
        serverCreated = raw.toDate();
      } else if (raw is DateTime) {
        serverCreated = raw;
      }

      final byId = latestId != newestCached.id;
      final byTime = serverCreated != null &&
          serverCreated.isAfter(newestCached.createdAt);
      final newer = byId || byTime;
      if (newer) {
        debugPrint(
          'newer posts detected (server=$latestId '
          'cache=${newestCached.id} byId=$byId byTime=$byTime)',
        );
      }
      return newer;
    } catch (e) {
      debugPrint('최신 글 감지 실패: $e');
      return false;
    }
  }

  /// Posts written by [authorId], newest first.
  /// One-shot stream (no live `snapshots()`). Prefer [fetchPostsByAuthor].
  Stream<List<Post>> watchPostsByAuthor(String authorId) {
    return Stream.fromFuture(fetchPostsByAuthor(authorId));
  }

  /// Posts for a topic id, newest first.
  /// One-shot stream (no live `snapshots()`). Prefer [fetchPostsByTopicId].
  Stream<List<Post>> watchPostsByTopicId(String topicId) {
    return Stream.fromFuture(fetchPostsByTopicId(topicId));
  }

  /// One-shot fetch for topic feeds (supports client-side popular sort).
  Future<List<Post>> fetchPostsByTopicId(
    String topicId, {
    bool forceRefresh = false,
  }) async {
    final id = topicId.trim();
    if (id.isEmpty) return const [];

    if (!forceRefresh) {
      final cached = _topicListMemory[id];
      if (cached != null && !cached.isExpired(memoryCacheTtl)) {
        debugPrint('topic posts memory hit ($id)');
        return List<Post>.from(cached.value);
      }
    }

    final snap = await _posts
        .where('topicId', isEqualTo: id)
        .orderBy('createdAt', descending: true)
        .limit(feedPageSize)
        .get();
    final posts = await _mapAndEnrich(snap);
    _topicListMemory[id] =
        _MemoryCacheEntry(List<Post>.from(posts), DateTime.now());
    return posts;
  }

  Future<List<Post>> _mapAndEnrich(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final uid = AuthService.instance.kakaoUserId?.trim();
    _ensureLikeCacheUid(uid);

    final posts = snapshot.docs.map((doc) {
      final data = doc.data();
      var post = Post.fromFirestore(doc.id, data);
      if (uid != null && uid.isNotEmpty && post.poll != null) {
        final rawVoters = data['pollVoters'];
        if (rawVoters is Map) {
          final optionId = rawVoters[uid]?.toString().trim();
          post = post.copyWith(
            poll: post.poll!.withMyVote(
              (optionId != null && optionId.isNotEmpty) ? optionId : null,
            ),
          );
        }
      }
      if (uid != null && uid.isNotEmpty) {
        final fromMap = _likedByMeFromMap(data, uid);
        if (fromMap != null) {
          post = post.copyWith(likedByMe: fromMap);
          _likeCache[post.id] = fromMap;
        } else if (_likeCache.containsKey(post.id)) {
          post = post.copyWith(likedByMe: _likeCache[post.id]!);
        }
      }
      return post;
    }).toList();
    rememberPosts(posts);
    final withLikes = await enrichWithMyLikes(posts);
    return applyLiveAuthorNicknames(withLikes);
  }

  /// Replace denormalized author with current `users/{authorId}.nickname`.
  /// Skips withdrawn authors — always keep [AppConstants.withdrawnAuthorNickname].
  Future<List<Post>> applyLiveAuthorNicknames(List<Post> posts) async {
    if (posts.isEmpty) return posts;
    final resolved = [
      for (final p in posts)
        p.authorWithdrawn
            ? (p.author == AppConstants.withdrawnAuthorNickname
                ? p
                : p.copyWith(author: AppConstants.withdrawnAuthorNickname))
            : p,
    ];
    final lookupIds = resolved
        .where((p) => !p.authorWithdrawn)
        .map((p) => p.authorId ?? '');
    final map = await NicknameLookupCache.instance.resolveMany(lookupIds);
    if (map.isEmpty) return resolved;
    final out = <Post>[];
    for (final p in resolved) {
      if (p.authorWithdrawn) {
        out.add(p);
        continue;
      }
      final live = map[p.authorId?.trim() ?? ''];
      if (live != null && live.isNotEmpty && live != p.author) {
        out.add(p.copyWith(author: live));
      } else {
        out.add(p);
      }
    }
    return out;
  }

  /// Attach my vote + like flags for the signed-in user.
  Future<List<Post>> enrichPosts(List<Post> posts) async {
    var next = await enrichWithMyVotes(posts);
    next = await enrichWithMyLikes(next);
    next = await applyLiveAuthorNicknames(next);
    return next;
  }

  /// Attach hasVoted from post `pollVoters.{auth.uid}` (or legacy poll_votes).
  Future<List<Post>> enrichWithMyVotes(List<Post> posts) async {
    final uid = AuthService.instance.kakaoUserId?.trim();
    if (uid == null || uid.isEmpty) return posts;

    final indexed = <int, Post>{};
    final futures = <Future<void>>[];

    for (var i = 0; i < posts.length; i++) {
      final post = posts[i];
      if (post.poll == null) {
        indexed[i] = post;
        continue;
      }
      // Prefer vote already applied from pollVoters during mapping.
      if (post.poll!.hasVoted) {
        indexed[i] = post;
        continue;
      }
      futures.add(() async {
        try {
          // Legacy fallback: posts/{id}/poll_votes/{uid}
          final voteSnap = await _votesRef(post.id).doc(uid).get();
          final optionId =
              (voteSnap.data()?['optionId'] as String?)?.trim();
          indexed[i] = post.copyWith(
            poll: post.poll!.withMyVote(voteSnap.exists ? optionId : null),
          );
        } catch (e) {
          debugPrint('투표 상태 조회 실패 (${post.id}): $e');
          indexed[i] = post;
        }
      }());
    }

    await Future.wait(futures);
    return [
      for (var i = 0; i < posts.length; i++) indexed[i] ?? posts[i],
    ];
  }

  /// Attach likedByMe from post `likedBy.{uid}` (preferred) or legacy like doc.
  /// Uses an in-memory cache so snapshot churn does not re-read every post.
  Future<List<Post>> enrichWithMyLikes(List<Post> posts) async {
    final uid = AuthService.instance.kakaoUserId?.trim();
    if (uid == null || uid.isEmpty) return posts;
    if (posts.isEmpty) return posts;
    _ensureLikeCacheUid(uid);

    final indexed = <int, Post>{};
    final futures = <Future<void>>[];

    for (var i = 0; i < posts.length; i++) {
      final post = posts[i];
      if (_likeCache.containsKey(post.id)) {
        indexed[i] = post.copyWith(likedByMe: _likeCache[post.id]!);
        continue;
      }
      futures.add(() async {
        try {
          final likeSnap = await _likesRef(post.id).doc(uid).get();
          final liked = likeSnap.exists;
          _likeCache[post.id] = liked;
          indexed[i] = post.copyWith(likedByMe: liked);
        } catch (e) {
          debugPrint('공감 상태 조회 실패 (${post.id}): $e');
          indexed[i] = post;
        }
      }());
    }

    await Future.wait(futures);
    return [
      for (var i = 0; i < posts.length; i++) indexed[i] ?? posts[i],
    ];
  }

  /// Posts written by [authorId], newest first (one-shot + memory TTL).
  /// Prefer this over [watchPostsByAuthor] for profile / my-posts screens.
  Future<List<Post>> fetchPostsByAuthor(
    String authorId, {
    bool forceRefresh = false,
  }) async {
    final uid = authorId.trim();
    if (uid.isEmpty) return const [];

    if (!forceRefresh) {
      final cached = _authorListMemory[uid];
      if (cached != null && !cached.isExpired(memoryCacheTtl)) {
        debugPrint('author posts memory hit ($uid)');
        return List<Post>.from(cached.value);
      }
    }

    final snap = await _posts
        .where('authorId', isEqualTo: uid)
        .limit(feedPageSize)
        .get();
    final posts = await _mapAndEnrich(snap);
    posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _authorListMemory[uid] =
        _MemoryCacheEntry(List<Post>.from(posts), DateTime.now());
    return posts;
  }

  Future<Post?> getPost(
    String postId, {
    bool forceRefresh = false,
  }) async {
    final id = postId.trim();
    if (id.isEmpty) return null;

    if (!forceRefresh) {
      final cached = peekCachedPost(id);
      if (cached != null) {
        debugPrint('post detail memory hit ($id)');
        debugPrint('[REFRESH_DEBUG] CACHE USED');
        if (cached.poll != null) {
          debugPrint('[POLL_REFRESH_DEBUG] CACHE USED');
        }
        return cached;
      }
    } else {
      debugPrint('[REFRESH_DEBUG] refresh start');
      debugPrint('[REFRESH_DEBUG] forceRefresh=true postId=$id');
      debugPrint('[POLL_REFRESH_DEBUG] refresh start');
      debugPrint('[POLL_REFRESH_DEBUG] postId=$id');
    }

    debugPrint('[REFRESH_DEBUG] Firestore fetch start');
    if (forceRefresh) {
      debugPrint('[POLL_REFRESH_DEBUG] Firestore poll fetch start');
    }
    final snap = await _posts.doc(id).get(
          forceRefresh
              ? const GetOptions(source: Source.server)
              : const GetOptions(),
        );
    if (!snap.exists || snap.data() == null) return null;
    final data = snap.data()!;
    var post = Post.fromFirestore(snap.id, data);
    if (forceRefresh && post.poll != null) {
      debugPrint('[POLL_REFRESH_DEBUG] Firestore poll fetch success');
      debugPrint('[POLL_REFRESH_DEBUG] pollId=embedded:${post.id}');
    }
    final uid = AuthService.instance.kakaoUserId?.trim();
    _ensureLikeCacheUid(uid);
    if (uid != null && uid.isNotEmpty && post.poll != null) {
      final rawVoters = data['pollVoters'];
      if (rawVoters is Map) {
        final optionId = rawVoters[uid]?.toString().trim();
        post = post.copyWith(
          poll: post.poll!.withMyVote(
            (optionId != null && optionId.isNotEmpty) ? optionId : null,
          ),
        );
      }
    }
    if (uid != null && uid.isNotEmpty) {
      final fromMap = _likedByMeFromMap(data, uid);
      if (fromMap != null) {
        post = post.copyWith(likedByMe: fromMap);
        _likeCache[post.id] = fromMap;
        var voted = (await enrichWithMyVotes([post])).first;
        // Must apply live users/{authorId}.nickname — do not return the
        // denormalized snapshot from the post doc (notification open path).
        voted = (await applyLiveAuthorNicknames([voted])).first;
        rememberPost(voted);
        if (forceRefresh) {
          debugPrint(
            '[REFRESH_DEBUG] likeCount=${voted.likeCount} '
            'commentCount=${voted.commentCount} '
            'poll=${voted.poll?.options.map((o) => o.votes).toList()}',
          );
          _logPollRefresh(voted, phase: 'detail');
          debugPrint('[POLL_REFRESH_DEBUG] poll cache updated');
          debugPrint('[REFRESH_DEBUG] cache updated');
          debugPrint('[REFRESH_DEBUG] Firestore fetch success');
          debugPrint('[POLL_REFRESH_DEBUG] refresh complete');
        }
        return voted;
      }
    }
    final enriched = await enrichPosts([post]);
    final result = enriched.first;
    rememberPost(result);
    if (forceRefresh) {
      debugPrint(
        '[REFRESH_DEBUG] likeCount=${result.likeCount} '
        'commentCount=${result.commentCount} '
        'poll=${result.poll?.options.map((o) => o.votes).toList()}',
      );
      _logPollRefresh(result, phase: 'detail');
      debugPrint('[POLL_REFRESH_DEBUG] poll cache updated');
      debugPrint('[REFRESH_DEBUG] cache updated');
      debugPrint('[REFRESH_DEBUG] Firestore fetch success');
      debugPrint('[POLL_REFRESH_DEBUG] refresh complete');
    }
    return result;
  }

  /// Pull-to-refresh poll diagnostics (embedded `posts/{id}.poll`).
  void _logPollRefresh(Post post, {required String phase}) {
    final poll = post.poll;
    if (poll == null) return;
    debugPrint('[POLL_REFRESH_DEBUG] phase=$phase postId=${post.id}');
    debugPrint('[POLL_REFRESH_DEBUG] pollId=embedded:${post.id}');
    String? myVote;
    for (final o in poll.options) {
      debugPrint('[POLL_REFRESH_DEBUG] optionId=${o.id}');
      debugPrint('[POLL_REFRESH_DEBUG] optionText=${o.text}');
      debugPrint('[POLL_REFRESH_DEBUG] firestoreVoteCount=${o.votes}');
      if (o.selectedByMe) myVote = o.id;
    }
    debugPrint(
      '[POLL_REFRESH_DEBUG] currentUserVote=${myVote ?? '(none)'} '
      'hasVoted=${poll.hasVoted} totalVotes=${poll.totalVotes}',
    );
  }

  /// Same-topic posts for "비슷한 글". Excludes [excludePostId].
  Future<List<Post>> fetchSimilarPosts({
    required String topicId,
    required String excludePostId,
    int limit = 5,
    bool forceRefresh = false,
  }) async {
    final tid = topicId.trim();
    if (tid.isEmpty) return const [];

    final cacheKey = '$tid|${excludePostId.trim()}|$limit';
    if (!forceRefresh) {
      final cached = _similarMemory[cacheKey];
      if (cached != null && !cached.isExpired(memoryCacheTtl)) {
        debugPrint('similar posts memory hit ($cacheKey)');
        return List<Post>.from(cached.value);
      }
    }

    final snap = await _posts
        .where('topicId', isEqualTo: tid)
        .orderBy('createdAt', descending: true)
        .limit((limit + 1).clamp(2, 12))
        .get();

    final posts = snap.docs
        .map((doc) {
          final data = doc.data();
          var post = Post.fromFirestore(doc.id, data);
          final uid = AuthService.instance.kakaoUserId?.trim();
          if (uid != null && uid.isNotEmpty) {
            final fromMap = _likedByMeFromMap(data, uid);
            if (fromMap != null) {
              post = post.copyWith(likedByMe: fromMap);
              _likeCache[post.id] = fromMap;
            }
          }
          return post;
        })
        .where((p) => p.id != excludePostId)
        .toList();

    posts.sort((a, b) {
      final byLikes = b.likeCount.compareTo(a.likeCount);
      if (byLikes != 0) return byLikes;
      return b.createdAt.compareTo(a.createdAt);
    });

    final capped = posts.take(limit).toList();
    final enriched = await enrichPosts(capped);
    rememberPosts(enriched);
    _similarMemory[cacheKey] =
        _MemoryCacheEntry(List<Post>.from(enriched), DateTime.now());
    return enriched;
  }

  /// Toggle like. Doc id = Kakao user id (1 like / user / post).
  Future<Post> toggleLike({
    required String postId,
    String? userId,
  }) async {
    AuthService.instance.requireKakaoWriter();
    final uid = (userId ?? AuthService.instance.kakaoUserId)?.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('카카오 로그인 후 이용해 주세요.');
    }

    late Post result;
    await _firestore.runTransaction((tx) async {
      final postRef = _posts.doc(postId);
      final likeRef = _likesRef(postId).doc(uid);
      final postSnap = await tx.get(postRef);
      final likeSnap = await tx.get(likeRef);

      if (!postSnap.exists || postSnap.data() == null) {
        throw StateError('글을 찾을 수 없어요.');
      }

      final data = postSnap.data()!;
      final current = (data['likeCount'] as num?)?.toInt() ?? 0;
      var post = Post.fromFirestore(postSnap.id, data);

      if (likeSnap.exists) {
        final nextCount = (current - 1).clamp(0, 1 << 30);
        tx.delete(likeRef);
        tx.update(postRef, {
          'likeCount': nextCount,
          'likedBy.$uid': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        result = post.copyWith(likedByMe: false, likeCount: nextCount);
      } else {
        final nextCount = current + 1;
        tx.set(likeRef, {
          'userId': uid,
          'postId': postId,
          'kakaoUserId': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(postRef, {
          'likeCount': FieldValue.increment(1),
          'likedBy.$uid': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        result = post.copyWith(likedByMe: true, likeCount: nextCount);
      }
    });

    _ensureLikeCacheUid(uid);
    _likeCache[postId] = result.likedByMe;
    // Keep optimistic commentCount if a local comment landed during the tx.
    final mem = peekCachedPostStale(postId);
    final memCount = mem?.remoteCommentCount;
    final resultCount = result.remoteCommentCount;
    if (memCount != null &&
        (resultCount == null || memCount > resultCount)) {
      result = result.copyWith(remoteCommentCount: memCount);
    }
    rememberPost(result);
    final feed = _feedMemory?.value;
    if (feed != null) {
      _feedMemory = _MemoryCacheEntry([
        for (final p in feed) p.id == result.id ? result : p,
      ], DateTime.now());
    }
    return result;
  }

  /// Create a post. Resolves/creates topic and increments usage on success.
  Future<Post> createPost({
    required String content,
    required String authorId,
    required String authorNickname,
    String authorProfileImage = '',
    String? experience,
    String? cafeType,
    String? topicName,
    List<String> tags = const [],
    Poll? poll,
  }) async {
    AuthService.instance.requireKakaoWriter();

    final text = content.trim();
    final hasPoll = poll != null &&
        poll.options.where((o) => o.text.trim().isNotEmpty).length >= 2;
    if (text.isEmpty && !hasPoll) {
      throw ArgumentError('내용이 비어 있어요.');
    }

    String profileImage = authorProfileImage.trim();
    if (profileImage.isEmpty) {
      final profileUid = authorId.trim().isNotEmpty
          ? authorId.trim()
          : (AuthService.instance.kakaoUserId?.trim() ?? '');
      try {
        if (profileUid.isNotEmpty) {
          final userDoc =
              await _firestore.collection('users').doc(profileUid).get();
          profileImage =
              (userDoc.data()?['profileImage'] as String?)?.trim() ?? '';
        }
      } catch (e) {
        debugPrint('프로필 이미지 조회 실패: $e');
      }
    }

    Topic? topic;
    final rawTopic = (topicName ?? (tags.isNotEmpty ? tags.first : null));
    if (rawTopic != null && normalizeTopicName(rawTopic).isNotEmpty) {
      topic = await _topics.ensureTopic(rawTopic);
    }

    final doc = _posts.doc();
    final nickname =
        authorNickname.trim().isEmpty ? '익명' : authorNickname.trim();
    final topicTags =
        topic == null ? const <String>[] : <String>[topic.name];

    Poll? storedPoll;
    if (poll != null &&
        poll.options.where((o) => o.text.trim().isNotEmpty).length >= 2) {
      storedPoll = Poll(
        title: poll.trimmedTitle,
        question: poll.question.trim(),
        options: [
          for (var i = 0; i < poll.options.length; i++)
            PollOption(
              id: poll.options[i].id.trim().isEmpty
                  ? 'opt_$i'
                  : poll.options[i].id.trim(),
              text: poll.options[i].text.trim(),
              votes: 0,
            ),
        ],
      );
    }

    final data = <String, dynamic>{
      'content': text,
      'authorId': authorId,
      'authorNickname': nickname,
      'nickname': nickname,
      'authorProfileImage': profileImage,
      'experience': experience ?? '',
      'cafeType': cafeType ?? '',
      'likeCount': 0,
      'commentCount': 0,
      'likedBy': <String, dynamic>{},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'tags': topicTags,
    };

    if (topic != null) {
      data['topicId'] = topic.id;
      data['topicName'] = topic.name;
    } else {
      data['topicId'] = null;
      data['topicName'] = null;
    }

    if (storedPoll != null) {
      data['poll'] = storedPoll.toMap();
    }

    final batch = _firestore.batch();
    batch.set(doc, data);
    // usageCount is maintained by Cloud Function triggers (not client).
    await batch.commit();

    _topics.invalidatePopularCache();

    final created = Post(
      id: doc.id,
      content: text,
      createdAt: DateTime.now(),
      author: nickname,
      authorId: authorId,
      authorProfileImage: profileImage,
      experience: experience,
      cafeType: cafeType,
      tags: topicTags,
      topicId: topic?.id,
      topicName: topic?.name,
      remoteCommentCount: 0,
      poll: storedPoll,
    );
    rememberPost(created);
    prependToFeedCache(created);
    invalidateAuthorPosts(authorId);
    invalidateSimilarForTopic(topic?.id);
    invalidateTopicPosts(topic?.id);
    return created;
  }

  /// Cast or change a vote via Cloud Function `castVote` (Admin SDK tx).
  ///
  /// Client does **not** write `pollVoters` / `voteCount` directly.
  /// Uses Firebase Auth uid on the server (Custom Token = Kakao id).
  Future<Post> castVote({
    required String postId,
    required String optionId,
  }) async {
    AuthService.instance.requireKakaoWriter();
    final id = postId.trim();
    final optId = optionId.trim();
    if (id.isEmpty || optId.isEmpty) {
      throw ArgumentError('투표 정보가 올바르지 않아요.');
    }

    await _ensureFirebaseAuthForVote();

    final callable = FirebaseFunctions.instanceFor(
      region: FirebaseAuthBridge.region,
    ).httpsCallable('castVote');

    final result = await callable.call(<String, dynamic>{
      'postId': id,
      'optionId': optId,
      // Never send a trusted userId — server uses request.auth.uid only.
    });

    final raw = result.data;
    if (raw is! Map) {
      throw StateError('투표 응답이 올바르지 않아요.');
    }
    final map = Map<String, dynamic>.from(raw);
    if (map['success'] != true) {
      throw StateError('투표를 저장하지 못했어요.');
    }

    final selectedRaw = map['selectedOptionId'];
    final String? selectedOptionId = selectedRaw == null
        ? null
        : selectedRaw.toString().trim().isEmpty
            ? null
            : selectedRaw.toString().trim();

    final optionsRaw = map['options'];
    final serverOptions = <PollOption>[];
    if (optionsRaw is List) {
      for (final item in optionsRaw) {
        if (item is Map) {
          final opt = PollOption.fromMap(Map<String, dynamic>.from(item));
          if (opt.id.isNotEmpty) serverOptions.add(opt);
        }
      }
    }

    var baseline = peekCachedPostStale(id) ?? PostService.instance.getById(id);
    baseline ??= await getPost(id, forceRefresh: true);
    if (baseline == null) {
      throw StateError('글을 찾을 수 없어요.');
    }

    final existing = baseline.poll;
    final byId = <String, PollOption>{
      for (final o in existing?.options ?? <PollOption>[]) o.id: o,
    };

    final options = <PollOption>[];
    if (serverOptions.isNotEmpty) {
      for (final o in serverOptions) {
        options.add(
          o.copyWith(
            text: o.text.isNotEmpty ? o.text : (byId[o.id]?.text ?? o.text),
          ),
        );
      }
    } else if (existing != null) {
      options.addAll(existing.options);
    }

    final poll = Poll(
      title: existing?.trimmedTitle,
      question: existing?.question ?? '',
      options: options,
    ).withMyVote(selectedOptionId);

    var post = baseline.copyWith(poll: poll);

    if (_likeCache.containsKey(id)) {
      post = post.copyWith(likedByMe: _likeCache[id]!);
    }

    rememberPost(post);
    final feed = _feedMemory?.value;
    if (feed != null) {
      rememberFeed([
        for (final p in feed) p.id == post.id ? post : p,
      ]);
    }
    return post;
  }

  Future<void> _ensureFirebaseAuthForVote() async {
    if (FirebaseAuthBridge.instance.isSignedIn) return;
    final ok =
        await FirebaseAuthBridge.instance.signInWithCurrentKakaoToken();
    if (!ok || !FirebaseAuthBridge.instance.isSignedIn) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Firebase Auth session required to vote.',
      );
    }
  }

  /// Update content / topic. Poll structure edits go through [editPostPoll] CF.
  ///
  /// When [poll] is provided or [clearPoll] is true, tallies are applied by
  /// Admin SDK (`editPostPoll`) so clients cannot rewrite voteCount/pollVoters.
  Future<Post> updatePost({
    required String postId,
    required String content,
    String? topicName,
    bool clearTopic = false,
    Poll? poll,
    bool clearPoll = false,
  }) async {
    AuthService.instance.requireKakaoWriter();

    final text = content.trim();
    final hasPoll = poll != null &&
        poll.options.where((o) => o.text.trim().isNotEmpty).length >= 2;
    if (text.isEmpty && !hasPoll && !clearPoll) {
      throw ArgumentError('내용이 비어 있어요.');
    }

    final ref = _posts.doc(postId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) {
      throw StateError('글을 찾을 수 없어요.');
    }
    final data = Map<String, dynamic>.from(snap.data()!);
    final current = Post.fromFirestore(snap.id, data);

    String? nextTopicId;
    String? nextTopicName;
    final topicTags = <String>[];

    if (clearTopic) {
      nextTopicId = null;
      nextTopicName = null;
    } else if (topicName != null &&
        normalizeTopicName(topicName).isNotEmpty) {
      final topic = await _topics.ensureTopic(topicName);
      nextTopicId = topic.id;
      nextTopicName = topic.name;
      topicTags.add(topic.name);
    } else {
      nextTopicId = current.topicId;
      nextTopicName = current.topicName ?? current.topic;
      if (nextTopicName != null) topicTags.add(nextTopicName);
    }

    final updates = <String, dynamic>{
      'content': text,
      'topicId': nextTopicId,
      'topicName': nextTopicName,
      'tags': topicTags,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Never write poll / pollVoters from the client on post update.
    Poll? nextPoll = current.poll;
    if (clearPoll || hasPoll) {
      nextPoll = await _editPostPollViaCallable(
        postId: postId,
        poll: clearPoll ? null : poll,
        clearPoll: clearPoll,
      );
    }

    await ref.update(updates);

    // Topic usageCount: Cloud Function onPostUpdatedTopicUsage (not client).

    final updated = current.copyWith(
      content: text,
      topicId: nextTopicId,
      topicName: nextTopicName,
      tags: topicTags,
      clearTopic: clearTopic,
      clearPoll: clearPoll,
      poll: nextPoll?.clone(),
    );
    final enriched = await enrichPosts([updated]);
    final result = enriched.first;
    rememberPost(result);
    // Keep feed row in sync without forcing a full feed re-query.
    final feed = _feedMemory?.value;
    if (feed != null) {
      rememberFeed([
        for (final p in feed) p.id == result.id ? result : p,
      ], preferServerCounts: true);
    }
    invalidateAuthorPosts(result.authorId);
    invalidateSimilarForTopic(result.topicId);
    invalidateTopicPosts(result.topicId);
    invalidateSimilarForTopic(current.topicId);
    invalidateTopicPosts(current.topicId);
    _topics.invalidatePopularCache();
    return result;
  }

  /// Author poll edit / clear via Cloud Function (preserves vote tallies).
  Future<Poll?> _editPostPollViaCallable({
    required String postId,
    Poll? poll,
    required bool clearPoll,
  }) async {
    await _ensureFirebaseAuthForVote();
    final callable = FirebaseFunctions.instanceFor(
      region: FirebaseAuthBridge.region,
    ).httpsCallable('editPostPoll');

    final payload = <String, dynamic>{
      'postId': postId.trim(),
      'clearPoll': clearPoll,
    };
    if (!clearPoll && poll != null) {
      payload['poll'] = {
        if (poll.trimmedTitle != null) 'title': poll.trimmedTitle,
        'question': poll.question.trim(),
        'options': [
          for (final o in poll.options)
            if (o.text.trim().isNotEmpty)
              {
                'id': o.id.trim().isEmpty ? null : o.id.trim(),
                'text': o.text.trim(),
              },
        ],
      };
    }

    final result = await callable.call(payload);
    final raw = result.data;
    if (raw is! Map) {
      throw StateError('투표 수정 응답이 올바르지 않아요.');
    }
    final map = Map<String, dynamic>.from(raw);
    if (map['success'] != true) {
      throw StateError('투표를 수정하지 못했어요.');
    }
    if (map['cleared'] == true || map['poll'] == null) {
      return null;
    }
    final pollRaw = map['poll'];
    if (pollRaw is! Map) return null;
    return Poll.fromMap(Map<String, dynamic>.from(pollRaw));
  }

  /// Change only the topic of a post.
  Future<Post> updatePostTopic({
    required String postId,
    String? topicName,
  }) async {
    final clear = topicName == null || normalizeTopicName(topicName).isEmpty;
    final snap = await _posts.doc(postId).get();
    if (!snap.exists || snap.data() == null) {
      throw StateError('글을 찾을 수 없어요.');
    }
    final current = Post.fromFirestore(snap.id, snap.data()!);
    return updatePost(
      postId: postId,
      content: current.content,
      topicName: clear ? null : topicName,
      clearTopic: clear,
    );
  }

  /// Delete post + comments + likes. Does not delete Topic docs.
  Future<void> deletePost(String postId) async {
    AuthService.instance.requireKakaoWriter();

    final ref = _posts.doc(postId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data();
    final topicId = (data?['topicId'] as String?)?.trim();
    final authorId = (data?['authorId'] as String?)?.trim();

    await _deleteSubcollectionDocs(_commentsRef(postId));
    await _deleteSubcollectionDocs(_likesRef(postId));
    await _deleteSubcollectionDocs(_votesRef(postId));

    await ref.delete();
    invalidatePost(postId);
    invalidateAuthorPosts(authorId);
    invalidateSimilarForTopic(topicId);
    invalidateTopicPosts(topicId);
    _topics.invalidatePopularCache();
    // Topic usageCount: Cloud Function onPostDeletedTopicUsage (not client).
  }

  Future<void> _deleteSubcollectionDocs(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    try {
      QuerySnapshot<Map<String, dynamic>> page;
      do {
        page = await col.limit(200).get();
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in page.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } while (page.docs.isNotEmpty);
    } catch (e) {
      debugPrint('서브컬렉션 삭제 실패 (${col.path}): $e');
    }
  }
}

class _MemoryCacheEntry<T> {
  _MemoryCacheEntry(this.value, this.fetchedAt);

  final T value;
  final DateTime fetchedAt;

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(fetchedAt) > ttl;
}
