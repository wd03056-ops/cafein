import 'dart:async';

import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/block_firestore_service.dart';
import '../services/comment_like_helper.dart';
import '../services/comments_firestore_service.dart';
import '../services/like_helper.dart';
import '../services/poll_vote_helper.dart';
import '../services/post_service.dart';
import '../services/posts_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/comment_item.dart';
import '../widgets/comment_more_sheet.dart';
import '../widgets/dismiss_keyboard_on_tap.dart';
import '../widgets/no_underline_text_editing_controller.dart';
import '../widgets/poll_section.dart';
import '../widgets/post_author_meta.dart';
import '../widgets/post_more_sheet.dart';
import '../widgets/related_post_card.dart';
import '../widgets/topic_pill.dart';
import 'auth_required_screen.dart';
import 'topic_feed_screen.dart';
import 'write_post_screen.dart';

/// Post detail — accepts full [post] from the list, or [postId] lookup.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    this.postId,
    this.post,
    this.forceRefreshOnOpen = false,
  }) : assert(
          postId != null || post != null,
          'postId or post is required',
        );

  final String? postId;

  /// Post payload from the feed (preferred when coming from ListView).
  final Post? post;

  /// When true (e.g. notification tap), force-refresh this post + comments
  /// from Firestore once on open. Does not reload the home feed.
  final bool forceRefreshOnOpen;

  String get resolvedPostId => postId ?? post!.id;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _postService = PostService.instance;
  final _postsFirestore = PostsFirestoreService.instance;
  final _commentsFirestore = CommentsFirestoreService.instance;
  final _commentController = NoUnderlineTextEditingController();
  final _commentFocus = FocusNode();

  late Post _seedPost;
  bool _submitting = false;
  List<Post> _similarPosts = const [];
  bool _similarLoaded = false;

  List<Comment> _comments = const [];
  bool _commentsLoading = true;
  Object? _commentsError;
  int _commentsLoadGen = 0;

  /// When non-null, bottom composer is editing this comment (same UI as write).
  String? _editingCommentId;
  String? _editingOriginalContent;

  @override
  void initState() {
    super.initState();
    _seedPost = widget.post ??
        _postService.getById(widget.resolvedPostId) ??
        _postsFirestore.peekCachedPostStale(widget.resolvedPostId) ??
        Post(
          id: widget.resolvedPostId,
          content: '',
          createdAt: DateTime.now(),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Never overwrite a fresher PostService entry (e.g. optimistic like
      // that landed before this callback). Only seed when missing.
      if (_postService.getById(widget.resolvedPostId) == null) {
        _postService.upsertRemotePost(_seedPost);
      }
    });
    _postService.addListener(_refresh);
    BlockFirestoreService.instance.addListener(_refresh);
    unawaited(BlockFirestoreService.instance.ensureLoaded());
    unawaited(_loadPostAndSimilar());
    // Notification entry: always refresh comments. Otherwise force when the
    // feed commentCount is ahead of the local comment cache.
    final forceComments = widget.forceRefreshOnOpen;
    final cachedComments = forceComments
        ? null
        : _commentsFirestore.peekCachedComments(
            widget.resolvedPostId,
            allowStale: true,
          );
    final expectedCount =
        (_postService.getById(widget.resolvedPostId) ?? _seedPost)
            .commentCount;
    final needForceComments = forceComments ||
        cachedComments == null ||
        cachedComments.length < expectedCount;
    unawaited(_loadComments(forceRefresh: needForceComments));
  }

  Future<void> _loadPostAndSimilar() async {
    final id = widget.resolvedPostId;

    if (widget.forceRefreshOnOpen) {
      // Targeted post refresh only — used by notification / FCM open.
      try {
        final remote = await _postsFirestore.getPost(id, forceRefresh: true);
        if (remote != null && mounted) {
          _postService.upsertRemotePost(remote);
          setState(() => _seedPost = remote);
          debugPrint(
            '[NOTIFICATION_OPEN] post forceRefresh '
            'likeCount=${remote.likeCount} commentCount=${remote.commentCount}',
          );
        }
      } catch (e) {
        debugPrint('알림 진입 게시글 새로고침 실패: $e');
      }
    } else {
      // Prefer feed/list payload or memory cache — avoid posts/{id} get.
      final fromWidget = widget.post;
      final fromService = _postService.getById(id);
      final fromMemory = _postsFirestore.peekCachedPost(id);
      final hasUsableLocal = (fromWidget != null &&
              fromWidget.content.trim().isNotEmpty) ||
          (fromService != null && fromService.content.trim().isNotEmpty) ||
          fromMemory != null;

      if (fromWidget != null) {
        _postsFirestore.rememberPost(fromWidget);
      }

      if (!hasUsableLocal) {
        try {
          final remote = await _postsFirestore.getPost(id);
          if (remote != null && mounted) {
            _postService.upsertRemotePost(remote);
            setState(() => _seedPost = remote);
          }
        } catch (e) {
          debugPrint('게시글 조회 실패: $e');
        }
      }
    }

    final topicId =
        (_postService.getById(id) ?? _seedPost).topicId?.trim();
    if (topicId == null || topicId.isEmpty) {
      if (mounted) {
        setState(() {
          _similarPosts = const [];
          _similarLoaded = true;
        });
      }
      return;
    }

    try {
      final similar = await _postsFirestore.fetchSimilarPosts(
        topicId: topicId,
        excludePostId: id,
        limit: 5,
      );
      if (!mounted) return;
      setState(() {
        _similarPosts = similar;
        _similarLoaded = true;
      });
    } catch (e) {
      debugPrint('비슷한 글 조회 실패: $e');
      if (!mounted) return;
      setState(() {
        _similarPosts = const [];
        _similarLoaded = true;
      });
    }
  }

  Future<void> _onPullRefresh() async {
    debugPrint('[REFRESH_DEBUG] detail refresh start');
    debugPrint('[REFRESH_DEBUG] forceRefresh=true');
    debugPrint('[POLL_REFRESH_DEBUG] refresh start');
    final id = widget.resolvedPostId;
    debugPrint('[POLL_REFRESH_DEBUG] postId=$id');
    try {
      final remote = await _postsFirestore.getPost(id, forceRefresh: true);
      if (remote != null && mounted) {
        _postService.upsertRemotePost(remote);
        setState(() => _seedPost = remote);
        debugPrint(
          '[REFRESH_DEBUG] detail post likeCount=${remote.likeCount} '
          'commentCount=${remote.commentCount}',
        );
        final poll = remote.poll;
        if (poll != null) {
          for (final o in poll.options) {
            debugPrint(
              '[POLL_REFRESH_DEBUG] optionId=${o.id} '
              'firestoreVoteCount=${o.votes}',
            );
          }
          debugPrint('[POLL_REFRESH_DEBUG] UI poll updated');
        }
      }
    } catch (e) {
      debugPrint('상세 게시글 새로고침 실패: $e');
    }
    await _loadComments(forceRefresh: true);
    if (mounted) {
      debugPrint('[REFRESH_DEBUG] UI updated');
      debugPrint('[REFRESH_DEBUG] refresh complete');
      debugPrint('[POLL_REFRESH_DEBUG] refresh complete');
    }
  }

  Future<void> _loadComments({bool forceRefresh = false}) async {
    final id = widget.resolvedPostId;
    final gen = ++_commentsLoadGen;
    final stale = _commentsFirestore.peekCachedComments(id, allowStale: true);
    if (!forceRefresh && stale != null && mounted) {
      setState(() {
        // Keep any in-flight optimistic rows the cache copy may lack.
        final pending = _comments
            .where((c) => c.id.startsWith('local_'))
            .where((c) => !stale.any((s) => s.id == c.id))
            .toList();
        _comments = CommentsFirestoreService.sortedNewestFirst([
          ...stale,
          ...pending,
        ]);
        _commentsLoading = false;
        _commentsError = null;
      });
    } else if (mounted && _comments.isEmpty) {
      setState(() {
        _commentsLoading = true;
        _commentsError = null;
      });
    }

    try {
      final comments = await _commentsFirestore.fetchComments(
        id,
        forceRefresh: forceRefresh,
      );
      if (!mounted || gen != _commentsLoadGen) {
        debugPrint(
          '[COMMENT_DEBUG] load discarded gen=$gen current=$_commentsLoadGen',
        );
        return;
      }
      setState(() {
        // Only keep in-flight optimistic rows (write not confirmed yet).
        final localOnly = _comments
            .where((c) => c.id.startsWith('local_'))
            .toList();
        _comments = CommentsFirestoreService.sortedNewestFirst([
          ...comments,
          ...localOnly.where(
            (local) => !comments.any((c) => c.id == local.id),
          ),
        ]);
        _commentsLoading = false;
        _commentsError = null;
      });
      debugPrint(
        '[COMMENT_DEBUG] load applied count=${_comments.length}',
      );
      debugPrint('[REFRESH_DEBUG] comments count=${_comments.length}');
    } catch (e) {
      debugPrint('댓글 로드 실패: $e');
      if (!mounted || gen != _commentsLoadGen) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = e;
      });
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocus.dispose();
    _postService.removeListener(_refresh);
    BlockFirestoreService.instance.removeListener(_refresh);
    super.dispose();
  }

  Post get _post {
    return _postService.getById(widget.resolvedPostId) ?? _seedPost;
  }

  void _bumpLocalCommentCount(int delta) {
    final post = _post;
    final next = (post.commentCount + delta).clamp(0, 1 << 30);
    final updated = post.copyWith(remoteCommentCount: next);
    _postService.upsertRemotePost(updated);
    _seedPost = updated;
  }

  Future<void> _submitComment() async {
    if (_submitting) return;
    final text = _commentController.text.trim();
    debugPrint('[COMMENT_DEBUG] submit start');
    debugPrint('[COMMENT_DEBUG] content=$text');
    if (text.isEmpty) return;

    final editingId = _editingCommentId?.trim();
    if (editingId != null && editingId.isNotEmpty) {
      await _submitCommentEdit(editingId, text);
      return;
    }

    final auth = AuthService.instance;
    if (!auth.canWriteContent) {
      final ready = await AuthRequiredScreen.ensureWriter(context);
      if (!ready || !mounted) return;
      if (!AuthService.instance.canWriteContent) return;
    }

    final authorId = AuthService.instance.kakaoUserId;
    final nickname = AuthService.instance.nickname;
    debugPrint('[COMMENT_DEBUG] postId=${widget.resolvedPostId}');
    debugPrint('[COMMENT_DEBUG] userId=$authorId');
    if (authorId == null || authorId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이나 회원가입 후 댓글을 남길 수 있어요.')),
      );
      return;
    }

    // Invalidate any in-flight one-shot comment fetch so it cannot
    // overwrite the optimistic append with a stale list.
    _commentsLoadGen++;

    final tempId =
        'local_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Comment(
      id: tempId,
      postId: widget.resolvedPostId,
      content: text,
      createdAt: DateTime.now(),
      author: nickname ?? '익명',
      authorId: authorId,
      experience: AuthService.instance.experience,
      cafeType: AuthService.instance.cafeType,
      likeCount: 0,
      likedByMe: false,
    );

    debugPrint('[COMMENT_DEBUG] local UI insert tempId=$tempId');
    setState(() {
      _submitting = true;
      _comments = CommentsFirestoreService.sortedNewestFirst([
        optimistic,
        ..._comments,
      ]);
      _commentController.clear();
    });
    debugPrint(
      '[COMMENT_DEBUG] comment list count=${_comments.length}',
    );
    _commentsFirestore.appendCachedComment(widget.resolvedPostId, optimistic);
    _bumpLocalCommentCount(1);
    debugPrint('[COMMENT_DEBUG] commentCount update');
    _commentFocus.unfocus();

    try {
      debugPrint('[COMMENT_DEBUG] firestore write start');
      final created = await _commentsFirestore.addComment(
        postId: widget.resolvedPostId,
        content: text,
        authorId: authorId,
        authorNickname: nickname ?? '익명',
        experience: AuthService.instance.experience,
        cafeType: AuthService.instance.cafeType,
      );
      debugPrint(
        '[COMMENT_DEBUG] firestore write success commentId=${created.id}',
      );
      if (!mounted) return;
      setState(() {
        _comments = CommentsFirestoreService.sortedNewestFirst([
          for (final c in _comments) c.id == tempId ? created : c,
        ]);
      });
      _commentsFirestore.removeCachedComment(widget.resolvedPostId, tempId);
      _commentsFirestore.appendCachedComment(widget.resolvedPostId, created);
      debugPrint(
        '[COMMENT_DEBUG] comment list count after replace=${_comments.length}',
      );
    } catch (e) {
      debugPrint('[COMMENT_DEBUG] firestore write failed: $e');
      debugPrint('댓글 저장 실패: $e');
      if (!mounted) return;
      setState(() {
        _comments = _comments.where((c) => c.id != tempId).toList();
      });
      _commentsFirestore.removeCachedComment(widget.resolvedPostId, tempId);
      _bumpLocalCommentCount(-1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글을 저장하지 못했어요. 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _startEditComment(Comment comment) {
    final id = comment.id.trim();
    if (id.isEmpty || id.startsWith('local_')) return;

    setState(() {
      _editingCommentId = id;
      _editingOriginalContent = comment.content;
      _commentController.text = comment.content;
      _commentController.selection = TextSelection.collapsed(
        offset: _commentController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _commentFocus.requestFocus();
    });
  }

  void _cancelEditComment() {
    if (_editingCommentId == null) return;
    setState(() {
      _editingCommentId = null;
      _editingOriginalContent = null;
      _commentController.clear();
    });
    _commentFocus.unfocus();
  }

  Future<void> _submitCommentEdit(String commentId, String text) async {
    if (_submitting) return;
    final original = (_editingOriginalContent ?? '').trim();
    if (text == original) {
      _cancelEditComment();
      return;
    }

    Comment? previous;
    for (final c in _comments) {
      if (c.id == commentId) {
        previous = c;
        break;
      }
    }
    if (previous == null) {
      _cancelEditComment();
      return;
    }

    final optimistic = previous.copyWith(content: text);
    setState(() {
      _submitting = true;
      _comments = [
        for (final c in _comments) c.id == commentId ? optimistic : c,
      ];
    });
    _commentsFirestore.patchCachedComment(widget.resolvedPostId, optimistic);

    try {
      final updated = await _commentsFirestore.updateComment(
        postId: widget.resolvedPostId,
        commentId: commentId,
        content: text,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _editingCommentId = null;
        _editingOriginalContent = null;
        _commentController.clear();
        _comments = [
          for (final c in _comments) c.id == updated.id ? updated : c,
        ];
      });
      _commentsFirestore.patchCachedComment(widget.resolvedPostId, updated);
      _commentFocus.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글을 수정했어요.')),
      );
    } catch (e) {
      debugPrint('댓글 수정 실패: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _comments = [
          for (final c in _comments) c.id == commentId ? previous! : c,
        ];
        // Keep edit mode + controller text so the user can retry.
        _commentController.text = text;
        _commentController.selection = TextSelection.collapsed(
          offset: _commentController.text.length,
        );
      });
      _commentsFirestore.patchCachedComment(widget.resolvedPostId, previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글을 수정할 수 없어요.')),
      );
    }
  }

  void _onCommentDeleted(String commentId) {
    if (_editingCommentId == commentId) {
      _cancelEditComment();
    }
    setState(() {
      _comments = _comments.where((c) => c.id != commentId).toList();
    });
    _bumpLocalCommentCount(-1);
  }

  Future<void> _onCommentLike(Comment comment) async {
    await toggleCommentLikeOptimistic(
      context,
      comment: comment,
      onLocalUpdate: (updated) {
        if (!mounted) return;
        setState(() {
          _comments = [
            for (final c in _comments) c.id == updated.id ? updated : c,
          ];
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final blocks = BlockFirestoreService.instance;
    final related = blocks.filterByAuthorId(
      _similarLoaded ? _similarPosts : const <Post>[],
      (p) => p.authorId,
    );
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (_postService.isMyPost(post.id, post: post)) ...[
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WritePostScreen(editPostId: post.id),
                  ),
                );
              },
              child: Text('수정', style: CafeinTypography.button()),
            ),
            TextButton(
              onPressed: () async {
                final deleted =
                    await PostMoreSheet.deleteWithConfirm(context, post);
                if (deleted &&
                    context.mounted &&
                    Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              child: Text(
                '삭제',
                style: CafeinTypography.button(colors.error),
              ),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.more_horiz),
              tooltip: '더보기',
              onPressed: () => PostMoreSheet.show(context, post: post),
            ),
        ],
      ),
      body: DismissKeyboardOnTap(
        child: Column(
        children: [
          Expanded(
            child: Builder(
              builder: (context) {
                final comments = BlockFirestoreService.instance.filterByAuthorId(
                  _comments,
                  (c) => c.authorId,
                );
                final loading = _commentsLoading && _comments.isEmpty;

                return RefreshIndicator(
                  onRefresh: _onPullRefresh,
                  child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenH,
                        8,
                        AppSpacing.screenH,
                        0,
                      ),
                      child: PostAuthorMeta(post: post),
                    ),
                    if (post.topic != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screenH,
                          14,
                          AppSpacing.screenH,
                          0,
                        ),
                        child: TopicPill(
                          topic: post.topic!,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => TopicFeedScreen(
                                  topicName: post.topic!,
                                  topicId: post.topicId,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.screenH,
                        post.topic != null ? 12 : 18,
                        AppSpacing.screenH,
                        // ~24px before poll so body and poll question don't merge.
                        post.poll != null ? AppSpacing.xl : 20,
                      ),
                      child: Text(
                        post.content,
                        style: CafeinTypography.postBody(colors.onSurface),
                      ),
                    ),
                    if (post.poll != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screenH,
                          0,
                          AppSpacing.screenH,
                          12,
                        ),
                        child: PollSection(
                          poll: post.poll!,
                          onVote: (optionId) => castPostVote(
                            context,
                            post: post,
                            optionId: optionId,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenH,
                        0,
                        AppSpacing.screenH,
                        12,
                      ),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () => togglePostLike(context, post: post),
                            splashFactory: NoSplash.splashFactory,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    post.likedByMe
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 20,
                                    color: post.likedByMe
                                        ? colors.error
                                        : colors.onSurface,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${post.likeCount}',
                                    style: CafeinTypography.reaction(
                                      post.likedByMe
                                          ? colors.error
                                          : colors.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 20,
                                color: colors.onSurface,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${comments.isNotEmpty ? comments.length : post.commentCount}',
                                style: CafeinTypography.reaction(
                                  colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 0.5, thickness: 0.5),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenH,
                        16,
                        AppSpacing.screenH,
                        4,
                      ),
                      child: Text(
                        '댓글 ${comments.length}',
                        style: CafeinTypography.nickname(colors.onSurface),
                      ),
                    ),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else if (_commentsError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screenH,
                          12,
                          AppSpacing.screenH,
                          16,
                        ),
                        child: Text(
                          '댓글을 불러오지 못했어요.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.muted,
                          ),
                        ),
                      )
                    else if (comments.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screenH,
                          12,
                          AppSpacing.screenH,
                          16,
                        ),
                        child: Text(
                          '아직 댓글이 없어요. 첫 번째로 이야기해보세요.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.muted,
                          ),
                        ),
                      )
                    else
                      ...comments.map(
                        (c) {
                          final myId =
                              AuthService.instance.kakaoUserId?.trim() ?? '';
                          final authorId = c.authorId?.trim() ?? '';
                          final mine = myId.isNotEmpty &&
                              authorId.isNotEmpty &&
                              myId == authorId;
                          return CommentItem(
                            comment: c,
                            onMore: mine
                                ? null
                                : () => CommentMoreSheet.show(
                                      context,
                                      comment: c,
                                      onDeleted: () =>
                                          _onCommentDeleted(c.id),
                                    ),
                            onEdit: mine
                                ? () => _startEditComment(c)
                                : null,
                            onDelete: mine
                                ? () => CommentMoreSheet.deleteWithConfirm(
                                      context,
                                      comment: c,
                                      onDeleted: () =>
                                          _onCommentDeleted(c.id),
                                    )
                                : null,
                            onLike: () => _onCommentLike(c),
                          );
                        },
                      ),
                    if (related.isNotEmpty) ...[
                      const Divider(height: 0.5, thickness: 0.5),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screenH,
                          16,
                          AppSpacing.screenH,
                          12,
                        ),
                        child: Text(
                          '비슷한 글',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 168,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.screenH,
                            0,
                            AppSpacing.screenH,
                            8,
                          ),
                          itemCount: related.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final r = related[index];
                            return RelatedPostCard(
                              post: r,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        PostDetailScreen(post: r),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                );
              },
            ),
          ),
          const Divider(height: 0.5, thickness: 0.5),
          if (_editingCommentId != null)
            Material(
              color: colors.fill,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '댓글 수정 중',
                        style: CafeinTypography.metadata(colors.muted),
                      ),
                    ),
                    TextButton(
                      onPressed: _submitting ? null : _cancelEditComment,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        textStyle: CafeinTypography.button(),
                      ),
                      child: const Text('취소'),
                    ),
                  ],
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Builder(
                builder: (context) {
                  final loggedIn = AuthService.instance.canWriteContent;
                  final canSubmit = loggedIn && !_submitting;
                  final editing = _editingCommentId != null;
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          focusNode: _commentFocus,
                          enabled: !_submitting,
                          readOnly: !loggedIn,
                          enableInteractiveSelection: loggedIn,
                          minLines: 1,
                          maxLines: 3,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.send,
                          spellCheckConfiguration:
                              const SpellCheckConfiguration.disabled(),
                          style: CafeinTypography.commentBody(colors.onSurface)
                              .copyWith(
                            decoration: TextDecoration.none,
                            decorationThickness: 0,
                          ),
                          cursorColor: colors.onSurface,
                          decoration: InputDecoration(
                            hintText: loggedIn
                                ? (editing ? '댓글을 수정하세요' : '댓글을 남겨보세요')
                                : '로그인/회원가입을 해주셔야 가능합니다.',
                            hintStyle: CafeinTypography.commentBody(colors.muted)
                                .copyWith(
                              fontSize: loggedIn ? 15 : 13,
                              decoration: TextDecoration.none,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: true,
                            fillColor: colors.fill,
                          ),
                          onTap: loggedIn
                              ? null
                              : () async {
                                  _commentFocus.unfocus();
                                  final ready =
                                      await AuthRequiredScreen.ensureWriter(
                                    context,
                                  );
                                  if (ready && mounted) setState(() {});
                                },
                          onSubmitted:
                              canSubmit ? (_) => _submitComment() : null,
                        ),
                      ),
                      IconButton(
                        onPressed: _submitting
                            ? null
                            : () async {
                                if (!loggedIn) {
                                  final ready =
                                      await AuthRequiredScreen.ensureWriter(
                                    context,
                                  );
                                  if (ready && mounted) setState(() {});
                                  return;
                                }
                                await _submitComment();
                              },
                        icon: _submitting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.onSurface,
                                ),
                              )
                            : const Icon(Icons.arrow_upward),
                        tooltip: !loggedIn
                            ? '로그인 필요'
                            : (editing ? '수정 저장' : '등록'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
