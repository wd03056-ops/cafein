import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/post_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/post_list_item.dart';
import '../widgets/post_more_sheet.dart';
import 'post_detail_screen.dart';
import 'topic_feed_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _postService = PostService.instance;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery?.trim() ?? '';
    _controller.text = _query;
    _postService.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_query.isEmpty) _focusNode.requestFocus();
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _postService.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _query.isEmpty ? const [] : _postService.search(_query);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          style: TextStyle(color: colors.onSurface),
          cursorColor: colors.onSurface,
          decoration: InputDecoration(
            hintText: AppConstants.searchHint,
            hintStyle: TextStyle(color: colors.mutedSoft),
            border: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          ),
          onChanged: (value) => setState(() => _query = value.trim()),
          onSubmitted: (value) => setState(() => _query = value.trim()),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
                _focusNode.requestFocus();
              },
            ),
        ],
      ),
      body: _query.isEmpty
          ? Center(
              child: Text(
                '키워드로 검색해보세요\n예) 마감, 주휴수당, 진상',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.muted,
                    ),
              ),
            )
          : results.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      AppConstants.emptySearchMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: colors.onSurface,
                          ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(top: 8),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 0.5,
                    thickness: 0.5,
                    indent: AppSpacing.screenH,
                    endIndent: AppSpacing.screenH,
                  ),
                  itemBuilder: (context, index) {
                    final post = results[index];
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
                      onMore: () => PostMoreSheet.show(context, post: post),
                      onTopicTap: (topic) {
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
    );
  }
}
