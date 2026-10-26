import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import 'shared/settings_section.dart';

class AboutPanel extends StatefulWidget {
  const AboutPanel({super.key});

  @override
  State<AboutPanel> createState() => _AboutPanelState();
}

class _AboutPanelState extends State<AboutPanel> {
  static final _projectUri = Uri.https(
    'github.com',
    '/StarSphere-1024/SkyPort',
  );
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  Future<void> _openProject() async {
    try {
      if (await launchUrl(_projectUri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // The URL remains selectable when the platform cannot open a browser.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).projectLinkOpenFailed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SvgPicture.asset(
                'assets/icon.svg',
                width: 80,
                height: 80,
                excludeFromSemantics: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.appTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FutureBuilder<PackageInfo>(
                future: _packageInfo,
                builder: (context, snapshot) => _Badge(
                  label: snapshot.hasData
                      ? 'v${snapshot.data!.version}'
                      : snapshot.hasError
                      ? l10n.unavailable
                      : '…',
                  background: colors.primaryContainer,
                  foreground: colors.onPrimaryContainer,
                ),
              ),
              _Badge(
                label: 'AGPL-3.0',
                background: colors.surfaceContainerHigh,
                foreground: colors.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            l10n.aboutDescription,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          SettingsSection(
            title: l10n.aboutMore,
            children: [
              Material(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _openProject,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.code_rounded,
                                size: 20,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.projectLink,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 20,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          'github.com/StarSphere-1024/SkyPort',
                          onTap: _openProject,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
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

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: foreground),
      ),
    ),
  );
}
