import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/connection_status.dart';
import '../../models/ui_settings.dart';
import '../../providers/common_providers.dart';
import '../../providers/serial/serial_port_manager.dart';
import '../../providers/serial/ui_settings_provider.dart';
import '../../utils/constants.dart';

class SendInputWidget extends ConsumerStatefulWidget {
  const SendInputWidget({super.key});

  @override
  ConsumerState<SendInputWidget> createState() => _SendInputWidgetState();
}

class _SendInputWidgetState extends ConsumerState<SendInputWidget> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _sendController = TextEditingController();
  late FocusNode _focusNode;
  bool _canSend = false;
  bool _previousHexMode = false;

  static const String _historyKey = 'send_input_history';
  List<String> _history = [];
  int _historyIndex = -1;
  String _tempInput = '';

  Timer? _autoSendTimer;
  UiSettings? _previousSettings;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    _loadHistory();
  }

  @override
  void dispose() {
    _autoSendTimer?.cancel();
    _sendController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final history = prefs.getStringList(_historyKey);
    if (mounted) {
      setState(() {
        _history = history ?? [];
      });
    }
  }

  Future<void> _saveHistory() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList(_historyKey, _history);
  }

  void _addToHistory(String text) {
    if (text.isEmpty) return;
    setState(() {
      _history.remove(text);
      _history.add(text);
      if (_history.length > SkyPortConstants.maxHistorySize) {
        _history.removeAt(0);
      }
      _historyIndex = -1;
      _tempInput = '';
    });
    _saveHistory();
  }

  void _handleAutoSendSettingsChange(UiSettings? previous, UiSettings next) {
    final wasEnabled = previous?.autoSendEnabled ?? false;
    final isEnabled = next.autoSendEnabled;

    if (wasEnabled != isEnabled) {
      if (isEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _startAutoSend();
          }
        });
      } else {
        _stopAutoSend();
      }
    } else if (isEnabled &&
        previous?.autoSendIntervalMs != next.autoSendIntervalMs) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startAutoSend();
        }
      });
    }
  }

  void _startAutoSend() {
    _autoSendTimer?.cancel();
    final interval = ref.read(uiSettingsProvider).autoSendIntervalMs;
    _autoSendTimer = Timer.periodic(
      Duration(milliseconds: interval),
      (_) => _autoSend(),
    );
  }

  void _stopAutoSend() {
    _autoSendTimer?.cancel();
    _autoSendTimer = null;
  }

  void _autoSend() {
    final connectionState =
        ref.read(serialPortManagerProvider).connection.state;
    if (connectionState == ConnectionState.connected && _canSend) {
      final text = _sendController.text;
      if (_formKey.currentState?.validate() ?? false) {
        ref.read(serialPortManagerProvider.notifier).send(text);
        _addToHistory(text);
      }
    }
  }

  void _navigateHistory(bool up) {
    if (_history.isEmpty) return;

    setState(() {
      if (up) {
        if (_historyIndex == -1) {
          _tempInput = _sendController.text;
          _historyIndex = _history.length - 1;
        } else if (_historyIndex > 0) {
          _historyIndex--;
        }
      } else if (_historyIndex != -1) {
        if (_historyIndex < _history.length - 1) {
          _historyIndex++;
        } else {
          _historyIndex = -1;
        }
      }

      final newText =
          _historyIndex == -1 ? _tempInput : _history[_historyIndex];
      _sendController.text = newText;
      _sendController.selection = TextSelection.fromPosition(
        TextPosition(offset: newText.length),
      );
      _updateCanSend(newText);
    });
  }

  void _updateCanSend(String value) {
    final uiSettings = ref.read(uiSettingsProvider);
    if (!uiSettings.hexSend) {
      _canSend = value.isNotEmpty;
      return;
    }

    if (value.isEmpty) {
      _canSend = false;
      return;
    }

    final sanitized = _sanitizeHex(value);
    if (sanitized.isEmpty) {
      _canSend = true;
    } else {
      _canSend = _isValidHex(sanitized);
    }
  }

  static final RegExp hexRegex = RegExp(r'^[0-9a-fA-F]+$');
  static final RegExp whitespaceRegex = RegExp(r'\s+');

  String _sanitizeHex(String value) => value.replaceAll(whitespaceRegex, '');

  bool _isValidHex(String sanitized) =>
      hexRegex.hasMatch(sanitized) && sanitized.length % 2 == 0;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final text = _sendController.text;
      final selection = _sendController.selection;
      if (selection.isCollapsed && selection.baseOffset >= 0) {
        final textBefore = text.substring(0, selection.baseOffset);
        if (!textBefore.contains('\n')) {
          _navigateHistory(true);
          return KeyEventResult.handled;
        }
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final text = _sendController.text;
      final selection = _sendController.selection;
      if (selection.isCollapsed && selection.baseOffset >= 0) {
        final textAfter = text.substring(selection.baseOffset);
        if (!textAfter.contains('\n')) {
          _navigateHistory(false);
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  Widget _buildTextField(bool hexSend, AppLocalizations l10n) {
    return TextFormField(
      controller: _sendController,
      focusNode: _focusNode,
      style: const TextStyle(fontFamily: 'monospace'),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: l10n.enterDataToSend,
        isDense: true,
      ),
      keyboardType: TextInputType.multiline,
      minLines: 1,
      maxLines: 5,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (value) {
        setState(() {
          _updateCanSend(value);
          if (_historyIndex != -1 && value != _history[_historyIndex]) {
            _historyIndex = -1;
          }
        });
      },
      validator: (value) {
        if (hexSend) {
          if (value == null || value.isEmpty) return null;
          final sanitized = _sanitizeHex(value);
          if (sanitized.isEmpty) return null;
          if (!hexRegex.hasMatch(sanitized)) {
            return l10n.invalidHexChars;
          }
          if (sanitized.length % 2 != 0) {
            return l10n.hexEvenLength;
          }
        }
        return null;
      },
    );
  }

  Widget _buildSendButton(ConnectionState connectionState, bool canSend) {
    return FilledButton.icon(
      icon: const Icon(Icons.send),
      label: Text(AppLocalizations.of(context).send),
      onPressed: connectionState == ConnectionState.connected && canSend
          ? () {
              if (_formKey.currentState!.validate()) {
                final text = _sendController.text;
                ref.read(serialPortManagerProvider.notifier).send(text);
                _addToHistory(text);
              }
            }
          : null,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionState =
        ref.watch(serialPortManagerProvider.select((s) => s.connection.state));
    final uiSettings = ref.watch(uiSettingsProvider);
    final hexSend = uiSettings.hexSend;

    if (_previousHexMode != hexSend) {
      _handleHexSendToggle(
        previousIsHex: _previousHexMode,
        currentIsHex: hexSend,
      );
      _previousHexMode = hexSend;
    }

    _handleAutoSendSettingsChange(_previousSettings, uiSettings);
    _previousSettings = uiSettings;

    final colorScheme = Theme.of(context).colorScheme;

    return Card.filled(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _buildTextField(hexSend, AppLocalizations.of(context)),
              ),
              const SizedBox(width: 8),
              _buildSendButton(connectionState, _canSend),
            ],
          ),
        ),
      ),
    );
  }

  void _handleHexSendToggle({
    required bool previousIsHex,
    required bool currentIsHex,
  }) {
    final text = _sendController.text;
    if (text.isEmpty) {
      return;
    }

    if (!previousIsHex && currentIsHex) {
      final bytes = utf8.encode(text);
      final hex = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      _sendController.text = hex;
      _sendController.selection = TextSelection.fromPosition(
        TextPosition(offset: _sendController.text.length),
      );
      _canSend = hex.isNotEmpty;
      return;
    }

    if (previousIsHex && !currentIsHex) {
      final hexText = text.trim();
      if (hexText.isEmpty) {
        _sendController.clear();
        _canSend = false;
        return;
      }

      try {
        final bytes = _parseHexToBytes(hexText);
        final decoded = utf8.decode(bytes, allowMalformed: false);
        _sendController.text = decoded;
        _sendController.selection = TextSelection.fromPosition(
          TextPosition(offset: decoded.length),
        );
        _canSend = decoded.isNotEmpty;
      } catch (_) {
        // Keep original content when conversion fails.
      }
    }
  }

  Uint8List _parseHexToBytes(String hex) {
    final bytes = <int>[];
    final parts = hex.trim().split(whitespaceRegex).where((s) => s.isNotEmpty);

    for (var part in parts) {
      if (part.length % 2 != 0) {
        part = '0$part';
      }

      for (int i = 0; i < part.length; i += 2) {
        final hexPair = part.substring(i, i + 2);
        bytes.add(int.parse(hexPair, radix: 16));
      }
    }

    return Uint8List.fromList(bytes);
  }
}
