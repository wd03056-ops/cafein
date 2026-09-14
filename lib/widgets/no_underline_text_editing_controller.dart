import 'package:flutter/material.dart';

/// Keeps Hangul/CJK IME composing working, without drawing the
/// default composing underline under in-progress characters.
class NoUnderlineTextEditingController extends TextEditingController {
  NoUnderlineTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = (style ?? const TextStyle()).copyWith(
      decoration: TextDecoration.none,
      decorationThickness: 0,
    );

    // Must keep composing range rendering for Korean IME.
    // Only skip the underline decoration that Flutter adds by default.
    if (!value.isComposingRangeValid || !withComposing) {
      return TextSpan(style: baseStyle, text: text);
    }

    final composingStyle = baseStyle.merge(
      const TextStyle(
        decoration: TextDecoration.none,
        decorationThickness: 0,
      ),
    );

    return TextSpan(
      style: baseStyle,
      children: [
        TextSpan(text: value.composing.textBefore(value.text)),
        TextSpan(
          style: composingStyle,
          text: value.composing.textInside(value.text),
        ),
        TextSpan(text: value.composing.textAfter(value.text)),
      ],
    );
  }
}
