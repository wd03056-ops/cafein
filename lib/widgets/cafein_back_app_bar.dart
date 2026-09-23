import 'package:flutter/material.dart';

/// AppBar for pushed routes (back + title).
///
/// Default Material leading slot is 56px wide, so even with [titleSpacing]
/// 0 the title sits far from ←. Use a compact leading + zero spacing.
class CafeinBackAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CafeinBackAppBar({
    super.key,
    required this.title,
    this.actions,
    this.onBack,
  });

  final String title;
  final List<Widget>? actions;

  /// When set, replaces the default [Navigator.maybePop] back action.
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      leadingWidth: 40,
      leading: IconButton(
        onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
      title: Text(title),
      actions: actions,
    );
  }
}
