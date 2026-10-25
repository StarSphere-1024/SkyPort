import 'package:flutter/material.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: trailing == null ? 0 : 12,
              bottom: 8,
            ),
            child: Semantics(
              header: true,
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: colors.primary),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: trailing!,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Material(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 12,
                      endIndent: 12,
                      color: colors.outlineVariant,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
