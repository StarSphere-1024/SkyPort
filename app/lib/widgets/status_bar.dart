import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ui_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/ui_state.dart';
import '../utils/connection_status.dart';
import '../utils/error_messages.dart';
import 'shared/error_notice.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      uiControllerProvider.select(
        (state) => (
          rxBytes: state.rxBytes,
          txBytes: state.txBytes,
          lastRxBytes: state.lastRxBytes,
          rxBytesPerSecond: state.rxBytesPerSecond,
          connection: state.connection,
          portName: state.portName,
          baudRate: state.baudRate,
          dataBits: state.dataBits,
          parity: state.parity,
          stopBits: state.stopBits,
          error: state.error,
        ),
      ),
    );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final actionStyle = IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
    final l10n = AppLocalizations.of(context);

    final secondaryStyle = TextStyle(color: colorScheme.onSurfaceVariant);
    final rxText = _formatIecBytes(state.rxBytes);
    final lastRxText = _formatIecBytes(state.lastRxBytes);
    final txText = _formatIecBytes(state.txBytes);
    final rateText = '${_formatIecBytes(state.rxBytesPerSecond)}/s';
    final statsText = 'RX $rxText - $lastRxText    TX $txText    $rateText';
    final disconnect =
        state.connection == UiConnection.connected ||
        state.connection == UiConnection.reconnecting;
    final canToggle =
        disconnect ||
        (state.connection == UiConnection.disconnected &&
            state.portName.isNotEmpty);
    final statusColor = connectionStatusColor(state.connection, theme);
    final status = connectionStatusLabel(state.connection, l10n);
    final reconnecting = state.connection == UiConnection.reconnecting;
    final diagnostic = reconnecting ? state.error : null;
    final portText = state.portName.isEmpty ? '' : state.portName;
    final serialSettings =
        '${state.baudRate} · ${state.dataBits}'
        '${switch (state.parity) {
          UiParity.none => 'N',
          UiParity.odd => 'O',
          UiParity.even => 'E',
        }}${state.stopBits}';

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: AlignmentDirectional.centerEnd,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        color: colorScheme.surface,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final style = theme.textTheme.bodySmall!;
          final scaler = MediaQuery.textScalerOf(context);
          final painter = TextPainter(
            textDirection: Directionality.of(context),
            textScaler: scaler,
            locale: Localizations.localeOf(context),
          );
          double widthOf(String text) {
            painter.text = TextSpan(text: text, style: style);
            painter.layout();
            return painter.width;
          }

          final available = math.max(
            0.0,
            constraints.maxWidth -
                32 -
                (reconnecting ? 0 : 12) -
                (diagnostic == null ? 0 : 32),
          );
          final portLabel = portText.isEmpty ? l10n.noPortSelected : portText;
          final minimumPortWidth = math.min(
            widthOf(portLabel),
            math.min(scaler.scale(80), available * 0.4),
          );
          final fullStatsWidth = widthOf(statsText);
          final showDetails = available >= minimumPortWidth + fullStatsWidth;
          final rxWidth = widthOf('RX $rxText');
          final txWidth = widthOf('TX $txText');
          final compactStatsWidth = rxWidth + 12 + txWidth;
          final statsWidth = reconnecting
              ? 0.0
              : math.min(
                  showDetails ? fullStatsWidth : compactStatsWidth,
                  available - minimumPortWidth,
                );
          final showSettings =
              portText.isNotEmpty &&
              available - statsWidth >=
                  minimumPortWidth + widthOf('  $serialSettings');
          painter.dispose();

          return Row(
            children: [
              IconButton(
                style: actionStyle,
                tooltip:
                    '$status\n${disconnect ? l10n.disconnect : l10n.connect}',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                onPressed: !canToggle
                    ? null
                    : () {
                        final controller = ref.read(
                          uiControllerProvider.notifier,
                        );
                        if (disconnect) {
                          controller.disconnect();
                        } else {
                          controller.connect();
                        }
                      },
                icon: Icon(Icons.circle, size: 10, color: statusColor),
              ),
              Expanded(
                child: Tooltip(
                  message:
                      '$status\n${state.portName}  $serialSettings'
                      '${diagnostic == null ? '' : '\n${localizedError(l10n, diagnostic)}'}',
                  child: Text.rich(
                    TextSpan(
                      text: reconnecting ? '$status  ' : '',
                      children: [
                        TextSpan(
                          text: portText.isEmpty
                              ? l10n.noPortSelected
                              : portText,
                          style: reconnecting ? secondaryStyle : null,
                        ),
                        if (showSettings)
                          TextSpan(
                            text: '  $serialSettings',
                            style: secondaryStyle,
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              if (diagnostic != null)
                IconButton(
                  style: actionStyle,
                  tooltip:
                      '${l10n.diagnosticDetails}: ${localizedError(l10n, diagnostic)}',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  onPressed: () => showErrorDetails(context, diagnostic),
                  icon: const Icon(Icons.info_outline, size: 16),
                ),
              if (!reconnecting) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: statsWidth,
                  child: Tooltip(
                    message:
                        '${l10n.trafficStats(state.rxBytes, state.txBytes, state.lastRxBytes)}'
                        ' · $rateText',
                    child: showDetails
                        ? Text.rich(
                            TextSpan(
                              text: 'RX $rxText - $lastRxText    TX $txText',
                              style: TextStyle(color: colorScheme.primary),
                              children: [
                                TextSpan(
                                  text: '    $rateText',
                                  style: secondaryStyle,
                                ),
                              ],
                            ),
                            maxLines: 1,
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: style,
                          )
                        : Row(
                            children: [
                              SizedBox(
                                width:
                                    math.max(0, statsWidth - 12) *
                                    rxWidth /
                                    (rxWidth + txWidth),
                                child: Text(
                                  'RX $rxText',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: style.copyWith(
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'TX $txText',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: style.copyWith(
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

String _formatIecBytes(num bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '${value.round()} ${units[unit]}'
      : '${value.toStringAsFixed(1)} ${units[unit]}';
}
