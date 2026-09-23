import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/poll.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/posts_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/no_underline_text_editing_controller.dart';
import '../widgets/dismiss_keyboard_on_tap.dart';
import '../widgets/poll_char_counter.dart';
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
  final _pollTitleController = NoUnderlineTextEditingController();
  final List<TextEditingController> _optionControllers = [];
  final _scrollController = ScrollController();
  final _pollSectionKey = GlobalKey();

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
    _pollTitleController.addListener(_onPollFieldsChanged);
    _loadEditPostIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentFocus.requestFocus();
    });
  }

  void _onPollFieldsChanged() {
    if (mounted) setState(() {});
  }

  void _attachOptionListener(TextEditingController c) {
    c.addListener(_onPollFieldsChanged);
  }

  /// Poll title + ≥2 options filled (within length limits).
  bool get _pollFilledEnough {
    if (!_showPoll) return false;
    final title = _pollTitleController.text.trim();
    if (title.isEmpty || title.length > _pollTitleMax) return false;
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (options.length < 2) return false;
    return options.every((t) => t.length <= _pollOptionMax);
  }

  bool get _hasTopic => (_selectedTopic ?? '').trim().isNotEmpty;

  bool get _canSubmit {
    if (_submitting) return false;
    if (!_hasTopic) return false;
    return _hasContent || _pollFilledEnough;
  }

  void _loadEditPostIfNeeded() {
    final editId = widget.editPostId;
    if (editId == null) return;

    final post = PostService.instance.getById(editId);
    if (post == null ||
        !PostService.instance.isMyPost(editId, post: post)) {
      return;
    }

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
      _pollTitleController.text = poll.trimmedTitle ?? poll.question;
      for (final option in poll.options) {
        final c = NoUnderlineTextEditingController(text: option.text);
        _attachOptionListener(c);
        _optionControllers.add(c);
      }
      if (_optionControllers.length < 2) {
        while (_optionControllers.length < 2) {
          final c = NoUnderlineTextEditingController();
          _attachOptionListener(c);
          _optionControllers.add(c);
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
    _pollTitleController.removeListener(_onPollFieldsChanged);
    _pollTitleController.dispose();
    _scrollController.dispose();
    for (final c in _optionControllers) {
      c.removeListener(_onPollFieldsChanged);
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
        final a = NoUnderlineTextEditingController();
        final b = NoUnderlineTextEditingController();
        _attachOptionListener(a);
        _attachOptionListener(b);
        _optionControllers.addAll([a, b]);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _pollSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      }
    });
  }

  void _removePoll() {
    _pollTitleController.clear();
    for (final c in _optionControllers) {
      c.removeListener(_onPollFieldsChanged);
      c.dispose();
    }
    setState(() {
      _optionControllers.clear();
      _showPoll = false;
      _pollConfirmed = false;
    });
  }

  static const _pollTitleMax = 40;
  static const _pollOptionMax = 25;

  bool _confirmPoll() {
    final title = _pollTitleController.text.trim();
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (title.isEmpty || options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('제목과 질문 2개 이상을 입력해주세요.'),
        ),
      );
      return false;
    }
    if (title.length > _pollTitleMax ||
        options.any((t) => t.length > _pollOptionMax)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('제목은 40자, 질문은 25자까지 입력할 수 있어요.'),
        ),
      );
      return false;
    }

    FocusScope.of(context).unfocus();
    setState(() => _pollConfirmed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _pollSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: 0.15,
        );
      }
    });
    return true;
  }

  void _editPoll() {
    setState(() => _pollConfirmed = false);
  }

  Poll _draftPoll() {
    final title = _pollTitleController.text.trim();
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    return Poll(
      question: title,
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
            style: CafeinTypography.postTitle(colors.onSurface),
          ),
          content: Text(
            '투표를 삭제하시겠습니까?',
            style: CafeinTypography.postBody(colors.onSurface),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                '아니오',
                style: CafeinTypography.button(colors.muted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                '예',
                style: CafeinTypography.button(colors.error),
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
            child: Text(
              '수정',
              style: CafeinTypography.button(),
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
        if (poll.question.trim().isNotEmpty) ...[
          Text(
            poll.question,
            style: CafeinTypography.pollTitle(colors.onSurface),
          ),
          const SizedBox(height: 12),
        ],
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
                style: CafeinTypography.pollOption(colors.onSurface),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          '투표는 이 글 작성 화면에서만 수정할 수 있어요.',
          style: CafeinTypography.metadata(colors.muted),
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
              Text(
                '투표',
                style: CafeinTypography.nickname(colors.onSurface),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '주제 필수,본문 작성 선택',
                  style: CafeinTypography.metadata(colors.muted).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
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
                    controller: _pollTitleController,
                    style: CafeinTypography.pollTitle(colors.onSurface),
                    cursorColor: colors.onSurface,
                    decoration: InputDecoration(
                      hintText: '제목을 작성해보세요.',
                      hintStyle: CafeinTypography.metadata(colors.mutedSoft),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                PollCharCounter(
                  controller: _pollTitleController,
                  maxLength: _pollTitleMax,
                ),
              ],
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
                      style: CafeinTypography.pollOption(colors.onSurface),
                      cursorColor: colors.onSurface,
                      decoration: InputDecoration(
                        hintText: '질문',
                        hintStyle: CafeinTypography.metadata(colors.mutedSoft),
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
                  PollCharCounter(
                    controller: _optionControllers[index],
                    maxLength: _pollOptionMax,
                  ),
                  // 기본 2개에는 X 없음 — 추가분(index >= 2)만 삭제.
                  if (index >= 2)
                    IconButton(
                      onPressed: () => _removeOption(index),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '질문 삭제',
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _optionControllers.length >= 4 ? null : _addOption,
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurface,
              disabledForegroundColor: colors.mutedSoft,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              alignment: Alignment.centerLeft,
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
        ],
      ),
    );
  }

  void _addOption() {
    if (_optionControllers.length >= 4) return;
    setState(() {
      final c = NoUnderlineTextEditingController();
      _attachOptionListener(c);
      _optionControllers.add(c);
    });
  }

  void _removeOption(int index) {
    if (index < 2 || _optionControllers.length <= 2) return;
    setState(() {
      final c = _optionControllers.removeAt(index);
      c.removeListener(_onPollFieldsChanged);
      c.dispose();
    });
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (_submitting) return;

    if (!_hasTopic) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('주제를 선택해주세요.')),
      );
      return;
    }

    // Body optional when a valid poll is ready.
    if (content.isEmpty && !_pollFilledEnough) return;

    Poll? poll;
    if (_showPoll) {
      final title = _pollTitleController.text.trim();
      final options = _optionControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      if (title.isEmpty || options.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('제목과 질문 2개 이상을 입력해주세요.'),
          ),
        );
        return;
      }
      if (title.length > _pollTitleMax ||
          options.any((t) => t.length > _pollOptionMax)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('제목은 40자, 질문은 25자까지 입력할 수 있어요.'),
          ),
        );
        return;
      }

      if (!_pollConfirmed) {
        setState(() => _pollConfirmed = true);
      }

      // Keep previous vote counts when editing an existing poll.
      final existing = _isEditing
          ? PostService.instance.getById(widget.editPostId!)?.poll
          : null;
      poll = Poll(
        question: title,
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
    } else if (content.isEmpty) {
      return;
    }

    setState(() => _submitting = true);

    if (_isEditing) {
      try {
        final updated = await PostsFirestoreService.instance.updatePost(
          postId: widget.editPostId!,
          content: content,
          topicName: _selectedTopic,
          clearTopic: _selectedTopic == null,
          poll: poll,
          clearPoll: !_showPoll,
        );
        PostService.instance.upsertRemotePost(updated);
        // Keep local service in sync for owner checks.
        PostService.instance.updatePost(
          postId: widget.editPostId!,
          content: content,
          tags: _selectedTopic == null ? const [] : [_selectedTopic!],
          poll: updated.poll,
          clearPoll: updated.poll == null,
        );
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('글을 수정했어요.')),
        );
        Navigator.of(context).pop(true);
        return;
      } catch (e) {
        debugPrint('Firestore 글 수정 실패: $e');
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('글을 수정할 수 없어요.')),
        );
        return;
      }
    }

    final authorId = AuthService.instance.kakaoUserId;
    if (authorId == null ||
        authorId.isEmpty ||
        !AuthService.instance.canWriteContent) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이나 회원가입 후 글을 작성할 수 있어요.')),
      );
      return;
    }

    try {
      final remote = await PostsFirestoreService.instance.createPost(
        content: content,
        authorId: authorId,
        authorNickname: _nickname,
        experience: AuthService.instance.experience,
        cafeType: AuthService.instance.cafeType,
        topicName: _selectedTopic,
        poll: poll,
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
    } catch (e) {
      debugPrint('Firestore 글 저장 실패: $e');
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('글을 저장하지 못했어요. 다시 시도해주세요.')),
      );
    }
  }

  Widget _buildSelectedTopic() {
    final topic = _selectedTopic;
    if (topic == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
          decoration: BoxDecoration(
            color: colors.fill,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: GestureDetector(
                  onTap: _openTopicPicker,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    '주제: $topic',
                    style: CafeinTypography.topic(colors.onSurfaceVariant),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _clearTopic,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
                  child: Icon(Icons.close, size: 14, color: colors.muted),
                ),
              ),
            ],
          ),
        ),
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
          style: CafeinTypography.postBody(colors.mutedSoft),
        ),
        const SizedBox(height: 8),
        Text(
          '!을 입력해 주제를 정해보세요. (*주제 필수)',
          style: CafeinTypography.metadata(colors.muted),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _canSubmit;
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
          child: Text(
            '취소',
            style: CafeinTypography.button().copyWith(fontWeight: FontWeight.w400),
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
                style: CafeinTypography.button(
                  canSubmit ? colors.onSurface : colors.mutedSoft,
                ),
              ),
            ),
          ),
        ],
      ),
      body: DismissKeyboardOnTap(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      16,
                      AppSpacing.screenH,
                      24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSelectedTopic(),
                          Text(
                            _nickname,
                            style: CafeinTypography.nickname(colors.onSurface),
                          ),
                          const SizedBox(height: 12),
                          Stack(
                            alignment: Alignment.topLeft,
                            children: [
                              Theme(
                                data: Theme.of(context).copyWith(
                                  inputDecorationTheme:
                                      const InputDecorationTheme(
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
                                  style: CafeinTypography.postBody(colors.onSurface),
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
                          if (_showPoll) ...[
                            const SizedBox(height: 20),
                            KeyedSubtree(
                              key: _pollSectionKey,
                              child: _pollConfirmed
                                  ? _buildConfirmedPollPreview()
                                  : _buildPollEditor(),
                            ),
                          ],
                          // Extra tappable empty space so taps outside TextField
                          // dismiss the keyboard even when content is short.
                          SizedBox(
                            height: (constraints.maxHeight * 0.35)
                                .clamp(80.0, 280.0),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
      ),
    );
  }
}

