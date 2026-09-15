import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/topic.dart';
import '../services/block_firestore_service.dart';
import '../services/like_helper.dart';
import '../services/post_service.dart';
import '../services/poll_vote_helper.dart';
import '../services/posts_firestore_service.dart';
import '../services/topics_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/post_list_item.dart';
import 'post_detail_screen.dart';

/// Posts gathered under a topic (Firestore `topicId`).
class TopicFeedScreen extends StatefulWidget {
  const TopicFeedScreen({
    super.key,
    required this.topicName,
    this.topicId,
  });

  final String topicName;
  final String? topicId;

  @override
  State<TopicFeedScreen> createState() => _TopicFeedScreenState();
}

class _TopicFeedScreenState extends State<TopicFeedScreen> {
  final _postService = PostService.instance;
  final _postsFs = PostsFirestoreService.instance;
  final _topicsFs = TopicsFirestoreService.instance;

  PostSort _sort = PostSort.latest;
  bool _loading = true;
  String? _error;
  String? _resolvedTopicId;
  int _usageCount = 0;
  List<Post> _posts = const [];

  @override
  void initState() {
    super.initState();
    BlockFirestoreService.instance.addListener(_onBlocksChanged);
    BlockFirestoreService.instance.ensureLoaded();
    _load();
  }

  void _onBlocksChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BlockFirestoreService.instance.removeListener(_onBlocksChanged);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var topicId = widget.topicId?.trim();
      Topic? topic;

      if (topicId != null && topicId.isNotEmpty) {
        topic = await _topicsFs.getById(topicId);
      }

      topic ??= await _topicsFs.findByName(widget.topicName);
      topicId = topic?.id;

      final posts = topicId == null || topicId.isEmpty
          ? const <Post>[]
          : await _postsFs.fetchPostsByTopicId(topicId);

      if (!mounted) return;
      setState(() {
        _resolvedTopicId = topicId;
        _usageCount = topic?.usageCount ?? posts.length;
        _posts = posts;
        _loading = false;
      });
    } catch (e) {
      debugPrint('주제 피드 로드 실패: $e');
      if (!mounted) return;
      setState(() {
        _error = '주제 글을 불러오지 못했어요.';
        _loading = false;
      });
    }
  }

  List<Post> get _sortedPosts {
    final list = BlockFirestoreService.instance.filterByAuthorId(
      _posts,
      (p) => p.authorId,
    );
    switch (_sort) {
      case PostSort.popular:
        list.sort((a, b) {
          final byLikes = b.likeCount.compareTo(a.likeCount);
          if (byLikes != 0) return byLikes;
          return b.createdAt.compareTo(a.createdAt);
        });
      case PostSort.all:
      case PostSort.latest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  void _openTopic(String topic, {String? topicId}) {
    if (topic == widget.topicName &&
        (topicId == null || topicId == _resolvedTopicId)) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TopicFeedScreen(
          topicName: topic,
          topicId: topicId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posts = _sortedPosts;
    final colors = Theme.of(context).colorScheme;
    final countLabel = _usageCount > 0 ? _usageCount : posts.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topicName),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              8,
              AppSpacing.screenH,
              12,
            ),
            child: Text(
              '게시글 $countLabel개',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: colors.muted,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              0,
              AppSpacing.screenH,
              8,
            ),
            child: Row(
              children: [
                _SortChip(
                  label: '최신',
                  selected: _sort == PostSort.latest,
                  onTap: () => setState(() => _sort = PostSort.latest),
                ),
                const SizedBox(width: 16),
                _SortChip(
                  label: '인기',
                  selected: _sort == PostSort.popular,
                  onTap: () => setState(() => _sort = PostSort.popular),
                ),
              ],
            ),
          ),
          const Divider(height: 0.5, thickness: 0.5),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            color: colors.muted,
                          ),
                        ),
                      )
                    : posts.isEmpty
                        ? Center(
                            child: Text(
                              '아직 이 주제의 이야기가 없어요.',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                color: colors.muted,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(top: 8),
                            itemCount: posts.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 0.5,
                              thickness: 0.5,
                              indent: AppSpacing.screenH,
                              endIndent: AppSpacing.screenH,
                            ),
                            itemBuilder: (context, index) {
                              final post = posts[index];
                              return PostListItem(
                                post: post,
                                onTap: () {
                                  _postService.upsertRemotePost(post);
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          PostDetailScreen(post: post),
                                    ),
                                  );
                                },
                                onLike: () =>
                                    togglePostLike(context, post: post),
                                onTopicTap: (topic) => _openTopic(
                                  topic,
                                  topicId: post.topicId,
                                ),
                                onVote: (optionId) => castPostVote(
                                  context,
                                  post: post,
                                  optionId: optionId,
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
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

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: colors.onSurface,
        ),
      ),
    );
  }
}
