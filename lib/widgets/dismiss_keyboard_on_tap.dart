import 'package:flutter/material.dart';

/// Dismisses the soft keyboard on a **tap**, but not on a **scroll/drag**.
///
/// Uses a [Listener] (not a competing [GestureDetector]) so ScrollViews and
/// buttons keep winning the gesture arena. Movement beyond [_tapSlop] is
/// treated as a drag → keyboard stays open.
class DismissKeyboardOnTap extends StatefulWidget {
  const DismissKeyboardOnTap({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<DismissKeyboardOnTap> createState() => _DismissKeyboardOnTapState();
}

class _DismissKeyboardOnTapState extends State<DismissKeyboardOnTap> {
  static const double _tapSlop = 18;

  int? _activePointer;
  Offset? _downPosition;
  bool _dragged = false;

  void _clear() {
    _activePointer = null;
    _downPosition = null;
    _dragged = false;
  }

  /// True when the pointer-up landed on the currently focused field.
  bool _tapLandedOnPrimaryFocus(Offset globalPosition) {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return false;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final local = box.globalToLocal(globalPosition);
    return (Offset.zero & box.size).contains(local);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_activePointer != null) return;
        _activePointer = event.pointer;
        _downPosition = event.position;
        _dragged = false;
      },
      onPointerMove: (event) {
        if (event.pointer != _activePointer || _downPosition == null) return;
        if ((event.position - _downPosition!).distance > _tapSlop) {
          _dragged = true;
        }
      },
      onPointerUp: (event) {
        if (event.pointer != _activePointer) return;
        final wasDrag = _dragged ||
            (_downPosition != null &&
                (event.position - _downPosition!).distance > _tapSlop);
        final pos = event.position;
        _clear();
        if (wasDrag) return;
        // Keep keyboard if the user tapped the focused TextField itself.
        if (_tapLandedOnPrimaryFocus(pos)) return;
        FocusManager.instance.primaryFocus?.unfocus();
      },
      onPointerCancel: (event) {
        if (event.pointer == _activePointer) _clear();
      },
      child: widget.child,
    );
  }
}
