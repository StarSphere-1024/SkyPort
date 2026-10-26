import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/app_localizations.dart';
import '../services/app_logger.dart';

/// Native hit testing uses the same 48px bar and 46px caption-button widths.
class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({required this.child, super.key});
  final Widget child;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame> {
  static const _channel = MethodChannel('skyport/window');
  ({String title, bool dark})? _configuration;
  ({bool maximized, bool active, bool maximizeHovered}) _window = (
    maximized: false,
    active: true,
    maximizeHovered: false,
  );
  bool _scheduled = false;

  bool get _supported => Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    if (_supported) {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'windowState') throw MissingPluginException();
        _updateWindow(call.arguments as Map);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_supported) return;
    final configuration = (
      title: AppLocalizations.of(context).appTitle,
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    if (_configuration == configuration) return;
    _configuration = configuration;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_configure());
    });
  }

  Future<void> _configure() async {
    final configuration = _configuration!;
    final result = await _invoke('configure', {
      'title': configuration.title,
      'dark': configuration.dark,
    });
    if (result != null && mounted) _updateWindow(result as Map);
  }

  void _updateWindow(Map value) {
    if (!mounted) return;
    final window = (
      maximized: value['maximized'] as bool,
      active: value['active'] as bool,
      maximizeHovered: value['maximizeHovered'] as bool,
    );
    if (_window != window) setState(() => _window = window);
  }

  Future<Object?> _invoke(String method, [Map<String, Object>? args]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on PlatformException catch (error, stackTrace) {
      AppLogger.instance.error(
        'Native window action failed: $method',
        error: error,
        stackTrace: stackTrace,
      );
    } on MissingPluginException catch (error, stackTrace) {
      AppLogger.instance.error(
        'Native window channel is unavailable: $method',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }

  @override
  void dispose() {
    if (_supported) _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return widget.child;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final foreground = _window.active
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return Overlay.wrap(
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surfaceContainerLow,
            child: SizedBox(
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: SvgPicture.asset(
                        'assets/icon.svg',
                        width: 24,
                        height: 24,
                        excludeFromSemantics: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.appTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: foreground,
                        ),
                      ),
                    ),
                    _CaptionButton(
                      label: l10n.windowMinimize,
                      icon: Icons.remove,
                      foreground: foreground,
                      onPressed: () => unawaited(_invoke('minimize')),
                    ),
                    _CaptionButton(
                      label: _window.maximized
                          ? l10n.windowRestore
                          : l10n.windowMaximize,
                      icon: _window.maximized
                          ? Icons.filter_none
                          : Icons.crop_square,
                      foreground: foreground,
                      nativeHovered: _window.maximizeHovered,
                      onPressed: () => unawaited(_invoke('toggleMaximize')),
                    ),
                    _CaptionButton(
                      label: l10n.windowClose,
                      icon: Icons.close,
                      foreground: foreground,
                      isClose: true,
                      onPressed: () => unawaited(_invoke('close')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.onPressed,
    this.nativeHovered = false,
    this.isClose = false,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final VoidCallback onPressed;
  final bool nativeHovered;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    final hover = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.1);
    return SizedBox(
      width: 46,
      height: 48,
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (isClose &&
                (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed))) {
              return Colors.white;
            }
            return foreground;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (isClose &&
                (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed))) {
              return const Color(0xffc42b1c);
            }
            return nativeHovered ? hover : Colors.transparent;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (isClose &&
                (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed))) {
              return Colors.transparent;
            }
            return null;
          }),
        ),
      ),
    );
  }
}
