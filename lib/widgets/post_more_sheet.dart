import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/post.dart';
import '../services/post_service.dart';
import '../services/posts_firestore_service.dart';
import 'topic_picker_sheet.dart';
import 'report_bottom_sheet.dart';
import '../screens/write_post_screen.dart';

/// Post overflow menu: share / edit topic / report / delete (owner only).
class PostMoreSheet {
  static Future<void> show(
    BuildContext context, {
    required Post post,
  }) async {
    final service = PostService.instance;
    final postsFs = PostsFirestoreService.instance;
    final mine = service.isMyPost(post.id);
    final colors = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  '공유',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    color: colors.onSurface,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final text = post.topic == null
                      ? post.content
                      : '[${post.topic}] ${post.content}';
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('글 내용을 복사했어요.')),
                  );
                },
              ),
              if (mine)
                ListTile(
                  title: Text(
                    '수정',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      color: colors.onSurface,
                    ),
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
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      color: colors.onSurface,
                    ),
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
              ListTile(
                title: Text(
                  '신고',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    color: colors.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ReportBottomSheet.show(
                    context,
                    onSubmit: (reason) {
                      service.reportContent(
                        targetType: 'post',
                        targetId: post.id,
                        reason: reason,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('신고가 접수되었습니다. (임시)')),
                      );
                    },
                  );
                },
              ),
              if (mine)
                ListTile(
                  title: Text(
                    '삭제',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      color: colors.error,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    try {
                      await postsFs.deletePost(post.id);
                      service.deletePost(post.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('글을 삭제했어요.')),
                      );
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    } catch (e) {
                      debugPrint('글 삭제 실패: $e');
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('글을 삭제할 수 없어요.')),
                      );
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
}
