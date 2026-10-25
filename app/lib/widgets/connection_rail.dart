import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class ConnectionRail extends StatelessWidget {
  const ConnectionRail({
    super.key,
    required this.panelOpen,
    required this.settingsSelected,
    required this.onSerial,
    required this.onSettings,
  });

  static const double width = 80;

  final bool panelOpen;
  final bool settingsSelected;
  final VoidCallback onSerial;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      width: width,
      child: Column(
        children: [
          const SizedBox(height: 12),
          _RailEntry(
            icon: Icons.cable,
            label: l10n.serialPageLabel,
            selected: panelOpen && !settingsSelected,
            onPressed: onSerial,
          ),
          const SizedBox(height: 8),
          _RailEntry(
            icon: Icons.settings_outlined,
            label: l10n.settingsPageLabel,
            selected: panelOpen && settingsSelected,
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

class _RailEntry extends StatefulWidget {
  const _RailEntry({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_RailEntry> createState() => _RailEntryState();
}

class _RailEntryState extends State<_RailEntry> {
  final _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = widget.selected ? colors.onSecondaryContainer : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: widget.selected ? colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Tooltip(
          key: _tooltipKey,
          message: widget.label,
          child: Semantics(
            button: true,
            selected: widget.selected,
            child: InkWell(
              onTap: widget.onPressed,
              onFocusChange: (focused) {
                if (focused) {
                  _tooltipKey.currentState?.ensureTooltipVisible();
                } else {
                  Tooltip.dismissAllToolTips();
                }
              },
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon, color: foreground),
                    const SizedBox(height: 3),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
