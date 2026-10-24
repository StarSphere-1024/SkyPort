import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/ui_controller.dart';
import '../providers/ui_settings_provider.dart';
import '../providers/theme_provider.dart';
import '../theme.dart';

class ApplicationSettings extends ConsumerWidget {
  final TextEditingController controller;
  final GlobalKey<FormState> formKey;

  const ApplicationSettings({
    super.key,
    required this.controller,
    required this.formKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final autoReconnect = ref.watch(
      uiControllerProvider.select((state) => state.autoReconnect),
    );
    final controllerNotifier = ref.read(uiControllerProvider.notifier);
    final uiSettings = ref.watch(uiSettingsProvider);
    final themeColor = ref.watch(themeColorProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Future<void> chooseExportDirectory() async {
      final path = await getDirectoryPath();
      if (path != null) {
        ref.read(uiSettingsProvider.notifier).setLogExportPath(path);
      }
    }

    Widget settingRow({
      required IconData icon,
      required String title,
      Widget? control,
      Widget? trailing,
      VoidCallback? onTap,
    }) {
      final content = Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colors.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.bodyMedium)),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
            if (control != null) ...[const SizedBox(height: 8), control],
          ],
        ),
      );
      return onTap == null
          ? content
          : MergeSemantics(
              child: InkWell(onTap: onTap, child: content),
            );
    }

    Widget section(String title, List<Widget> rows) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                ),
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
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 12,
                      endIndent: 12,
                      color: colors.outlineVariant,
                    ),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section(localizations.settingsAppearance, [
            settingRow(
              icon: Icons.brightness_6_outlined,
              title: localizations.theme,
              control: DropdownButton<ThemeMode>(
                value: ref.watch(themeModeProvider),
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                underline: const SizedBox.shrink(),
                onChanged: (mode) {
                  if (mode != null) {
                    ref.read(themeModeProvider.notifier).setThemeMode(mode);
                  }
                },
                items: [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text(localizations.followSystem),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text(localizations.light),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text(localizations.dark),
                  ),
                ],
              ),
            ),
            settingRow(
              icon: Icons.palette_outlined,
              title: localizations.themeColor,
              control: Wrap(
                spacing: 2,
                runSpacing: 4,
                children: availableThemeColors.map((color) {
                  final selected = color.toARGB32() == themeColor.toARGB32();
                  return Semantics(
                    inMutuallyExclusiveGroup: true,
                    selected: selected,
                    child: IconButton(
                      tooltip:
                          '${localizations.themeColor} #${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                      isSelected: selected,
                      onPressed: () => ref
                          .read(themeColorProvider.notifier)
                          .setThemeColor(color),
                      icon: Container(
                        width: 32,
                        height: 32,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? colors.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ]),
          section(localizations.settingsConnection, [
            settingRow(
              icon: Icons.sync_rounded,
              title: localizations.autoReconnect,
              onTap: () => controllerNotifier.setAutoReconnect(!autoReconnect),
              trailing: Switch(
                value: autoReconnect,
                onChanged: controllerNotifier.setAutoReconnect,
              ),
            ),
          ]),
          section(localizations.settingsLogs, [
            settingRow(
              icon: Icons.terminal_rounded,
              title: localizations.enableAnsi,
              onTap: () => ref
                  .read(uiSettingsProvider.notifier)
                  .setEnableAnsi(!uiSettings.enableAnsi),
              trailing: Switch(
                value: uiSettings.enableAnsi,
                onChanged: (value) =>
                    ref.read(uiSettingsProvider.notifier).setEnableAnsi(value),
              ),
            ),
            settingRow(
              icon: Icons.storage_outlined,
              title: localizations.logBufferSize,
              control: TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.start,
                decoration: InputDecoration(
                  labelText: localizations.logBufferSize,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  suffixText: 'MB',
                  isDense: true,
                  helperText: localizations.logBufferSizeHint,
                  helperMaxLines: 2,
                ),
                validator: (value) {
                  final size = int.tryParse(value ?? '');
                  if (size == null || size < 16 || size > 512) {
                    return localizations.logBufferSizeError;
                  }
                  return null;
                },
                onSaved: (value) {
                  controllerNotifier.setLogCapacity(int.parse(value!));
                },
                onFieldSubmitted: (_) {
                  final form = formKey.currentState;
                  if (form?.validate() == true) form!.save();
                },
              ),
            ),
            if (theme.platform == TargetPlatform.windows ||
                theme.platform == TargetPlatform.macOS ||
                theme.platform == TargetPlatform.linux)
              settingRow(
                icon: Icons.folder_outlined,
                title: localizations.exportPath,
                control: Tooltip(
                  message: uiSettings.logExportPath.isEmpty
                      ? localizations.exportPathHint
                      : uiSettings.logExportPath,
                  child: OutlinedButton(
                    onPressed: chooseExportDirectory,
                    style: OutlinedButton.styleFrom(
                      alignment: AlignmentDirectional.centerStart,
                      padding: const EdgeInsets.all(12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            uiSettings.logExportPath.isEmpty
                                ? localizations.exportPathHint
                                : uiSettings.logExportPath,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}
