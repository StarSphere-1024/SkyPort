import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/serial_provider.dart';
import '../../l10n/app_localizations.dart';

class SendInputWidget extends ConsumerStatefulWidget {
  const SendInputWidget({super.key});

  @override
  ConsumerState<SendInputWidget> createState() => _SendInputWidgetState();
}

class _SendInputWidgetState extends ConsumerState<SendInputWidget> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _sendController = TextEditingController();
  bool _canSend = false;
  bool _previousHexMode = false;

  // Static RegExp constants to avoid repeated object creation
  static final RegExp hexRegex = RegExp(r'^[0-9a-fA-F]+$');
  static final RegExp whitespaceRegex = RegExp(r'\s+');

  // Helper methods to reduce code duplication
  String _sanitizeHex(String value) => value.replaceAll(whitespaceRegex, '');
  bool _isValidHex(String sanitized) =>
      hexRegex.hasMatch(sanitized) && sanitized.length % 2 == 0;

  Widget _buildTextField(bool hexSend, AppLocalizations l10n) {
    return TextFormField(
      controller: _sendController,
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
          if (!hexSend) {
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
        });
      },
      validator: (value) {
        if (hexSend) {
          if (value == null || value.isEmpty) {
            return null;
          }
          final sanitized = _sanitizeHex(value);
          if (sanitized.isEmpty) {
            return null;
          }
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

  Widget _buildSendButton(
      ConnectionStatus connectionStatus, bool canSend, WidgetRef ref) {
    return FilledButton.icon(
      icon: const Icon(Icons.send),
      label: Text(AppLocalizations.of(context).send),
      onPressed: connectionStatus == ConnectionStatus.connected && canSend
          ? () {
              if (_formKey.currentState!.validate()) {
                ref
                    .read(serialConnectionProvider.notifier)
                    .send(_sendController.text);
              }
            }
          : null,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
      ),
    );
  }

  @override
  void dispose() {
    _sendController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus =
        ref.watch(serialConnectionProvider.select((c) => c.status));
    final uiSettings = ref.watch(uiSettingsProvider);
    final hexSend = uiSettings.hexSend;

    // Detect hexSend mode changes to perform text ↔ hex in-place conversion.
    if (_previousHexMode != hexSend) {
      _handleHexSendToggle(
          previousIsHex: _previousHexMode, currentIsHex: hexSend);
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
              _buildSendButton(connectionStatus, _canSend, ref),
            ],
          ),
        ),
      ),
    );
  }

  void _handleHexSendToggle(
      {required bool previousIsHex, required bool currentIsHex}) {
    final text = _sendController.text;
    if (text.isEmpty) {
      return;
    }

    // Text -> Hex
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

    // Hex -> Text
    if (previousIsHex && !currentIsHex) {
      final hexText = text.trim();
      if (hexText.isEmpty) {
        _sendController.clear();
        _canSend = false;
        return;
      }

      // Reuse the parsing rules from the sending end: allow spaces, automatically pad odd-length characters.
      try {
        final bytes = _parseHexToBytes(hexText);
        // Try to decode as UTF-8; if it fails, keep the original hex text.
        final decoded = utf8.decode(bytes, allowMalformed: false);
        _sendController.text = decoded;
        _sendController.selection = TextSelection.fromPosition(
          TextPosition(offset: decoded.length),
        );
        _canSend = decoded.isNotEmpty;
      } catch (_) {
        // Invalid hex or invalid UTF-8: keep the original content, no conversion.
      }
    }
  }

  // Locally implement a parser equivalent to the sending logic to avoid directly depending on private methods.
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
