import 'dart:async';

import 'package:flutter/material.dart';

import '../core/time_format.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/block_firestore_service.dart';
import '../services/comments_firestore_service.dart';
import '../services/like_helper.dart';
import '../services/poll_vote_helper.dart';
import '../services/post_service.dart';
import '../services/posts_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/comment_item.dart';
import '../widgets/comment_more_sheet.dart';
import '../widgets/no_underline_text_editing_controller.dart';
import '../widgets/poll_section.dart';
import '../widgets/post_more_sheet.dart';
import '../widgets/related_post_card.dart';
import '../widgets/topic_pill.dart';
import '../widgets/user_badge.dart';
import 'login_screen.dart';
import 'topic_feed_screen.dart';

/// Post detail — accepts full [post] from the list, or [postId] lookup.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    this.postId,
    this.post,
  }) : assert(
          postId != null || post != null,
          'postId or post is required',
        );

  final String? postId;

  /// Post payload from the feed (preferred when coming from ListView).
  final Post? post;

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

  late final Stream<List<Comment>> _commentsStream;
  late Post _seedPost;
  bool _submitting = false;
  List<Post> _similarPosts = const [];
  bool _similarLoaded = false;

  @override
  void initState() {
    super.initState();
    _seedPost = widget.post ??
        _postService.getById(widget.resolvedPostId) ??
        Post(
          id: widget.resolvedPostId,
          content: '',
          createdAt: DateTime.now(),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _postService.upsertRemotePost(_seedPost);
    });
    _commentsStream =
        _commentsFirestore.watchComments(widget.resolvedPostId);
    _postService.addListener(_refresh);
    BlockFirestoreService.instance.addListener(_refresh);
    unawaited(BlockFirestoreService.instance.ensureLoaded());
    _loadPostAndSimilar();
  }

  Future<void> _loadPostAndSimilar() async {
    try {
      final remote = await _postsFirestore.getPost(widget.resolvedPostId);
      if (remote != null && mounted) {
        _postService.upsertRemotePost(remote);
        setState(() => _seedPost = remote);
      }
    } catch (e) {
      debugPrint('게시글 조회 실패: $e');
    }

    final topicId =
        (_postService.getById(widget.resolvedPostId) ?? _seedPost)
            .topicId
            ?.trim();
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
        excludePostId: widget.resolvedPostId,
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

  Future<void> _submitComment() async {
    if (_submitting) return;
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final auth = AuthService.instance;
    if (!auth.canWriteContent) {
      final loggedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const LoginScreen()),
      );
      if (loggedIn != true || !mounted) return;
      if (!AuthService.instance.canWriteContent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('카카오 로그인과 프로필 설정을 완료해 주세요.')),
        );
        return;
      }
    }

    final authorId = AuthService.instance.kakaoUserId;
    final nickname = AuthService.instance.nickname;
    if (authorId == null || authorId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 후 댓글을 남길 수 있어요.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _commentsFirestore.addComment(
        postId: widget.resolvedPostId,
        content: text,
        authorId: authorId,
        authorNickname: nickname ?? '익명',
      );
      if (!mounted) return;
      _commentController.clear();
      _commentFocus.unfocus();
    } catch (e) {
      debugPrint('댓글 저장 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글을 저장하지 못했어요. 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
    final title = post.title?.trim();
    final hasTitle = title != null && title.isNotEmpty;
    final profileUrl = post.authorProfileImage?.trim();

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz),
            tooltip: '더보기',
            onPressed: () => PostMoreSheet.show(context, post: post),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Comment>>(
              stream: _commentsStream,
              builder: (context, snapshot) {
                final rawComments = snapshot.data ?? const <Comment>[];
                final comments = BlockFirestoreService.instance.filterByAuthorId(
                  rawComments,
                  (c) => c.authorId,
                );
                final loading = snapshot.connectionState ==
                        ConnectionState.waiting &&
                    !snapshot.hasData;

                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenH,
                        8,
                        AppSpacing.screenH,
                        0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _AuthorAvatar(
                            url: profileUrl,
                            nickname: post.author,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  post.authorNickname,
                                  style: TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                    color: colors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (post.cafeType != null &&
                                        post.cafeType!.isNotEmpty &&
                                        post.experience != null &&
                                        post.experience!.isNotEmpty)
                                      UserBadgeWidget(
                                        cafeType: post.cafeType!,
                                        experience: post.experience!,
                                      ),
                                    Text(
                                      formatRelativeTime(post.createdAt),
                                      style: TextStyle(
                                        fontFamily: 'Pretendard',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                        color: colors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
                    if (hasTitle)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.screenH,
                          post.topic != null ? 14 : 18,
                          AppSpacing.screenH,
                          0,
                        ),
                        child: Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 20,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.screenH,
                        hasTitle
                            ? 10
                            : (post.topic != null ? 12 : 18),
                        AppSpacing.screenH,
                        20,
                      ),
                      child: Text(
                        post.content,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 16,
                          height: 1.6,
                          fontWeight: FontWeight.w400,
                          color: colors.onSurface,
                        ),
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
                                    style: TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: colors.onSurface,
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
                                '${snapshot.hasData ? comments.length : post.commentCount}',
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: colors.onSurface,
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.onSurface,
                        ),
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
                    else if (snapshot.hasError)
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
                        (c) => CommentItem(
                          comment: c,
                          onMore: () => CommentMoreSheet.show(
                            context,
                            comment: c,
                          ),
                        ),
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
                );
              },
            ),
          ),
          const Divider(height: 0.5, thickness: 0.5),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      focusNode: _commentFocus,
                      enabled: !_submitting,
                      minLines: 1,
                      maxLines: 3,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.send,
                      spellCheckConfiguration:
                          const SpellCheckConfiguration.disabled(),
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: colors.onSurface,
                        decoration: TextDecoration.none,
                        decorationThickness: 0,
                      ),
                      cursorColor: colors.onSurface,
                      decoration: InputDecoration(
                        hintText: '댓글을 남겨보세요',
                        hintStyle: TextStyle(
                          fontFamily: 'Pretendard',
                          color: colors.muted,
                          decoration: TextDecoration.none,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: true,
                        fillColor: colors.fill,
                      ),
                      onSubmitted: (_) => _submitComment(),
                    ),
                  ),
                  IconButton(
                    onPressed: _submitting ? null : _submitComment,
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
                    tooltip: '등록',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({
    required this.url,
    required this.nickname,
  });

  final String? url;
  final String nickname;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasUrl = url != null && url!.isNotEmpty;

    return CircleAvatar(
      radius: 22,
      backgroundColor: colors.fill,
      backgroundImage: hasUrl ? NetworkImage(url!) : null,
      child: hasUrl
          ? null
          : Text(
              nickname.isNotEmpty ? nickname.characters.first : '?',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
    );
  }
}
