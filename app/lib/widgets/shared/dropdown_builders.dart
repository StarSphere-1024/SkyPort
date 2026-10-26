import 'package:flutter/material.dart';

class DropdownBuilders {
  static List<DropdownMenuEntry<T>> createEntries<T>(
    List<T> values,
    String Function(T) labelBuilder,
  ) {
    return values
        .map(
          (value) =>
              DropdownMenuEntry<T>(value: value, label: labelBuilder(value)),
        )
        .toList();
  }

  static Widget buildDropdown<T>({
    required BuildContext context,
    required T? initialSelection,
    required List<DropdownMenuEntry<T>> entries,
    required String label,
    required ValueChanged<T?>? onSelected,
    Key? menuKey,
    bool enabled = true,
    String? hintText,
    String? errorText,
  }) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      gapPadding: 0,
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 125;
            return Semantics(
              label: label,
              child: DropdownMenu<T>(
                key: menuKey,
                expandedInsets: EdgeInsets.zero,
                initialSelection: initialSelection,
                dropdownMenuEntries: entries,
                onSelected: onSelected,
                enabled: enabled,
                requestFocusOnTap: false,
                textStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: compact ? 12 : 14,
                ),
                decorationBuilder: (context, controller) => InputDecoration(
                  hintText: hintText,
                  errorText: errorText,
                  suffixIcon: Icon(
                    controller.isOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                  ),
                ),
                inputDecorationTheme: InputDecorationThemeData(
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  border: border,
                  enabledBorder: border,
                  disabledBorder: border,
                  focusedBorder: border.copyWith(
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                  contentPadding: EdgeInsets.only(
                    left: compact ? 8 : 12,
                    top: 9,
                    bottom: 9,
                  ),
                  suffixIconConstraints: BoxConstraints(
                    minWidth: compact ? 20 : 28,
                    maxWidth: compact ? 20 : 28,
                    minHeight: 36,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
