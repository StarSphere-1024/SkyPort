import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/ui_controller.dart';
import '../providers/ui_settings_provider.dart';
import '../providers/theme_provider.dart';
import 'shared/settings_section.dart';
import 'theme_color_setting.dart';

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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dynamicColorEnabled = ref.watch(dynamicColorEnabledProvider);
    final manualSeed = ref.watch(themeColorProvider);
    final hasManualSeed = ref.watch(hasManualThemeColorProvider);
    final systemAccent = ref.watch(systemAccentColorProvider);
    final showManualColor =
        resolveThemeColor(
          dynamicEnabled: dynamicColorEnabled,
          manualSeed: hasManualSeed ? manualSeed : null,
          systemAccent: systemAccent,
          brightness: theme.brightness,
        ).source !=
        ThemeColorSource.system;

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

    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSection(
            title: localizations.settingsAppearance,
            children: [
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
              if (theme.platform == TargetPlatform.windows ||
                  theme.platform == TargetPlatform.linux)
                settingRow(
                  icon: Icons.color_lens_outlined,
                  title: localizations.dynamicColor,
                  trailing: Switch(
                    key: const ValueKey('dynamic-color-switch'),
                    value: dynamicColorEnabled,
                    onChanged: (enabled) async {
                      try {
                        await ref
                            .read(dynamicColorEnabledProvider.notifier)
                            .setEnabled(enabled);
                      } catch (error, stackTrace) {
                        FlutterError.reportError(
                          FlutterErrorDetails(
                            exception: error,
                            stack: stackTrace,
                            library: 'SkyPort theme settings',
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(localizations.themeColorSaveFailed),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              if (showManualColor) const ThemeColorSetting(),
            ],
          ),
          SettingsSection(
            title: localizations.settingsConnection,
            children: [
              settingRow(
                icon: Icons.sync_rounded,
                title: localizations.autoReconnect,
                onTap: () =>
                    controllerNotifier.setAutoReconnect(!autoReconnect),
                trailing: Switch(
                  key: const ValueKey('auto-reconnect-switch'),
                  value: autoReconnect,
                  onChanged: controllerNotifier.setAutoReconnect,
                ),
              ),
            ],
          ),
          SettingsSection(
            title: localizations.settingsLogs,
            children: [
              settingRow(
                icon: Icons.terminal_rounded,
                title: localizations.enableAnsi,
                onTap: () => ref
                    .read(uiSettingsProvider.notifier)
                    .setEnableAnsi(!uiSettings.enableAnsi),
                trailing: Switch(
                  value: uiSettings.enableAnsi,
                  onChanged: (value) => ref
                      .read(uiSettingsProvider.notifier)
                      .setEnableAnsi(value),
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
            ],
          ),
        ],
      ),
    );
  }
}
