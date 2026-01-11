import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/log_model.dart';
import '../../models/ui_settings.dart';
import 'ui_settings_provider.dart';

class DataLogNotifier extends Notifier<LogState> {
  Timer? _receiveDebounce;
  final List<int> _lineBuffer = [];

  static const int _chunkSizeLimit = 1000;

  List<LogEntry> _currentBuffer = [];
  int _currentBufferBytes = 0;

  @override
  LogState build() {
    ref.onDispose(() {
      _receiveDebounce?.cancel();
    });
    return const LogState();
  }

  void _updateState() {
    final uiSettings = ref.read(uiSettingsProvider);
    final maxBytes = uiSettings.logBufferSize * 1024 * 1024;

    // Calculate total bytes including current buffer
    // Note: state.totalBytes represents bytes in FIXED chunks only if we track it that way,
    // but here we used state.totalBytes as global total.
    // Let's rely on calculating from chunks + buffer to be safe or maintain it carefully.

    // Recalculate fixed chunks size
    // We filter out the last chunk if it was temporary (-1) to ensure we rebuild state from stable data.
    List<LogChunk> finalizedChunks = [];
    if (state.chunks.isNotEmpty) {
      if (state.chunks.last.id == -1) {
        finalizedChunks = state.chunks.sublist(0, state.chunks.length - 1);
      } else {
        finalizedChunks = state.chunks;
      }
    }

    // Calculate total size
    int finalizedSize = finalizedChunks.fold(0, (sum, c) => sum + c.totalBytes);
    int newTotalBytes = finalizedSize + _currentBufferBytes;

    // Pruning
    int bytesToRemove = newTotalBytes - maxBytes;
    if (bytesToRemove > 0 && finalizedChunks.isNotEmpty) {
      int infoBytesRemoved = 0;
      int chunksToRemove = 0;
      for (final chunk in finalizedChunks) {
        if (infoBytesRemoved >= bytesToRemove) break;
        infoBytesRemoved += chunk.totalBytes;
        chunksToRemove++;
      }
      if (chunksToRemove > 0) {
        finalizedChunks = finalizedChunks.sublist(chunksToRemove);
        finalizedSize -= infoBytesRemoved;
        newTotalBytes -= infoBytesRemoved;
      }
    }

    // Check if current buffer needs finalizing
    if (_currentBuffer.length >= _chunkSizeLimit) {
      final newChunk = LogChunk(
        entries: List.unmodifiable(_currentBuffer),
        totalBytes: _currentBufferBytes,
        id: state.nextChunkId,
      );

      finalizedChunks = [...finalizedChunks, newChunk];
      state = LogState(
        chunks: finalizedChunks,
        totalBytes: newTotalBytes,
        nextChunkId: state.nextChunkId + 1,
      );

      _currentBuffer = [];
      _currentBufferBytes = 0;
    } else {
      // Create temp chunk
      if (_currentBuffer.isNotEmpty) {
        final tempChunk = LogChunk(
          entries:
              _currentBuffer, // Mutable reference shared, but safe for immediate render
          totalBytes: _currentBufferBytes,
          id: -1,
        );
        state = LogState(
          chunks: [...finalizedChunks, tempChunk],
          totalBytes: newTotalBytes,
          nextChunkId: state.nextChunkId,
        );
      } else {
        // Buffer empty, just finalized chunks
        if (state.chunks.length != finalizedChunks.length ||
            state.chunks.isNotEmpty && state.chunks.last.id == -1) {
          state = LogState(
            chunks: finalizedChunks,
            totalBytes: newTotalBytes,
            nextChunkId: state.nextChunkId,
          );
        }
      }
    }
  }

  void _addLogEntries(List<LogEntry> entries) {
    if (entries.isEmpty) return;
    _currentBuffer.addAll(entries);
    for (var e in entries) {
      _currentBufferBytes += e.data.length;
    }
    _updateState();
  }

  void addReceived(Uint8List data) {
    final settings = ref.read(uiSettingsProvider);

    // Determine receive mode:
    // - If hexDisplay is true: always use block receive mode
    // - If hexDisplay is false: use line mode if enabled, otherwise block mode
    final useBlockMode =
        settings.hexDisplay || settings.receiveMode == ReceiveMode.block;

    if (useBlockMode) {
      // Block receive mode: debounce short bursts of data into a single frame.
      if (_receiveDebounce?.isActive ?? false) {
        _receiveDebounce!.cancel();

        bool appended = false;
        // Try to append to the last entry in the current buffer
        if (_currentBuffer.isNotEmpty &&
            _currentBuffer.last.type == LogEntryType.received) {
          final lastEntry = _currentBuffer.last;
          final newData = Uint8List.fromList([...lastEntry.data, ...data]);

          // Update the entry in the mutable buffer
          _currentBuffer[_currentBuffer.length - 1] = LogEntry(
            newData,
            lastEntry.type,
            DateTime.now(), // Update timestamp
          );
          _currentBufferBytes += (newData.length - lastEntry.data.length);
          appended = true;
        }

        if (appended) {
          _updateState();
        } else {
          // If buffer was empty (or last was sending), treat as new entry
          _addLogEntries(
              [LogEntry(data, LogEntryType.received, DateTime.now())]);
        }
      } else {
        // Create a new entry
        _addLogEntries([LogEntry(data, LogEntryType.received, DateTime.now())]);
      }

      _receiveDebounce =
          Timer(Duration(milliseconds: settings.blockIntervalMs), () {
        // Debounce finished
      });
    } else {
      // Line receive mode: process as lines
      _receiveDebounce?.cancel();
      _appendAsLines(data);
    }
  }

  void _appendAsLines(Uint8List data) {
    final newEntries = <LogEntry>[];

    for (final byte in data) {
      if (byte == 0x0A) {
        if (_lineBuffer.isNotEmpty) {
          if (_lineBuffer.isNotEmpty && _lineBuffer.last == 0x0D) {
            _lineBuffer.removeLast();
          }

          final lineBytes = Uint8List.fromList(_lineBuffer);
          _lineBuffer.clear();

          newEntries
              .add(LogEntry(lineBytes, LogEntryType.received, DateTime.now()));
        } else {}
      } else {
        _lineBuffer.add(byte);
      }
    }

    if (newEntries.isNotEmpty) {
      _addLogEntries(newEntries);
    }
  }

  void addSent(Uint8List data) {
    _receiveDebounce?.cancel();
    _addLogEntries([LogEntry(data, LogEntryType.sent, DateTime.now())]);
  }

  void clear() {
    _receiveDebounce?.cancel();
    _lineBuffer.clear();
    _currentBuffer = [];
    _currentBufferBytes = 0;
    state = const LogState();
    // Removed direct manipulation of SerialConnectionProvider to avoid circular dependency
  }
}

final dataLogProvider = NotifierProvider.autoDispose<DataLogNotifier, LogState>(
    DataLogNotifier.new);
