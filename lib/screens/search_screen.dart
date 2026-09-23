import 'dart:async';

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
import '../theme/app_typography.dart';
import '../widgets/post_list_item.dart';
import '../widgets/post_more_sheet.dart';
import 'post_detail_screen.dart';
import 'topic_feed_screen.dart';
import 'write_post_screen.dart';

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
  final _postsFirestore = PostsFirestoreService.instance;

  String _query = '';
  List<Post> _results = const [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery?.trim() ?? '';
    _controller.text = _query;
    _postService.addListener(_onLocalCacheChanged);
    BlockFirestoreService.instance.addListener(_onLocalCacheChanged);
    BlockFirestoreService.instance.ensureLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_query.isEmpty) {
        _focusNode.requestFocus();
      } else {
        _runSearch(_query);
      }
    });
  }

  void _onLocalCacheChanged() {
    if (!mounted || _results.isEmpty) return;
    setState(() {
      _results = [
        for (final p in _results) _postService.getById(p.id) ?? p,
      ];
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _postService.removeListener(_onLocalCacheChanged);
    BlockFirestoreService.instance.removeListener(_onLocalCacheChanged);
    super.dispose();
  }

  void _setQuery(String value, {bool immediate = false}) {
    final next = value.trim();
    setState(() {
      _query = next;
      _error = null;
      if (next.isEmpty) {
        _results = const [];
        _loading = false;
      }
    });
    _debounce?.cancel();
    if (next.isEmpty) {
      _searchGeneration++;
      return;
    }
    if (immediate) {
      _runSearch(next);
    } else {
      _debounce = Timer(const Duration(milliseconds: 350), () {
        _runSearch(next);
      });
    }
  }

  Future<void> _runSearch(String rawQuery) async {
    final q = rawQuery.trim();
    if (q.isEmpty) return;
    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _postsFirestore.searchPosts(q);
      if (!mounted || generation != _searchGeneration) return;
      final filtered = BlockFirestoreService.instance.filterByAuthorId(
        raw,
        (p) => p.authorId,
      );
      final merged = [
        for (final p in filtered) _postService.getById(p.id) ?? p,
      ];
      setState(() {
        _results = merged;
        _loading = false;
      });
    } catch (e) {
      debugPrint('검색 실패: $e');
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loading = false;
        _error = '검색에 실패했어요. 잠시 후 다시 시도해 주세요.';
        _results = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          style: CafeinTypography.postBody(colors.onSurface),
          cursorColor: colors.onSurface,
          decoration: InputDecoration(
            hintText: AppConstants.searchHint,
            hintStyle: CafeinTypography.metadata(colors.mutedSoft),
            border: InputBorder.none,
            filled: false,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          ),
          onChanged: _setQuery,
          onSubmitted: (value) => _setQuery(value, immediate: true),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _setQuery('');
                _focusNode.requestFocus();
              },
            ),
        ],
      ),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(ColorScheme colors) {
    if (_query.isEmpty) {
      return Center(
        child: Text(
          '키워드로 검색해보세요\n예) 마감, 주휴수당, 진상',
          textAlign: TextAlign.center,
          style: CafeinTypography.commentBody(colors.muted),
        ),
      );
    }

    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: CafeinTypography.postBody(colors.onSurface),
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppConstants.emptySearchMessage,
            textAlign: TextAlign.center,
            style: CafeinTypography.postBody(colors.onSurface),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(
        height: 0.5,
        thickness: 0.5,
        indent: AppSpacing.screenH,
        endIndent: AppSpacing.screenH,
      ),
      itemBuilder: (context, index) {
        final post = _results[index];
        final mine = PostService.instance.isMyPost(post.id, post: post);
        return PostListItem(
          post: post,
          onTap: () {
            _postService.upsertRemotePost(post);
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PostDetailScreen(post: post),
              ),
            );
          },
          onLike: () => togglePostLike(context, post: post),
          onMore: mine
              ? null
              : () {
                  _postService.upsertRemotePost(post);
                  PostMoreSheet.show(context, post: post);
                },
          onEdit: mine
              ? () {
                  _postService.upsertRemotePost(post);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WritePostScreen(editPostId: post.id),
                    ),
                  );
                }
              : null,
          onDelete: mine
              ? () {
                  _postService.upsertRemotePost(post);
                  PostMoreSheet.deleteWithConfirm(context, post);
                }
              : null,
          onTopicTap: (topic) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TopicFeedScreen(
                  topicName: topic,
                  topicId: post.topicId,
                ),
              ),
            );
          },
          onVote: (optionId) => castPostVote(
            context,
            post: post,
            optionId: optionId,
          ),
        );
      },
    );
  }
}
