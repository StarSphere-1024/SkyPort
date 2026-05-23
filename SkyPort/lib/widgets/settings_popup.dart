import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/serial/serial_port_manager.dart';
import '../providers/serial/ui_settings_provider.dart';
import '../providers/theme_provider.dart';
import '../theme.dart';
import '../widgets/shared/compact_switch.dart';

class SettingsPopup extends ConsumerWidget {
  final TextEditingController controller;
  final GlobalKey<FormState> formKey;

  const SettingsPopup({
    super.key,
    required this.controller,
    required this.formKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serialState = ref.watch(serialPortManagerProvider);
    final serialManager = ref.read(serialPortManagerProvider.notifier);
    final uiSettings = ref.watch(uiSettingsProvider);

    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              AppLocalizations.of(context).theme,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            trailing: DropdownButton<ThemeMode>(
              value: ref.watch(themeModeProvider),
              onChanged: (ThemeMode? newMode) {
                if (newMode != null) {
                  ref.read(themeModeProvider.notifier).setThemeMode(newMode);
                }
              },
              items: [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(AppLocalizations.of(context).followSystem),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(AppLocalizations.of(context).light),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(AppLocalizations.of(context).dark),
                ),
              ],
            ),
          ),
          ListTile(
            title: Text(
              AppLocalizations.of(context).themeColor,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            trailing: DropdownButton<Color>(
              value: availableThemeColors.firstWhere(
                (c) => c.toARGB32() == ref.watch(themeColorProvider).toARGB32(),
                orElse: () => availableThemeColors.first,
              ),
              onChanged: (Color? newColor) {
                if (newColor != null) {
                  ref.read(themeColorProvider.notifier).setThemeColor(newColor);
                }
              },
              items: availableThemeColors.map((color) {
                return DropdownMenuItem(
                  value: color,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
              icon: const SizedBox.shrink(),
              underline: const SizedBox.shrink(),
            ),
          ),
          const Divider(),
          CompactSwitch(
            label: AppLocalizations.of(context).enableAnsi,
            value: uiSettings.enableAnsi,
            onChanged: (v) =>
                ref.read(uiSettingsProvider.notifier).setEnableAnsi(v),
          ),
          CompactSwitch(
            label: AppLocalizations.of(context).autoReconnect,
            value: serialState.targetConfig.autoReconnect,
            onChanged: serialManager.setAutoReconnect,
          ),
          ListTile(
            title: Text(
              AppLocalizations.of(context).logBufferSize,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            trailing: SizedBox(
              width: 120,
              child: TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  suffixText: 'MB',
                ),
                validator: (value) {
                  final size = int.tryParse(value ?? '');
                  if (size == null || size < 16 || size > 512) {
                    return AppLocalizations.of(context).logBufferSizeError;
                  }
                  return null;
                },
                onSaved: (value) {
                  final size = int.parse(value!);
                  ref.read(uiSettingsProvider.notifier).setLogBufferSize(size);
                },
                onFieldSubmitted: (value) {
                  if (formKey.currentState?.validate() == true) {
                    formKey.currentState?.save();
                  }
                },
              ),
            ),
          ),
          if (Theme.of(context).platform == TargetPlatform.windows ||
              Theme.of(context).platform == TargetPlatform.macOS ||
              Theme.of(context).platform == TargetPlatform.linux)
            ListTile(
              title: Text(
                AppLocalizations.of(context).exportPath,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final path =
                              await FilePicker.platform.getDirectoryPath();
                          if (path != null) {
                            ref
                                .read(uiSettingsProvider.notifier)
                                .setLogExportPath(path);
                          }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            hintText:
                                AppLocalizations.of(context).exportPathHint,
                            isDense: true,
                          ),
                          child: Text(
                            uiSettings.logExportPath.isEmpty
                                ? AppLocalizations.of(context).exportPathHint
                                : uiSettings.logExportPath,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder),
                      tooltip: AppLocalizations.of(context).exportPath,
                      onPressed: () async {
                        final path =
                            await FilePicker.platform.getDirectoryPath();
                        if (path != null) {
                          ref
                              .read(uiSettingsProvider.notifier)
                              .setLogExportPath(path);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
