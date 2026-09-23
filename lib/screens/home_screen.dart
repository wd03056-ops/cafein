import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ads/ad_helper.dart';
import '../core/constants.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/block_firestore_service.dart';
import '../services/like_helper.dart';
import '../services/notification_inbox_service.dart';
import '../services/poll_vote_helper.dart';
import '../services/post_service.dart';
import '../services/posts_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/ads/cafein_native_ad_card.dart';
import '../widgets/edit_poll_sheet.dart';
import '../widgets/post_list_item.dart';
import '../widgets/post_more_sheet.dart';
import 'notifications_screen.dart';
import 'post_detail_screen.dart';
import 'search_screen.dart';
import 'topic_feed_screen.dart';
import 'write_post_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.isActive = true,
  });

  /// True when the home tab is visible (IndexedStack). Used to re-check
  /// for newer posts without breaking cache-first rendering.
  final bool isActive;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _postService = PostService.instance;
  final _postsFirestore = PostsFirestoreService.instance;
  final _blocks = BlockFirestoreService.instance;
  late final Stream<List<Post>> _postsStream;
  PostSort _sort = PostSort.popular;
  bool _showNewPostsBanner = false;
  bool _checkingNewer = false;
  Timer? _newerPollTimer;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// Light ID/timestamp probe while the user stays on the feed.
  /// Not a full feed fetch — 1 document read per tick when banner is hidden.
  static const _newerPollInterval = Duration(seconds: 20);

  /// Survives list rebuilds so NativeAd isn't disposed mid-load / refresh.
  final Map<int, GlobalKey> _nativeAdKeys = {};
  final ScrollController _feedScrollController = ScrollController(
    // Prevent restoring the previous tab's offset onto the reordered list.
    keepScrollOffset: false,
  );

  GlobalKey _nativeAdKey(int slot) =>
      _nativeAdKeys.putIfAbsent(slot, GlobalKey.new);

  bool get _shouldPoll =>
      mounted &&
      widget.isActive &&
      (_lifecycle == AppLifecycleState.resumed ||
          _lifecycle == AppLifecycleState.inactive);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _postsStream = _postsFirestore.watchPosts();
    _postService.addListener(_onChanged);
    _blocks.addListener(_onChanged);
    NotificationInboxService.instance.addListener(_onChanged);
    unawaited(_blocks.ensureLoaded());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.isActive) {
        unawaited(_checkForNewerPosts());
        _startNewerPoll();
      }
      unawaited(NotificationInboxService.instance.warmUnreadBadge());
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      unawaited(_checkForNewerPosts());
      _startNewerPoll();
    } else if (!widget.isActive && oldWidget.isActive) {
      _stopNewerPoll();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previous = _lifecycle;
    _lifecycle = state;

    // Background / killed — stop probes (no requests while app is away).
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopNewerPoll();
      return;
    }

    // Returning to foreground from a real background — one probe + restart.
    // Ignore inactive↔resumed flapping (notification shade, etc.).
    if (state == AppLifecycleState.resumed &&
        widget.isActive &&
        (previous == AppLifecycleState.paused ||
            previous == AppLifecycleState.hidden ||
            previous == AppLifecycleState.detached)) {
      unawaited(_checkForNewerPosts());
      _startNewerPoll();
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _startNewerPoll() {
    _stopNewerPoll();
    if (!_shouldPoll) return;
    _newerPollTimer = Timer.periodic(_newerPollInterval, (_) {
      if (!_shouldPoll) return;
      // Banner already visible — skip further probes until user refreshes.
      if (_showNewPostsBanner) return;
      unawaited(_checkForNewerPosts());
    });
  }

  void _stopNewerPoll() {
    _newerPollTimer?.cancel();
    _newerPollTimer = null;
  }

  @override
  void dispose() {
    _stopNewerPoll();
    _feedScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _postService.removeListener(_onChanged);
    _blocks.removeListener(_onChanged);
    NotificationInboxService.instance.removeListener(_onChanged);
    super.dispose();
  }

  /// Switch 인기/최신 and jump to the first post (top of feed).
  void _selectSort(PostSort sort) {
    setState(() => _sort = sort);
    void jumpTop() {
      if (!mounted || !_feedScrollController.hasClients) return;
      _feedScrollController.jumpTo(0);
    }

    // Jump after layout — list reorder can leave a stale pixel offset for one
    // frame, and a second frame covers late attach after ValueKey swap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      jumpTop();
      WidgetsBinding.instance.addPostFrameCallback((_) => jumpTop());
    });
  }

  /// Background probe only — never replaces the feed cache by itself.
  Future<void> _checkForNewerPosts() async {
    if (_checkingNewer || !_shouldPoll) return;
    if (_showNewPostsBanner) return;
    _checkingNewer = true;
    try {
      final newer = await _postsFirestore.hasNewerPostsThanCache();
      if (!mounted) return;
      if (newer) {
        setState(() => _showNewPostsBanner = true);
      }
    } finally {
      _checkingNewer = false;
    }
  }

  /// Banner tap: switch to 최신, refresh feed, scroll to top, dismiss banner.
  Future<void> _onNewPostsBannerTap() async {
    // Always land on latest feed — banner means "check new posts".
    if (_sort != PostSort.latest) {
      _selectSort(PostSort.latest);
    } else if (_feedScrollController.hasClients) {
      await _feedScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted) return;
    await _refreshPosts(force: true);
  }

  void _dismissNewPostsBanner() {
    if (!_showNewPostsBanner) return;
    setState(() => _showNewPostsBanner = false);
  }

  /// Fetch latest posts only — never touches scroll offset.
  /// Pull-to-refresh always passes [force] true so Firestore is source of truth.
  Future<void> _refreshPosts({bool force = false}) async {
    try {
      final shouldForce = force || _showNewPostsBanner;
      debugPrint(
        '[REFRESH_DEBUG] home _refreshPosts force=$shouldForce',
      );
      final posts = await _postsFirestore.fetchLatestPosts(
        forceRefresh: shouldForce,
      );
      for (final post in posts) {
        _postService.upsertRemotePost(post);
      }
      if (mounted) {
        setState(() => _showNewPostsBanner = false);
      }
      debugPrint('[REFRESH_DEBUG] UI updated');
      if (widget.isActive) _startNewerPoll();
    } catch (e) {
      debugPrint('홈 새로고침 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('글을 새로고침하지 못했어요.')),
      );
    }
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
    );
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  void _openPost(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(post: post),
      ),
    );
  }

  void _openTopic(String topic, {String? topicId}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TopicFeedScreen(
          topicName: topic,
          topicId: topicId,
        ),
      ),
    );
  }

  List<Post> _sorted(List<Post> posts) {
    final list = List<Post>.from(posts);
    switch (_sort) {
      case PostSort.popular:
        list.sort((a, b) {
          final byLikes = b.likeCount.compareTo(a.likeCount);
          if (byLikes != 0) return byLikes;
          final byComments = b.commentCount.compareTo(a.commentCount);
          if (byComments != 0) return byComments;
          return b.createdAt.compareTo(a.createdAt);
        });
      case PostSort.all:
      case PostSort.latest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  List<_FeedItem> _feedItems(List<Post> posts) {
    final items = <_FeedItem>[];
    for (var i = 0; i < posts.length; i++) {
      items.add(_FeedItem.post(posts[i]));
      if ((i + 1) % AdHelper.nativeAdInterval == 0) {
        items.add(
          _FeedItem.nativeAd(slot: i ~/ AdHelper.nativeAdInterval),
        );
      }
    }
    return items;
  }

  Widget _buildPostTile(Post post) {
    final mine = _postService.isMyPost(post.id, post: post);
    VoidCallback? openEdit;
    if (mine) {
      openEdit = () {
        _postService.upsertRemotePost(post);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WritePostScreen(editPostId: post.id),
          ),
        );
      };
    }

    return PostListItem(
      post: post,
      onTap: () => _openPost(post),
      onLike: () => togglePostLike(context, post: post),
      onMore: mine
          ? null
          : () {
              _postService.upsertRemotePost(post);
              PostMoreSheet.show(context, post: post);
            },
      onEdit: openEdit,
      onDelete: mine
          ? () {
              _postService.upsertRemotePost(post);
              PostMoreSheet.deleteWithConfirm(context, post);
            }
          : null,
      onEditPoll: mine && post.poll != null
          ? () {
              _postService.upsertRemotePost(post);
              EditPollSheet.show(context, post: post);
            }
          : null,
      onTopicTap: (topic) => _openTopic(topic, topicId: post.topicId),
      onVote: (optionId) => castPostVote(
        context,
        post: post,
        optionId: optionId,
      ),
    );
  }

  static const double _newPostsBannerHeight = 40;

  /// First item in the feed scroll — scrolls away with posts (not AppBar/overlay).
  Widget _buildNewPostsBanner(ColorScheme colors) {
    return SizedBox(
      height: _newPostsBannerHeight,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _onNewPostsBannerTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  '새 게시글이 등록됐어요.',
                  style: CafeinTypography.reaction(colors.onSurface),
                ),
              ),
            ),
            GestureDetector(
              onTap: _dismissNewPostsBanner,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 8, 8),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: colors.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Instagram-style pull: content displaces down; spinner lives in the gap.
  Widget _buildPullToRefreshFeed({required List<Widget> bodySlivers}) {
    final colors = Theme.of(context).colorScheme;
    return CustomScrollView(
      // Stable key — sort change jumps via [_selectSort], not remount (avoids
      // one-frame layout/size flicker between 인기 and 최신).
      key: const PageStorageKey<String>('home_feed'),
      controller: _feedScrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(
          refreshTriggerPullDistance: 100,
          refreshIndicatorExtent: 60,
          onRefresh: () => _refreshPosts(force: true),
          builder: CupertinoSliverRefreshControl.buildRefreshIndicator,
        ),
        // Banner is scroll content — never fixed over posts.
        if (_showNewPostsBanner)
          SliverToBoxAdapter(child: _buildNewPostsBanner(colors)),
        ...bodySlivers,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        // Root tab: keep title aligned with screen padding (theme titleSpacing is 0).
        titleSpacing: AppSpacing.screenH,
        actions: [
          if (AuthService.instance.canWriteContent)
            IconButton(
              onPressed: _openNotifications,
              tooltip: '알림',
              icon: Badge(
                isLabelVisible:
                    NotificationInboxService.instance.unreadCount > 0,
                label: Text(
                  NotificationInboxService.instance.unreadBadgeLabel,
                  style: const TextStyle(fontSize: 10),
                ),
                child: const Icon(Icons.notifications_none),
              ),
            ),
          IconButton(
            onPressed: _openSearch,
            icon: const Icon(Icons.search),
            tooltip: '검색',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                0,
                AppSpacing.screenH,
                8,
              ),
              child: Row(
                children: [
                  _SortTab(
                    label: '인기',
                    selected: _sort == PostSort.popular,
                    onTap: () => _selectSort(PostSort.popular),
                  ),
                  const SizedBox(width: 20),
                  _SortTab(
                    label: '최신',
                    selected: _sort == PostSort.latest,
                    onTap: () => _selectSort(PostSort.latest),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Post>>(
        stream: _postsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return _buildPullToRefreshFeed(
              bodySlivers: const [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            );
          }

          if (snapshot.hasError) {
            final message = snapshot.error is FirebaseException
                ? (snapshot.error! as FirebaseException).message
                : snapshot.error.toString();
            return _buildPullToRefreshFeed(
              bodySlivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.screenH),
                    child: Center(
                      child: Text(
                        '글을 불러오지 못했어요.\n$message',
                        textAlign: TextAlign.center,
                        style: CafeinTypography.commentBody(colors.muted),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          final posts = _sorted(
            _blocks.filterByAuthorId(
              // Prefer in-memory feed (initial load / soft updates) so
              // re-entry and likes/create do not wait on a new server read.
              // Remap through PostService so optimistic likes win immediately.
              [
                for (final p in (_postsFirestore.peekCachedFeedStale() ??
                    snapshot.data ??
                    const <Post>[]))
                  _postService.getById(p.id) ?? p,
              ],
              (p) => p.authorId,
            ),
          );

          if (posts.isEmpty) {
            return _buildPullToRefreshFeed(
              bodySlivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      '아직 게시글이 없어요.',
                      style: CafeinTypography.commentBody(colors.muted)
                          .copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            );
          }

          final items = _feedItems(posts);
          return _buildPullToRefreshFeed(
            bodySlivers: [
              SliverPadding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final itemIndex = index ~/ 2;
                      if (index.isOdd) {
                        final current = items[itemIndex];
                        final next = itemIndex + 1 < items.length
                            ? items[itemIndex + 1]
                            : null;
                        if (current.isNativeAd ||
                            (next != null && next.isNativeAd)) {
                          return const SizedBox.shrink();
                        }
                        return const Divider(
                          height: 0.5,
                          thickness: 0.5,
                          indent: AppSpacing.screenH,
                          endIndent: AppSpacing.screenH,
                        );
                      }
                      final item = items[itemIndex];
                      if (item.isNativeAd) {
                        return CafeinNativeAdCard(
                          key: _nativeAdKey(item.adSlot!),
                          debugSlot: item.adSlot,
                        );
                      }
                      return _buildPostTile(item.post!);
                    },
                    childCount: items.length * 2 - 1,
                    addAutomaticKeepAlives: true,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FeedItem {
  const _FeedItem._({this.post, this.adSlot})
      : assert(post != null || adSlot != null);

  factory _FeedItem.post(Post post) => _FeedItem._(post: post);

  factory _FeedItem.nativeAd({required int slot}) =>
      _FeedItem._(adSlot: slot);

  final Post? post;
  final int? adSlot;

  bool get isNativeAd => adSlot != null;
}

class _SortTab extends StatelessWidget {
  const _SortTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = CafeinTypography.sortTab(
      selected: selected,
      color: selected ? colors.onSurface : colors.muted,
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          // Lock to 인기(selected) line box so label metrics never shift.
          height: 18 * 1.2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(label, style: style),
          ),
        ),
      ),
    );
  }
}
