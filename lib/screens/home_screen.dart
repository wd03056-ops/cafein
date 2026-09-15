import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/post.dart';
import '../services/block_firestore_service.dart';
import '../services/like_helper.dart';
import '../services/poll_vote_helper.dart';
import '../services/post_service.dart';
import '../services/posts_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/post_list_item.dart';
import '../widgets/post_more_sheet.dart';
import 'post_detail_screen.dart';
import 'search_screen.dart';
import 'topic_feed_screen.dart';
import 'write_post_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _postService = PostService.instance;
  final _postsFirestore = PostsFirestoreService.instance;
  final _blocks = BlockFirestoreService.instance;
  late final Stream<List<Post>> _postsStream;
  PostSort _sort = PostSort.latest;

  @override
  void initState() {
    super.initState();
    _postsStream = _postsFirestore.watchPosts();
    _postService.addListener(_onChanged);
    _blocks.addListener(_onChanged);
    unawaited(_blocks.ensureLoaded());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _postService.removeListener(_onChanged);
    _blocks.removeListener(_onChanged);
    super.dispose();
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            onPressed: _openSearch,
            icon: const Icon(Icons.search),
            tooltip: '검색',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
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
                    label: '최신',
                    selected: _sort == PostSort.latest,
                    onTap: () => setState(() => _sort = PostSort.latest),
                  ),
                  const SizedBox(width: 20),
                  _SortTab(
                    label: '인기',
                    selected: _sort == PostSort.popular,
                    onTap: () => setState(() => _sort = PostSort.popular),
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
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final message = snapshot.error is FirebaseException
                ? (snapshot.error! as FirebaseException).message
                : snapshot.error.toString();
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenH),
                child: Text(
                  '글을 불러오지 못했어요.\n$message',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    height: 1.5,
                    color: colors.muted,
                  ),
                ),
              ),
            );
          }

          final posts = _sorted(
            _blocks.filterByAuthorId(
              snapshot.data ?? const [],
              (p) => p.authorId,
            ),
          );
          if (posts.isEmpty) {
            return Center(
              child: Text(
                '아직 게시글이 없어요.',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colors.muted,
                ),
              ),
            );
          }

          return ListView.separated(
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
                onTap: () => _openPost(post),
                onLike: () => togglePostLike(context, post: post),
                onMore: () {
                  _postService.upsertRemotePost(post);
                  PostMoreSheet.show(context, post: post);
                },
                onEdit: _postService.isMyPost(post.id, post: post)
                    ? () {
                        _postService.upsertRemotePost(post);
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                WritePostScreen(editPostId: post.id),
                          ),
                        );
                      }
                    : null,
                onTopicTap: (topic) =>
                    _openTopic(topic, topicId: post.topicId),
                onVote: (optionId) => castPostVote(
                  context,
                  post: post,
                  optionId: optionId,
                ),
              );
            },
          );
        },
      ),
    );
  }
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

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: colors.onSurface,
          ),
        ),
      ),
    );
  }
}
