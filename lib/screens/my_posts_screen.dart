import 'package:flutter/material.dart';

import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/poll_vote_helper.dart';
import '../services/post_service.dart';
import '../services/posts_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/cafein_back_app_bar.dart';
import '../widgets/edit_poll_sheet.dart';
import '../widgets/post_list_item.dart';
import '../widgets/post_more_sheet.dart';
import 'login_screen.dart';
import 'post_detail_screen.dart';
import 'write_post_screen.dart';

/// List of posts written by the current logged-in user (Firestore).
/// Uses [PostsFirestoreService.fetchPostsByAuthor] memory TTL cache so
/// re-opening within ~5 minutes does not re-query Firestore.
class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  final _postService = PostService.instance;
  final _postsFirestore = PostsFirestoreService.instance;

  List<Post> _posts = const [];
  bool _loading = true;
  Object? _error;
  String? _loadedForUid;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChanged);
    _load();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final uid = AuthService.instance.kakaoUserId?.trim();
    if (uid != _loadedForUid) {
      _load(forceRefresh: true);
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final auth = AuthService.instance;
    final uid = auth.kakaoUserId?.trim();
    if (!auth.isLoggedIn || uid == null || uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _posts = const [];
        _loading = false;
        _error = null;
        _loadedForUid = null;
      });
      return;
    }

    setState(() {
      _loading = _posts.isEmpty;
      _error = null;
    });

    try {
      final posts = await _postsFirestore.fetchPostsByAuthor(
        uid,
        forceRefresh: forceRefresh,
      );
      for (final post in posts) {
        _postService.upsertRemotePost(post);
      }
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
        _error = null;
        _loadedForUid = uid;
      });
    } catch (e) {
      debugPrint('내 글 목록 로드 실패: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _openPost(Post post) {
    _postService.upsertRemotePost(post);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(post: post),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final auth = AuthService.instance;
    final uid = auth.kakaoUserId;

    return Scaffold(
      appBar: const CafeinBackAppBar(title: '내가 쓴 글'),
      body: ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          final currentUid = auth.kakaoUserId ?? uid;
          if (!auth.isLoggedIn ||
              currentUid == null ||
              currentUid.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '로그인하면 내가 쓴 글을 볼 수 있어요.',
                      textAlign: TextAlign.center,
                      style: CafeinTypography.commentBody(colors.muted),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      child: const Text('로그인'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '내 글을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                      textAlign: TextAlign.center,
                      style: CafeinTypography.commentBody(colors.muted),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _load(forceRefresh: true),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (_posts.isEmpty) {
            return Center(
              child: Text(
                '아직 작성한 글이 없어요.',
                style: CafeinTypography.commentBody(colors.muted),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => _load(forceRefresh: true),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: _posts.length,
              separatorBuilder: (_, _) => const Divider(
                height: 0.5,
                thickness: 0.5,
                indent: AppSpacing.screenH,
                endIndent: AppSpacing.screenH,
              ),
              itemBuilder: (context, index) {
                final post = _posts[index];
                return PostListItem(
                  post: post,
                  onTap: () => _openPost(post),
                  onEdit: () async {
                    _postService.upsertRemotePost(post);
                    _postService.markAsMyPost(post.id);
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            WritePostScreen(editPostId: post.id),
                      ),
                    );
                    if (mounted) await _load(forceRefresh: true);
                  },
                  onDelete: () async {
                    _postService.upsertRemotePost(post);
                    final deleted =
                        await PostMoreSheet.deleteWithConfirm(context, post);
                    if (deleted && mounted) await _load(forceRefresh: true);
                  },
                  onEditPoll: post.poll == null
                      ? null
                      : () async {
                          _postService.upsertRemotePost(post);
                          final updated =
                              await EditPollSheet.show(context, post: post);
                          if (updated != null && mounted) {
                            await _load(forceRefresh: true);
                          }
                        },
                  onVote: (optionId) => castPostVote(
                    context,
                    post: post,
                    optionId: optionId,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
