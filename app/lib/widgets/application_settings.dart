import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/ui_controller.dart';
import '../providers/ui_settings_provider.dart';
import '../providers/theme_provider.dart';
import '../theme.dart';
import '../widgets/shared/compact_switch.dart';

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
    final labelStyle = TextStyle(color: Theme.of(context).colorScheme.primary);

    Future<void> chooseExportDirectory() async {
      final path = await getDirectoryPath();
      if (path != null) {
        ref.read(uiSettingsProvider.notifier).setLogExportPath(path);
      }
    }

    Widget labeledControl(String label, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 4),
          control,
        ],
      ),
    );

    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          labeledControl(
            localizations.theme,
            DropdownButton<ThemeMode>(
              isExpanded: true,
              borderRadius: BorderRadius.circular(12),
              value: ref.watch(themeModeProvider),
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
          labeledControl(
            localizations.themeColor,
            DropdownButton<Color>(
              isExpanded: true,
              borderRadius: BorderRadius.circular(12),
              value: availableThemeColors.firstWhere(
                (color) =>
                    color.toARGB32() ==
                    ref.watch(themeColorProvider).toARGB32(),
                orElse: () => availableThemeColors.first,
              ),
              onChanged: (color) {
                if (color != null) {
                  ref.read(themeColorProvider.notifier).setThemeColor(color);
                }
              },
              items: availableThemeColors.map((color) {
                return DropdownMenuItem(
                  value: color,
                  child: Align(
                    alignment: Alignment.centerLeft,
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
                  ),
                );
              }).toList(),
              icon: const SizedBox.shrink(),
              underline: const SizedBox.shrink(),
            ),
          ),
          const Divider(),
          CompactSwitch(
            label: localizations.enableAnsi,
            value: uiSettings.enableAnsi,
            onChanged: (value) =>
                ref.read(uiSettingsProvider.notifier).setEnableAnsi(value),
          ),
          CompactSwitch(
            label: localizations.autoReconnect,
            value: autoReconnect,
            onChanged: controllerNotifier.setAutoReconnect,
          ),
          labeledControl(
            localizations.logBufferSize,
            TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(suffixText: 'MB'),
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
          if (Theme.of(context).platform == TargetPlatform.windows ||
              Theme.of(context).platform == TargetPlatform.macOS ||
              Theme.of(context).platform == TargetPlatform.linux)
            labeledControl(
              localizations.exportPath,
              InkWell(
                onTap: chooseExportDirectory,
                child: InputDecorator(
                  decoration: InputDecoration(
                    hintText: localizations.exportPathHint,
                    isDense: true,
                    suffixIcon: const Icon(Icons.folder),
                  ),
                  child: Text(
                    uiSettings.logExportPath.isEmpty
                        ? localizations.exportPathHint
                        : uiSettings.logExportPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
