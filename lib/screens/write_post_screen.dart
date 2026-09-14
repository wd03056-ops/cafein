import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/poll.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/posts_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/no_underline_text_editing_controller.dart';
import '../widgets/topic_picker_sheet.dart';
import 'post_detail_screen.dart';

class WritePostScreen extends StatefulWidget {
  const WritePostScreen({super.key, this.editPostId});

  /// When set, screen opens in edit mode for this post.
  final String? editPostId;

  @override
  State<WritePostScreen> createState() => _WritePostScreenState();
}

class _WritePostScreenState extends State<WritePostScreen> {
  final _contentController = NoUnderlineTextEditingController();
  final _contentFocus = FocusNode();
  final _pollQuestionController = NoUnderlineTextEditingController();
  final List<TextEditingController> _optionControllers = [];

  late String _nickname;
  String? _selectedTopic;
  bool _showPoll = false;
  bool _pollConfirmed = false;
  bool _submitting = false;
  bool _hasContent = false;
  bool _showComposeHints = true;

  String _prevText = '';
  bool _openingTopic = false;
  bool _suppressBang = false;

  bool get _isEditing => widget.editPostId != null;

  @override
  void initState() {
    super.initState();
    _nickname = AuthService.instance.nickname ?? AppConstants.randomNickname();
    _contentController.addListener(_onContentChanged);
    _loadEditPostIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentFocus.requestFocus();
    });
  }

  void _loadEditPostIfNeeded() {
    final editId = widget.editPostId;
    if (editId == null) return;

    final post = PostService.instance.getById(editId);
    if (post == null || !PostService.instance.isMyPost(editId)) return;

    _nickname = post.author;
    _contentController.text = post.content;
    _prevText = post.content;
    _selectedTopic = post.topic;
    _hasContent = post.content.trim().isNotEmpty;
    _showComposeHints = post.content.isEmpty;

    final poll = post.poll;
    if (poll != null) {
      _showPoll = true;
      _pollConfirmed = true;
      _pollQuestionController.text = poll.question;
      for (final option in poll.options) {
        _optionControllers.add(
          NoUnderlineTextEditingController(text: option.text),
        );
      }
      if (_optionControllers.length < 2) {
        while (_optionControllers.length < 2) {
          _optionControllers.add(NoUnderlineTextEditingController());
        }
      }
    }
  }

  void _onContentChanged() {
    final text = _contentController.text;
    final has = text.trim().isNotEmpty;
    final showHints = text.isEmpty;
    if (has != _hasContent || showHints != _showComposeHints) {
      setState(() {
        _hasContent = has;
        _showComposeHints = showHints;
      });
    }

    if (_suppressBang || _openingTopic) {
      _prevText = text;
      return;
    }

    final bangIndex = _detectNewTopicBang(text, _prevText);
    if (bangIndex != null) {
      // Remove "!" immediately so it never stays in the body.
      _suppressBang = true;
      final cleaned = text.replaceRange(bangIndex, bangIndex + 1, '');
      _contentController.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(
          offset: bangIndex.clamp(0, cleaned.length),
        ),
      );
      _prevText = cleaned;
      _suppressBang = false;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openTopicPicker();
      });
      return;
    }

    _prevText = text;
  }

  /// Returns index of a newly typed topic-trigger `!`, or null.
  /// Sentence-ending "대박!" does not open the sheet.
  int? _detectNewTopicBang(String text, String prev) {
    if (text.length != prev.length + 1) return null;

    final sel = _contentController.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;

    final cursor = sel.baseOffset;
    if (cursor <= 0 || cursor - 1 >= text.length) return null;
    if (text[cursor - 1] != '!') return null;

    final bangIndex = cursor - 1;
    if (bangIndex > 0 && !_isTopicBoundary(text[bangIndex - 1])) {
      return null;
    }
    return bangIndex;
  }

  bool _isTopicBoundary(String ch) =>
      ch == '\n' || ch == '\r' || ch.trim().isEmpty;

  Future<void> _openTopicPicker() async {
    if (_openingTopic || !mounted) return;
    _openingTopic = true;

    final selected = await TopicPickerSheet.show(
      context,
      title: '주제 선택',
      hintText: '주제를 검색해보세요',
      initialTopic: _selectedTopic,
      showClearOption: _selectedTopic != null,
    );

    if (!mounted) {
      _openingTopic = false;
      return;
    }

    if (selected != null) {
      setState(() {
        _selectedTopic = selected.trim().isEmpty ? null : selected.trim();
      });
    }

    _openingTopic = false;
    _prevText = _contentController.text;

    if (mounted) {
      _contentFocus.requestFocus();
    }
  }

  void _clearTopic() {
    setState(() => _selectedTopic = null);
  }

  @override
  void dispose() {
    _contentController.removeListener(_onContentChanged);
    _contentController.dispose();
    _contentFocus.dispose();
    _pollQuestionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _togglePoll() {
    if (_showPoll) {
      _removePoll();
      return;
    }
    setState(() {
      _showPoll = true;
      _pollConfirmed = false;
      if (_optionControllers.isEmpty) {
        _addOption();
        _addOption();
      }
    });
  }

  void _removePoll() {
    _pollQuestionController.clear();
    for (final c in _optionControllers) {
      c.dispose();
    }
    setState(() {
      _optionControllers.clear();
      _showPoll = false;
      _pollConfirmed = false;
    });
  }

  bool _confirmPoll() {
    final question = _pollQuestionController.text.trim();
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (question.isEmpty || options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('투표 질문과 선택지 2개 이상을 입력해주세요.')),
      );
      return false;
    }

    FocusScope.of(context).unfocus();
    setState(() => _pollConfirmed = true);
    return true;
  }

  void _editPoll() {
    setState(() => _pollConfirmed = false);
  }

  Poll _draftPoll() {
    final question = _pollQuestionController.text.trim();
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    return Poll(
      question: question,
      options: [
        for (var i = 0; i < options.length; i++)
          PollOption(id: 'draft-$i', text: options[i]),
      ],
    );
  }

  Future<void> _confirmRemovePoll() async {
    final colors = Theme.of(context).colorScheme;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          surfaceTintColor: Colors.transparent,
          title: Text(
            '투표 삭제',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          content: Text(
            '투표를 삭제하시겠습니까?',
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: colors.onSurface,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                '아니오',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  color: colors.muted,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                '예',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true && mounted) {
      _removePoll();
    }
  }

  Widget _buildPollHeaderActions({required bool confirmed}) {
    final colors = Theme.of(context).colorScheme;

    if (confirmed) {
      return Row(
        children: [
          const Spacer(),
          TextButton(
            onPressed: _editPoll,
            style: TextButton.styleFrom(
              foregroundColor: colors.accentBlue,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '수정',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: _confirmRemovePoll,
            tooltip: '투표 삭제',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: colors.muted,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        const Spacer(),
        IconButton(
          onPressed: _confirmPoll,
          tooltip: '투표 확정',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(
            Icons.check_rounded,
            size: 22,
            color: colors.accentBlue,
          ),
        ),
        IconButton(
          onPressed: _removePoll,
          tooltip: '투표 취소',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(
            Icons.close_rounded,
            size: 20,
            color: colors.muted,
          ),
        ),
      ],
    );
  }

  /// Matches published (unvoted) poll look — no gray card background.
  Widget _buildConfirmedPollPreview() {
    final poll = _draftPoll();
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPollHeaderActions(confirmed: true),
        Text(
          poll.question,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        for (final option in poll.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: colors.fill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                option.text,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: colors.onSurface,
                  height: 1.35,
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          '투표는 이 글 작성 화면에서만 수정할 수 있어요.',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 12,
            fontWeight: FontWeight.w400,
            height: 1.4,
            color: colors.muted,
          ),
        ),
      ],
    );
  }

  Widget _buildPollEditor() {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '투표',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: colors.onSurface,
                  ),
                ),
              ),
              IconButton(
                onPressed: _confirmPoll,
                tooltip: '투표 확정',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  Icons.check_rounded,
                  size: 22,
                  color: colors.accentBlue,
                ),
              ),
              IconButton(
                onPressed: _removePoll,
                tooltip: '투표 취소',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: colors.muted,
                ),
              ),
            ],
          ),
          TextField(
            controller: _pollQuestionController,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              color: colors.onSurface,
            ),
            cursorColor: colors.onSurface,
            decoration: InputDecoration(
              hintText: '투표 질문',
              hintStyle: TextStyle(
                fontFamily: 'Pretendard',
                color: colors.mutedSoft,
              ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          ...List.generate(_optionControllers.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _optionControllers[index],
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        color: colors.onSurface,
                      ),
                      cursorColor: colors.onSurface,
                      decoration: InputDecoration(
                        hintText: '선택지 ${index + 1}',
                        hintStyle: TextStyle(
                          fontFamily: 'Pretendard',
                          color: colors.mutedSoft,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  if (_optionControllers.length > 2)
                    IconButton(
                      onPressed: () => _removeOption(index),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '선택지 삭제',
                    ),
                ],
              ),
            );
          }),
          TextButton(
            onPressed: _optionControllers.length >= 6 ? null : _addOption,
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurface,
              padding: EdgeInsets.zero,
            ),
            child: const Text(
              '선택지 추가',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addOption() {
    if (_optionControllers.length >= 6) return;
    setState(() {
      _optionControllers.add(NoUnderlineTextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers.removeAt(index).dispose();
    });
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty || _submitting) return;

    Poll? poll;
    if (_showPoll) {
      if (!_pollConfirmed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('투표 확인(✓)을 눌러 투표를 확정해주세요.')),
        );
        return;
      }

      final question = _pollQuestionController.text.trim();
      final options = _optionControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      if (question.isEmpty || options.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('투표 질문과 선택지 2개 이상을 입력해주세요.')),
        );
        return;
      }

      // Keep previous vote counts when editing an existing poll.
      final existing = _isEditing
          ? PostService.instance.getById(widget.editPostId!)?.poll
          : null;
      poll = Poll(
        question: question,
        hasVoted: existing?.hasVoted ?? false,
        options: [
          for (var i = 0; i < options.length; i++)
            PollOption(
              id: existing != null && i < existing.options.length
                  ? existing.options[i].id
                  : 'new-$i',
              text: options[i],
              votes: existing != null && i < existing.options.length
                  ? existing.options[i].votes
                  : 0,
              selectedByMe: existing != null &&
                      i < existing.options.length
                  ? existing.options[i].selectedByMe
                  : false,
            ),
        ],
      );
    }

    setState(() => _submitting = true);

    if (_isEditing) {
      final ok = PostService.instance.updatePost(
        postId: widget.editPostId!,
        content: content,
        tags: _selectedTopic == null ? const [] : [_selectedTopic!],
        poll: poll,
        clearPoll: !_showPoll,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('글을 수정할 수 없어요.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('글을 수정했어요.')),
      );
      Navigator.of(context).pop(true);
      return;
    }

    final authorId = AuthService.instance.kakaoUserId;
    if (authorId != null && authorId.isNotEmpty) {
      try {
        final remote = await PostsFirestoreService.instance.createPost(
          content: content,
          authorId: authorId,
          authorNickname: _nickname,
          experience: AuthService.instance.experience,
          cafeType: AuthService.instance.cafeType,
          tags: _selectedTopic == null ? const [] : [_selectedTopic!],
        );
        final withPoll = remote.copyWith(poll: poll);
        PostService.instance.markAsMyPost(withPoll.id);
        PostService.instance.upsertRemotePost(withPoll);
        if (!mounted) return;
        setState(() => _submitting = false);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => PostDetailScreen(post: withPoll),
          ),
        );
        return;
      } catch (e) {
        debugPrint('Firestore 글 저장 실패, 로컬만 유지: $e');
      }
    }

    final post = PostService.instance.addPost(
      content: content,
      poll: poll,
      tags: _selectedTopic == null ? const [] : [_selectedTopic!],
      author: _nickname,
      experience: AuthService.instance.experience,
      cafeType: AuthService.instance.cafeType,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(post: post),
      ),
    );
  }

  Widget _buildSelectedTopic() {
    final topic = _selectedTopic;
    if (topic == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        children: [
          Text(
            '주제:',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: colors.muted,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: GestureDetector(
              onTap: _openTopicPicker,
              behavior: HitTestBehavior.opaque,
              child: Text(
                topic,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.onSurface,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: _clearTopic,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
              child: Icon(Icons.close, size: 16, color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposeHints() {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '무슨 이야기를 하고 싶나요?',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            height: 1.55,
            fontWeight: FontWeight.w400,
            color: colors.mutedSoft,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '!을 입력해 주제를 정해보세요.',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w400,
            color: colors.muted,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _hasContent && !_submitting;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        toolbarHeight: 56,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        leadingWidth: 72,
        leading: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          style: TextButton.styleFrom(
            foregroundColor: colors.onSurface,
            padding: const EdgeInsets.only(left: 8),
          ),
          child: const Text(
            '취소',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: canSubmit ? _submit : null,
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurface,
                disabledForegroundColor: colors.mutedSoft,
              ),
              child: Text(
                _isEditing ? '수정 완료' : '등록',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: canSubmit ? colors.onSurface : colors.mutedSoft,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                22,
                AppSpacing.screenH,
                24,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _nickname,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Stack(
                    alignment: Alignment.topLeft,
                    children: [
                      Theme(
                        data: Theme.of(context).copyWith(
                          inputDecorationTheme: const InputDecorationTheme(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            filled: false,
                            fillColor: Colors.transparent,
                            hoverColor: Colors.transparent,
                            focusColor: Colors.transparent,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        child: TextField(
                          controller: _contentController,
                          focusNode: _contentFocus,
                          minLines: 6,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          spellCheckConfiguration:
                              const SpellCheckConfiguration.disabled(),
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            height: 1.55,
                            fontWeight: FontWeight.w400,
                            color: colors.onSurface,
                            decoration: TextDecoration.none,
                            decorationThickness: 0,
                          ),
                          cursorColor: colors.onSurface,
                          decoration: const InputDecoration.collapsed(
                            hintText: null,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_showComposeHints)
                        IgnorePointer(
                          child: _buildComposeHints(),
                        ),
                    ],
                  ),
                  _buildSelectedTopic(),
                  if (_showPoll) ...[
                    const SizedBox(height: 20),
                    if (_pollConfirmed)
                      _buildConfirmedPollPreview()
                    else
                      _buildPollEditor(),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 0.5, thickness: 0.5),
          SafeArea(
            top: false,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _togglePoll,
                      tooltip: _showPoll ? '투표 제거' : '투표',
                      icon: Icon(
                        _showPoll
                            ? Icons.bar_chart
                            : Icons.bar_chart_outlined,
                        size: 20,
                      ),
                      color: colors.onSurface,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
