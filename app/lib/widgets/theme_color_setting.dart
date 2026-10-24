import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/theme_provider.dart';

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

class ThemeColorSetting extends ConsumerWidget {
  const ThemeColorSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = ref.watch(themeColorProvider);
    final l10n = AppLocalizations.of(context);
    final presets = [
      (Colors.blue, l10n.themeBlue),
      (Colors.red, l10n.themeRed),
      (Colors.green, l10n.themeGreen),
      (Colors.teal, l10n.themeTeal),
      (Colors.indigo, l10n.themeIndigo),
      (const Color(0xff6750a4), l10n.themeViolet),
      (Colors.pink, l10n.themePink),
      (Colors.yellow, l10n.themeYellow),
      (Colors.orange, l10n.themeOrange),
    ];
    final preset = presets.where(
      (entry) => entry.$1.toARGB32() == seed.toARGB32(),
    );
    final custom = preset.isEmpty;
    final name = custom ? l10n.customSeedColor : preset.first.$2;

    return Tooltip(
      message: _hex(seed),
      child: ListTile(
        key: const ValueKey('theme-color-scheme'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        minTileHeight: 64,
        minLeadingWidth: 20,
        horizontalTitleGap: 12,
        leading: Icon(
          Icons.palette_rounded,
          size: 24,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(
          l10n.themeColor,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        subtitle: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () async {
          final chosen = await showDialog<Color>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(l10n.colorScheme),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (color, label) in presets)
                        _SchemeTile(
                          key: ValueKey('theme-preset-${color.toARGB32()}'),
                          seed: color,
                          label: label,
                          selected: color.toARGB32() == seed.toARGB32(),
                          onTap: () => Navigator.pop(dialogContext, color),
                        ),
                      _SchemeTile(
                        key: const ValueKey('theme-custom-color'),
                        seed: seed,
                        label: l10n.customSeedColor,
                        subtitle: custom ? _hex(seed) : null,
                        selected: custom,
                        onTap: () async {
                          final color = await showDialog<Color>(
                            context: dialogContext,
                            builder: (_) => _CustomColorDialog(initial: seed),
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, color);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
              ],
            ),
          );
          if (chosen != null && context.mounted) {
            ref.read(themeColorProvider.notifier).setThemeColor(chosen);
          }
        },
      ),
    );
  }
}

class _SchemeTile extends StatelessWidget {
  const _SchemeTile({
    super.key,
    required this.seed,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final Color seed;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accessibleLabel = subtitle == null ? label : '$label, $subtitle';
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: accessibleLabel,
      child: Tooltip(
        message: accessibleLabel,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 82,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: _SchemePreview(seed: seed, size: 42),
                        ),
                      ),
                      if (selected)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox(
                            width: 25,
                            height: 25,
                            child: Icon(
                              Icons.check_rounded,
                              color: colors.onPrimary,
                              size: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SchemePreview extends StatelessWidget {
  const _SchemePreview({required this.seed, this.size = 48});
  final Color seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Theme.of(context).brightness,
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: Column(
            children: [
              Expanded(
                child: ColoredBox(
                  color: scheme.primary,
                  child: const SizedBox.expand(),
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ColoredBox(color: scheme.secondaryContainer),
                    ),
                    Expanded(child: ColoredBox(color: scheme.tertiary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({required this.initial});
  final Color initial;

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late Color _draft;
  late final TextEditingController _controller;
  bool _valid = true;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial.withValues(alpha: 1);
    _controller = TextEditingController(text: _hex(_draft));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _editHex(String input) {
    final text = input.trim();
    setState(() {
      _valid = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text);
      if (_valid) {
        _draft = Color(0xff000000 | int.parse(text.substring(1), radix: 16));
      }
    });
  }

  void _editChannel(int shift, double value) {
    setState(() {
      final argb = _draft.toARGB32();
      _draft = Color((argb & ~(0xff << shift)) | (value.round() << shift));
      _valid = true;
      _controller.value = TextEditingValue(
        text: _hex(_draft),
        selection: const TextSelection.collapsed(offset: 7),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final argb = _draft.toARGB32();
    return AlertDialog(
      title: Text(l10n.customSeedColor),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _draft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _SchemePreview(seed: _draft),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_hex(_draft))),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('theme-color-hex'),
                controller: _controller,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.seedColorHex,
                  border: const OutlineInputBorder(),
                  errorText: _valid ? null : l10n.seedColorHexError,
                  errorMaxLines: 3,
                ),
                onChanged: _editHex,
              ),
              const SizedBox(height: 12),
              for (final (id, label, shift, color) in [
                ('red', l10n.colorChannelRed, 16, Colors.red),
                ('green', l10n.colorChannelGreen, 8, Colors.green),
                ('blue', l10n.colorChannelBlue, 0, Colors.blue),
              ]) ...[
                Text('$label · ${(argb >> shift) & 0xff}'),
                Slider(
                  key: ValueKey('theme-color-$id'),
                  value: ((argb >> shift) & 0xff).toDouble(),
                  max: 255,
                  divisions: 255,
                  activeColor: color,
                  label: '${(argb >> shift) & 0xff}',
                  semanticFormatterCallback: (value) =>
                      '$label ${value.round()}',
                  onChanged: (value) => _editChannel(shift, value),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('theme-color-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const ValueKey('theme-color-apply'),
          onPressed: _valid ? () => Navigator.pop(context, _draft) : null,
          child: Text(l10n.applyColor),
        ),
      ],
    );
  }
}
