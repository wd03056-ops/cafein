import 'package:flutter/material.dart';

import '../models/poll.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../services/posts_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'no_underline_text_editing_controller.dart';
import 'poll_char_counter.dart';

/// Bottom sheet to edit only the poll on an existing post.
class EditPollSheet {
  static Future<Post?> show(
    BuildContext context, {
    required Post post,
  }) {
    final poll = post.poll;
    if (poll == null) return Future.value(null);

    return showModalBottomSheet<Post>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: _EditPollSheetBody(post: post, initialPoll: poll),
        );
      },
    );
  }
}

class _EditPollSheetBody extends StatefulWidget {
  const _EditPollSheetBody({
    required this.post,
    required this.initialPoll,
  });

  final Post post;
  final Poll initialPoll;

  @override
  State<_EditPollSheetBody> createState() => _EditPollSheetBodyState();
}

class _EditPollSheetBodyState extends State<_EditPollSheetBody> {
  static const _titleMax = 40;
  static const _optionMax = 25;

  late final TextEditingController _titleController;
  late final List<TextEditingController> _optionControllers;
  /// Original option ids aligned with [_optionControllers] indices.
  late final List<String> _optionIds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final poll = widget.initialPoll;
    _titleController = NoUnderlineTextEditingController(
      text: poll.trimmedTitle ?? poll.question,
    );
    _optionControllers = [
      for (final o in poll.options)
        NoUnderlineTextEditingController(text: o.text),
    ];
    _optionIds = [for (final o in poll.options) o.id];
    while (_optionControllers.length < 2) {
      _optionControllers.add(NoUnderlineTextEditingController());
      _optionIds.add('opt_${_optionIds.length}');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 4) return;
    setState(() {
      _optionControllers.add(NoUnderlineTextEditingController());
      _optionIds.add('opt_${DateTime.now().microsecondsSinceEpoch}');
    });
  }

  void _removeOption(int index) {
    if (index < 2 || _optionControllers.length <= 2) return;
    setState(() {
      _optionControllers.removeAt(index).dispose();
      _optionIds.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (_saving) return;

    final title = _titleController.text.trim();
    final texts = _optionControllers
        .map((c) => c.text.trim())
        .toList(growable: false);

    final options = <PollOption>[];
    for (var i = 0; i < texts.length; i++) {
      final text = texts[i];
      if (text.isEmpty) continue;
      final id = i < _optionIds.length && _optionIds[i].trim().isNotEmpty
          ? _optionIds[i].trim()
          : 'opt_$i';
      PollOption? matched;
      for (final o in widget.initialPoll.options) {
        if (o.id == id) {
          matched = o;
          break;
        }
      }
      options.add(
        PollOption(
          id: id,
          text: text,
          votes: matched?.votes ?? 0,
          selectedByMe: matched?.selectedByMe ?? false,
        ),
      );
    }

    if (title.isEmpty || options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('제목과 질문 2개 이상을 입력해주세요.'),
        ),
      );
      return;
    }
    if (title.length > _titleMax ||
        options.any((o) => o.text.length > _optionMax)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('제목은 40자, 질문은 25자까지 입력할 수 있어요.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final poll = Poll(
        question: title,
        hasVoted: widget.initialPoll.hasVoted,
        options: options,
      );
      final updated = await PostsFirestoreService.instance.updatePost(
        postId: widget.post.id,
        content: widget.post.content,
        poll: poll,
      );
      PostService.instance.upsertRemotePost(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('투표를 수정했어요.')),
      );
      Navigator.of(context).pop(updated);
    } catch (e) {
      debugPrint('투표 수정 실패: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('투표를 수정할 수 없어요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          0,
          AppSpacing.screenH,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '투표 수정',
              style: CafeinTypography.postTitle(colors.onSurface),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      '제목',
                      style: CafeinTypography.metadata(colors.muted)
                          .copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      style: CafeinTypography.pollTitle(colors.onSurface),
                      cursorColor: colors.onSurface,
                      decoration: InputDecoration(
                        hintText: '제목을 작성해보세요.',
                        hintStyle: CafeinTypography.metadata(colors.mutedSoft),
                        filled: true,
                        fillColor: colors.fill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  PollCharCounter(
                    controller: _titleController,
                    maxLength: _titleMax,
                  ),
                ],
              ),
            ),
            ...List.generate(_optionControllers.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _optionControllers[index],
                        style: CafeinTypography.pollOption(colors.onSurface),
                        cursorColor: colors.onSurface,
                        decoration: InputDecoration(
                          hintText: '질문',
                          hintStyle:
                              CafeinTypography.metadata(colors.mutedSoft),
                          filled: true,
                          fillColor: colors.fill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    PollCharCounter(
                      controller: _optionControllers[index],
                      maxLength: _optionMax,
                    ),
                    if (index >= 2)
                      IconButton(
                        onPressed: _saving ? null : () => _removeOption(index),
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: '질문 삭제',
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _saving || _optionControllers.length >= 4
                    ? null
                    : _addOption,
                style: TextButton.styleFrom(
                  foregroundColor: colors.onSurface,
                  disabledForegroundColor: colors.mutedSoft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  minimumSize: const Size(0, 44),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: Text(
                  '질문 추가 (최대 4개)',
                  style: CafeinTypography.button(
                    _optionControllers.length >= 4
                        ? colors.mutedSoft
                        : colors.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: colors.onSurface,
                foregroundColor: colors.surface,
              ),
              child: _saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.surface,
                      ),
                    )
                  : Text(
                      '저장',
                      style: CafeinTypography.button(colors.surface),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
