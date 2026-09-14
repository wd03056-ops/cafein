import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../services/post_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'no_underline_text_editing_controller.dart';

/// Topic search / create sheet — opened via "!" on write screen.
class TopicPickerSheet extends StatefulWidget {
  const TopicPickerSheet({
    super.key,
    this.initialTopic,
    this.title = '주제 선택',
    this.hintText = '주제를 검색해보세요',
    this.showClearOption = false,
  });

  final String? initialTopic;
  final String title;
  final String hintText;
  final bool showClearOption;

  static Future<String?> show(
    BuildContext context, {
    String? initialTopic,
    String title = '주제 선택',
    String hintText = '주제를 검색해보세요',
    bool showClearOption = false,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => TopicPickerSheet(
        initialTopic: initialTopic,
        title: title,
        hintText: hintText,
        showClearOption: showClearOption,
      ),
    );
  }

  @override
  State<TopicPickerSheet> createState() => _TopicPickerSheetState();
}

class _TopicPickerSheetState extends State<TopicPickerSheet> {
  late final TextEditingController _controller;
  final _postService = PostService.instance;

  @override
  void initState() {
    super.initState();
    _controller = NoUnderlineTextEditingController(
      text: widget.initialTopic ?? '',
    );
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _query => _controller.text.trim();

  List<Topic> get _results {
    // Empty query → topics ranked by post count (popularity).
    if (_query.isEmpty) {
      return _postService.popularTopics(limit: 12);
    }
    return _postService.searchTopics(_query, limit: 12);
  }

  bool get _canCreateNew {
    final q = _query;
    if (q.isEmpty) return false;
    return !_results.any((t) => t.name == q);
  }

  void _select(String topic) {
    Navigator.pop(context, topic);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Material(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.hairline,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    16,
                    AppSpacing.screenH,
                    0,
                  ),
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    14,
                    AppSpacing.screenH,
                    8,
                  ),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (value) {
                      final q = value.trim();
                      if (q.isNotEmpty) _select(q);
                    },
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
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        color: colors.mutedSoft,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 22,
                        color: colors.muted,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () => _controller.clear(),
                              icon: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: colors.muted,
                              ),
                            ),
                      filled: true,
                      fillColor: colors.fill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      8,
                      AppSpacing.screenH,
                      28,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (_query.isEmpty) ...[
                              const Icon(
                                Icons.local_fire_department_rounded,
                                size: 16,
                                color: Color(0xFFFF5A1F),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              _query.isEmpty ? '인기 주제' : '검색 결과',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (results.isEmpty && !_canCreateNew)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              '아직 등록된 주제가 없어요.\n검색해서 새 주제를 만들어 보세요.',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                height: 1.5,
                                color: colors.muted,
                              ),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final topic in results)
                                _TopicChip(
                                  label: topic.name,
                                  selected:
                                      topic.name == widget.initialTopic,
                                  onTap: () => _select(topic.name),
                                ),
                              if (_canCreateNew)
                                _TopicChip(
                                  label: '“$_query” 만들기',
                                  emphasized: true,
                                  onTap: () => _select(_query),
                                ),
                              if (widget.showClearOption &&
                                  (widget.initialTopic?.trim().isNotEmpty ??
                                      false))
                                _TopicChip(
                                  label: '주제 없음',
                                  muted: true,
                                  onTap: () => _select(''),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.emphasized = false,
    this.muted = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool emphasized;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final Color bg;
    final Color fg;
    final FontWeight weight;

    if (selected || emphasized) {
      bg = colors.onSurface;
      fg = colors.surface;
      weight = FontWeight.w600;
    } else if (muted) {
      bg = colors.fill;
      fg = colors.muted;
      weight = FontWeight.w500;
    } else {
      bg = colors.fill;
      fg = colors.onSurface;
      weight = FontWeight.w500;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: weight,
              letterSpacing: -0.2,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
