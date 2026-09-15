import 'package:flutter/material.dart';

import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/poll_vote_helper.dart';
import '../services/post_service.dart';
import '../services/posts_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/post_list_item.dart';
import '../widgets/post_more_sheet.dart';
import 'login_screen.dart';
import 'post_detail_screen.dart';
import 'write_post_screen.dart';

/// List of posts written by the current logged-in user (Firestore).
class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  final _postService = PostService.instance;
  final _postsFirestore = PostsFirestoreService.instance;

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
      appBar: AppBar(
        title: const Text('내가 쓴 글'),
      ),
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
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        color: colors.muted,
                      ),
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

          return StreamBuilder<List<Post>>(
            stream: _postsFirestore.watchPostsByAuthor(currentUid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.screenH),
                    child: Text(
                      '내 글을 불러오지 못했어요.\n복합 인덱스가 필요할 수 있어요.',
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

              final posts = snapshot.data ?? const [];
              if (posts.isEmpty) {
                return Center(
                  child: Text(
                    '아직 작성한 글이 없어요.',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      color: colors.muted,
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
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
                    onMore: () {
                      _postService.upsertRemotePost(post);
                      PostMoreSheet.show(context, post: post);
                    },
                    onEdit: () {
                      _postService.upsertRemotePost(post);
                      _postService.markAsMyPost(post.id);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              WritePostScreen(editPostId: post.id),
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
            },
          );
        },
      ),
    );
  }
}
