import 'package:flutter/material.dart';

import '../models/post.dart';
import '../services/post_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/post_list_item.dart';
import 'post_detail_screen.dart';

/// Posts gathered under a user-created topic.
class TopicFeedScreen extends StatefulWidget {
  const TopicFeedScreen({super.key, required this.topicName});

  final String topicName;

  @override
  State<TopicFeedScreen> createState() => _TopicFeedScreenState();
}

class _TopicFeedScreenState extends State<TopicFeedScreen> {
  final _postService = PostService.instance;
  PostSort _sort = PostSort.popular;

  @override
  void initState() {
    super.initState();
    _postService.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _postService.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posts = _postService.postsByTopic(widget.topicName, sort: _sort);
    final count = _postService.postCountForTopic(widget.topicName);
    final colors = Theme.of(context).colorScheme;

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
              '$count개의 이야기',
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
                  label: '인기',
                  selected: _sort == PostSort.popular,
                  onTap: () => setState(() => _sort = PostSort.popular),
                ),
                const SizedBox(width: 16),
                _SortChip(
                  label: '최신',
                  selected: _sort == PostSort.latest,
                  onTap: () => setState(() => _sort = PostSort.latest),
                ),
              ],
            ),
          ),
          const Divider(height: 0.5, thickness: 0.5),
          Expanded(
            child: posts.isEmpty
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
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PostDetailScreen(post: post),
                            ),
                          );
                        },
                        onLike: () => _postService.toggleLike(post.id),
                        onTopicTap: (topic) {
                          if (topic == widget.topicName) return;
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TopicFeedScreen(topicName: topic),
                            ),
                          );
                        },
                        onVote: (optionId) =>
                            _postService.vote(post.id, optionId),
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
