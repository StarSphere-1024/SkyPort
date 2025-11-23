import 'package:flutter/material.dart';

class AppInputDecorations {
  static InputDecoration dense({
    required BuildContext context,
    required String label,
    String? errorText,
    String? suffixText,
    TextStyle? suffixStyle,
    bool filled = false,
    Color? fillColor,
    BorderRadius? borderRadius,
    double borderWidth = 1.0,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      isDense: true,
      suffixText: suffixText,
      suffixStyle: suffixStyle ??
          TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
      filled: filled,
      fillColor: fillColor ?? colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(4),
        borderSide: BorderSide(
          color: colorScheme.outline,
          width: borderWidth,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(4),
        borderSide: BorderSide(
          color: colorScheme.outline,
          width: borderWidth,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(4),
        borderSide: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.5),
          width: borderWidth,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(4),
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: 2,
        ),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
      errorText: errorText,
    );
  }
}
