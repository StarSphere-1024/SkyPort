import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ui_state.dart';
import '../../providers/ui_controller.dart';

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

  int _historyIndex = -1;
  String _tempInput = '';

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    _sendController.text = ref.read(autoSendDraftProvider);
    _previousHexMode = ref.read(uiControllerProvider).hexSend;
    _updateCanSend(_sendController.text);
  }

  @override
  void dispose() {
    _sendController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setDraft(String value) {
    ref.read(autoSendDraftProvider.notifier).setDraft(value);
    final core = ref.read(uiControllerProvider);
    if (core.autoSendEnabled && value != core.autoSendInput) {
      ref.read(uiControllerProvider.notifier).setAutoSendInput(value);
    }
  }

  void _setDraftAfterFrame(String value) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setDraft(value);
    });
  }

  void _navigateHistory(bool up) {
    final history = ref.read(uiControllerProvider).sendHistory;
    if (history.isEmpty) return;
    setState(() {
      if (up) {
        if (_historyIndex == -1) {
          _tempInput = _sendController.text;
          _historyIndex = history.length - 1;
        } else if (_historyIndex > 0) {
          _historyIndex--;
        }
      } else if (_historyIndex != -1) {
        _historyIndex = _historyIndex < history.length - 1
            ? _historyIndex + 1
            : -1;
      }
      final newText = _historyIndex == -1 ? _tempInput : history[_historyIndex];
      _sendController.text = newText;
      _sendController.selection = TextSelection.fromPosition(
        TextPosition(offset: newText.length),
      );
      _updateCanSend(newText);
      _setDraft(newText);
    });
  }

  void _updateCanSend(String value) {
    if (!ref.read(uiControllerProvider).hexSend) {
      _canSend = value.isNotEmpty;
      return;
    }

    if (value.isEmpty) {
      _canSend = false;
      return;
    }

    final sanitized = _sanitizeHex(value);
    if (sanitized.isEmpty) {
      _canSend = false;
    } else {
      _canSend = _isValidHex(sanitized);
    }
  }

  static final RegExp hexRegex = RegExp(r'^[0-9a-fA-F]+$');
  static final RegExp whitespaceRegex = RegExp(r'[ \t\n\r\f]+');

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
          final history = ref.read(uiControllerProvider).sendHistory;
          if (_historyIndex != -1 &&
              (_historyIndex >= history.length ||
                  value != history[_historyIndex])) {
            _historyIndex = -1;
          }
        });
        _setDraft(value);
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

  Widget _buildSendButton(UiConnection connectionState, bool canSend) {
    return FilledButton.icon(
      icon: const Icon(Icons.send),
      label: Text(AppLocalizations.of(context).send),
      onPressed: connectionState == UiConnection.connected && canSend
          ? () {
              if (_formKey.currentState!.validate()) {
                final text = _sendController.text;
                ref.read(uiControllerProvider.notifier).send(text);
                setState(() {
                  _historyIndex = -1;
                  _tempInput = '';
                });
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
    final state = ref.watch(uiControllerProvider);
    final connectionState = state.connection;
    final hexSend = state.hexSend;
    if (_previousHexMode != hexSend) {
      _sendController.text = state.autoSendInput;
      _sendController.selection = TextSelection.collapsed(
        offset: _sendController.text.length,
      );
      _updateCanSend(_sendController.text);
      _setDraftAfterFrame(_sendController.text);
      _previousHexMode = hexSend;
    }
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
}
