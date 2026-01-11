import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../providers/serial/ui_settings_provider.dart';
import '../providers/serial/serial_config_provider.dart';
import '../l10n/app_localizations.dart';
import '../widgets/shared/compact_switch.dart';
import '../theme.dart';

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
              'Theme Color',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            trailing: DropdownButton<Color>(
              value: availableThemeColors.firstWhere(
                (c) => c.value == ref.watch(themeColorProvider).value,
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
              icon: const SizedBox
                  .shrink(), // Hide the arrow icon to save space if needed, or keep it.
              // Actually keeping the arrow is standard.
              underline: const SizedBox.shrink(), // Remove underline
            ),
          ),
          const Divider(),
          CompactSwitch(
            label: AppLocalizations.of(context).enableAnsi,
            value: ref.watch(uiSettingsProvider).enableAnsi,
            onChanged: (v) =>
                ref.read(uiSettingsProvider.notifier).setEnableAnsi(v),
          ),
          CompactSwitch(
            label: AppLocalizations.of(context).autoReconnect,
            value: ref.watch(serialConfigProvider)?.autoReconnect ?? true,
            onChanged: (v) =>
                ref.read(serialConfigProvider.notifier).setAutoReconnect(v),
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
                  int? size = int.tryParse(value ?? '');
                  if (size == null || size < 16 || size > 512) {
                    return AppLocalizations.of(context).logBufferSizeError;
                  }
                  return null;
                },
                onSaved: (value) {
                  int size = int.parse(value!);
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
        ],
      ),
    );
  }
}
