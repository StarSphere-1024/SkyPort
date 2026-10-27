import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/search_controller.dart';
import '../../providers/ui_settings_provider.dart';
import '../../utils/error_messages.dart';

class LogSearchBar extends ConsumerStatefulWidget {
  final FocusNode focusNode;
  const LogSearchBar({super.key, required this.focusNode});

  @override
  ConsumerState<LogSearchBar> createState() => _LogSearchBarState();
}

class _LogSearchBarState extends ConsumerState<LogSearchBar> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: ref.read(searchControllerProvider).draft,
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    ref.watch(uiSettingsProvider);
    final controller = ref.read(searchControllerProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final options = controller.currentOptions;
    final canNavigate =
        state.total > 0 && !state.invalidated && !state.submitting;
    final busy = state.submitting || !state.complete;
    final dirty = state.dirty(options);
    final status = <String>[
      if (state.submitting) l10n.searchStarting,
      if (!state.complete && !state.submitting)
        l10n.searchProgress(state.total),
      if (state.activeQuery != null && state.complete && state.total == 0)
        l10n.searchNoMatches,
      if (dirty) l10n.searchDirty,
      if (state.invalidated) l10n.searchStale,
      if (state.wrapped) l10n.searchWrapped,
      if (state.error != null)
        l10n.searchFailed(localizedError(l10n, state.error!)),
    ];
    final count = state.invalidated
        ? '—/—'
        : l10n.searchCount((state.selectedIndex ?? -1) + 1, state.total);
    final buttonStyle = IconButton.styleFrom(
      minimumSize: const Size.square(32),
      maximumSize: const Size.square(32),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        height: 36,
        child: IconButtonTheme(
          data: IconButtonThemeData(style: buttonStyle),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('search-input'),
                  controller: _text,
                  focusNode: widget.focusNode,
                  style: theme.textTheme.bodyMedium,
                  textInputAction: TextInputAction.search,
                  onChanged: controller.setDraft,
                  onEditingComplete: widget.focusNode.requestFocus,
                  onSubmitted: (_) => controller.submit(),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    hintText: options.hex
                        ? l10n.searchHexHint
                        : l10n.searchTextHint,
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: state.error != null
                            ? colors.error
                            : colors.outlineVariant,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: state.error != null
                            ? colors.error
                            : colors.primary,
                      ),
                    ),
                    suffixIconConstraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    suffixIcon: options.hex
                        ? null
                        : IconButton(
                            key: const ValueKey('search-case'),
                            tooltip: l10n.searchCaseSensitive,
                            isSelected: state.caseSensitive,
                            onPressed: () => controller.setCaseSensitive(
                              !state.caseSensitive,
                            ),
                            icon: const Text(
                              'Aa',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('search-submit'),
                tooltip: l10n.searchSubmit,
                onPressed: controller.submit,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.search, size: 18),
              ),
              IconButton(
                key: const ValueKey('search-previous'),
                tooltip: l10n.searchPrevious,
                onPressed: canNavigate ? () => controller.navigate(-1) : null,
                icon: const Icon(Icons.chevron_left, size: 20),
              ),
              IconButton(
                key: const ValueKey('search-next'),
                tooltip: l10n.searchNext,
                onPressed: canNavigate ? () => controller.navigate(1) : null,
                icon: const Icon(Icons.chevron_right, size: 20),
              ),
              Tooltip(
                message: status.isEmpty ? count : status.join('\n'),
                child: Semantics(
                  liveRegion: true,
                  label: status.isEmpty ? count : status.join('. '),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: state.error != null
                        ? Icon(
                            Icons.error_outline,
                            key: const ValueKey('search-status'),
                            size: 16,
                            color: colors.error,
                          )
                        : Text(
                            count,
                            key: const ValueKey('search-status'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: dirty || state.invalidated
                                  ? colors.onSurfaceVariant
                                  : colors.onSurface,
                              decoration: dirty
                                  ? TextDecoration.underline
                                  : null,
                              decorationStyle: TextDecorationStyle.dotted,
                            ),
                          ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('search-close'),
                tooltip: l10n.searchClose,
                onPressed: controller.close,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
