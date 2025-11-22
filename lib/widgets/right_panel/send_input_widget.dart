import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/serial_provider.dart';
import 'package:sky_port/l10n/app_localizations.dart';

class SendInputWidget extends ConsumerStatefulWidget {
  const SendInputWidget({super.key});

  @override
  ConsumerState<SendInputWidget> createState() => _SendInputWidgetState();
}

class _SendInputWidgetState extends ConsumerState<SendInputWidget> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _sendController = TextEditingController();

  @override
  void dispose() {
    _sendController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus =
        ref.watch(serialConnectionProvider.select((c) => c.status));
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
                child: Consumer(builder: (context, ref, child) {
                  final hexSend = ref.watch(uiSettingsProvider).hexSend;
                  final l10n = AppLocalizations.of(context);
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
                    validator: (value) {
                      if (hexSend) {
                        if (value == null || value.isEmpty) {
                          return null;
                        }
                        final sanitizedValue =
                            value.replaceAll(RegExp(r'\s+'), '');
                        if (sanitizedValue.isEmpty) {
                          return null;
                        }
                        if (!RegExp(r'^[0-9a-fA-F]+$')
                            .hasMatch(sanitizedValue)) {
                          return l10n.invalidHexChars;
                        }
                        if (sanitizedValue.length % 2 != 0) {
                          return l10n.hexEvenLength;
                        }
                      }
                      return null;
                    },
                  );
                }),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.send),
                label: Text(AppLocalizations.of(context).send),
                onPressed: connectionStatus == ConnectionStatus.connected
                    ? () {
                        if (_formKey.currentState!.validate()) {
                          ref
                              .read(serialConnectionProvider.notifier)
                              .send(_sendController.text);
                        }
                      }
                    : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      vertical: 16.0, horizontal: 24.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
