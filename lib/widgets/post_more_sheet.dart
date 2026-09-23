import 'package:flutter/material.dart';

import '../models/post.dart';
import '../screens/auth_required_screen.dart';
import '../screens/write_post_screen.dart';
import '../services/auth_service.dart';
import '../services/block_firestore_service.dart';
import '../services/post_service.dart';
import '../services/posts_firestore_service.dart';
import '../services/report_firestore_service.dart';
import '../theme/app_typography.dart';
import 'report_bottom_sheet.dart';
import 'topic_picker_sheet.dart';

/// Post overflow: edit / report / block / delete (owner).
/// Share is intentionally omitted until a real share flow ships.
class PostMoreSheet {
  static Future<void> show(
    BuildContext context, {
    required Post post,
  }) async {
    final service = PostService.instance;
    final postsFs = PostsFirestoreService.instance;
    final mine = service.isMyPost(post.id, post: post);
    final colors = Theme.of(context).colorScheme;
    final authorId = post.authorId?.trim() ?? '';

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mine)
                ListTile(
                  title: Text(
                    '수정',
                    style: CafeinTypography.commentBody(colors.onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => WritePostScreen(editPostId: post.id),
                      ),
                    );
                  },
                ),
              if (mine)
                ListTile(
                  title: Text(
                    '주제 수정',
                    style: CafeinTypography.commentBody(colors.onSurface),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final selected = await TopicPickerSheet.show(
                      context,
                      initialTopic: post.topic,
                      title: '주제 수정',
                      hintText: '주제를 입력하세요',
                      showClearOption: true,
                    );
                    if (selected == null || !context.mounted) return;
                    try {
                      final updated = await postsFs.updatePostTopic(
                        postId: post.id,
                        topicName: selected.isEmpty ? null : selected,
                      );
                      service.upsertRemotePost(updated);
                      service.updatePostTopic(
                        post.id,
                        selected.isEmpty ? null : selected,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('주제를 수정했어요.')),
                      );
                    } catch (e) {
                      debugPrint('주제 수정 실패: $e');
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('주제를 수정할 수 없어요.')),
                      );
                    }
                  },
                ),
              if (!mine) ...[
                ListTile(
                  title: Text(
                    '신고',
                    style: CafeinTypography.commentBody(colors.onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _reportPost(context, post);
                  },
                ),
                if (authorId.isNotEmpty)
                  ListTile(
                    title: Text(
                      '사용자 차단',
                      style: CafeinTypography.commentBody(colors.onSurface),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _blockAuthor(context, authorId);
                    },
                  ),
              ],
              if (mine)
                ListTile(
                  title: Text(
                    '삭제',
                    style: CafeinTypography.commentBody(colors.error),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final deleted = await deleteWithConfirm(context, post);
                    if (deleted &&
                        context.mounted &&
                        Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Confirm + delete post (feed 「삭제」 button / sheet).
  static Future<bool> deleteWithConfirm(
    BuildContext context,
    Post post,
  ) async {
    final colors = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: const Text('게시글을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '삭제',
              style: TextStyle(color: colors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;

    final service = PostService.instance;
    final postsFs = PostsFirestoreService.instance;
    try {
      await postsFs.deletePost(post.id);
      service.deletePost(post.id);
      if (!context.mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('글을 삭제했어요.')),
      );
      return true;
    } catch (e) {
      debugPrint('글 삭제 실패: $e');
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('글을 삭제할 수 없어요.')),
      );
      return false;
    }
  }

  static Future<bool> _ensureWriter(BuildContext context) async {
    if (AuthService.instance.canWriteContent) return true;
    return AuthRequiredScreen.ensureWriter(context);
  }

  static Future<void> _reportPost(BuildContext context, Post post) async {
    if (!await _ensureWriter(context) || !context.mounted) return;
    await ReportBottomSheet.show(
      context,
      onSubmit: (reason) async {
        try {
          await ReportFirestoreService.instance.submitReport(
            targetType: 'post',
            targetId: post.id,
            targetAuthorId: post.authorId,
            reason: reason,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('신고가 접수되었습니다.')),
          );
        } catch (e) {
          debugPrint('신고 실패: $e');
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('신고를 접수하지 못했어요.')),
          );
        }
      },
    );
  }

  static Future<void> _blockAuthor(
    BuildContext context,
    String authorId,
  ) async {
    if (!await _ensureWriter(context) || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('사용자 차단'),
        content: const Text(
          '이 사용자를 차단하시겠습니까?\n\n'
          '차단하면 해당 사용자의 게시글과 댓글이\n'
          '내 화면에서 보이지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('차단'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await BlockFirestoreService.instance.blockUser(authorId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용자를 차단했어요.')),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('차단 실패: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('차단하지 못했어요.')),
      );
    }
  }
}
