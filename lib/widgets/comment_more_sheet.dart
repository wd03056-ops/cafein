import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../screens/auth_required_screen.dart';
import '../services/auth_service.dart';
import '../services/block_firestore_service.dart';
import '../services/comments_firestore_service.dart';
import '../services/report_firestore_service.dart';
import '../theme/app_typography.dart';
import 'report_bottom_sheet.dart';

/// Comment overflow: report / block (others). Own comments use inline 수정/삭제.
class CommentMoreSheet {
  static Future<void> show(
    BuildContext context, {
    required Comment comment,
    VoidCallback? onDeleted,
  }) async {
    final colors = Theme.of(context).colorScheme;
    final myId = AuthService.instance.kakaoUserId?.trim() ?? '';
    final authorId = comment.authorId?.trim() ?? '';
    final mine = myId.isNotEmpty && authorId.isNotEmpty && myId == authorId;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!mine) ...[
                ListTile(
                  title: Text(
                    '신고',
                    style: CafeinTypography.commentBody(colors.onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _report(context, comment);
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
                      _block(context, authorId);
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
                    await deleteWithConfirm(
                      context,
                      comment: comment,
                      onDeleted: onDeleted,
                    );
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Owner inline 「삭제」.
  static Future<bool> deleteWithConfirm(
    BuildContext context, {
    required Comment comment,
    VoidCallback? onDeleted,
  }) async {
    final colors = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('댓글 삭제'),
        content: const Text('댓글을 삭제하시겠습니까?'),
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
    try {
      await CommentsFirestoreService.instance.deleteComment(
        postId: comment.postId,
        commentId: comment.id,
      );
      onDeleted?.call();
      if (!context.mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글을 삭제했어요.')),
      );
      return true;
    } catch (e) {
      debugPrint('댓글 삭제 실패: $e');
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글을 삭제할 수 없어요.')),
      );
      return false;
    }
  }

  static Future<bool> _ensureWriter(BuildContext context) async {
    if (AuthService.instance.canWriteContent) return true;
    return AuthRequiredScreen.ensureWriter(context);
  }

  static Future<void> _report(BuildContext context, Comment comment) async {
    if (!await _ensureWriter(context) || !context.mounted) return;
    await ReportBottomSheet.show(
      context,
      onSubmit: (reason) async {
        try {
          await ReportFirestoreService.instance.submitReport(
            targetType: 'comment',
            targetId: comment.id,
            targetAuthorId: comment.authorId,
            parentPostId: comment.postId,
            reason: reason,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('신고가 접수되었습니다.')),
          );
        } catch (e) {
          debugPrint('댓글 신고 실패: $e');
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('신고를 접수하지 못했어요.')),
          );
        }
      },
    );
  }

  static Future<void> _block(BuildContext context, String authorId) async {
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
    } catch (e) {
      debugPrint('차단 실패: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('차단하지 못했어요.')),
      );
    }
  }
}
