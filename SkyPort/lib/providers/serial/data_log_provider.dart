import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/log_model.dart';
import 'ui_settings_provider.dart';

class DataLogNotifier extends Notifier<LogState> {
  // Stream buffering: pending data for current line
  List<int> _pendingData = [];
  DateTime? _pendingTimestamp;

  // Defense: maximum pending bytes before forcing flush (256KB)
  static const int _maxPendingBytes = 256 * 1024;

  // Completed entries waiting to be packed into chunks
  List<LogEntry> _completedBuffer = [];

  static const int _chunkSizeLimit = 1000;
  List<LogEntry> _currentBuffer = [];
  int _currentBufferBytes = 0;

  @override
  LogState build() {
    return const LogState();
  }

  /// Check if two lists of LogEntry are equal (same length and same content)
  bool _listsEqual(List<LogEntry> a, List<LogEntry> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].data.length != b[i].data.length) return false;
      // Compare byte-by-byte
      for (int j = 0; j < a[i].data.length; j++) {
        if (a[i].data[j] != b[i].data[j]) return false;
      }
    }
    return true;
  }

  void _updateState() {
    final uiSettings = ref.read(uiSettingsProvider);
    final maxBytes = uiSettings.logBufferSize * 1024 * 1024;

    // Recalculate fixed chunks size
    // Filter out the last chunk if it was temporary (-1)
    List<LogChunk> finalizedChunks = [];
    if (state.chunks.isNotEmpty) {
      if (state.chunks.last.id == -1) {
        finalizedChunks = state.chunks.sublist(0, state.chunks.length - 1);
      } else {
        finalizedChunks = state.chunks;
      }
    }

    // Add completed buffer entries to current buffer
    if (_completedBuffer.isNotEmpty) {
      // Convert to unmodifiable list to prevent accidental mutation
      // This prevents duplicate entries in displayChunks
      final newEntries = List<LogEntry>.unmodifiable(_completedBuffer);
      _currentBuffer.addAll(newEntries);
      for (var entry in _completedBuffer) {
        _currentBufferBytes += entry.data.length;
      }
      _completedBuffer = [];
    }

    // Calculate total size
    int finalizedSize = finalizedChunks.fold(0, (sum, c) => sum + c.totalBytes);
    int pendingBytes = _pendingData.length;
    int newTotalBytes = finalizedSize + _currentBufferBytes + pendingBytes;

    // Pruning old chunks if exceeding max bytes
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

    // Check if current buffer needs finalizing into a chunk
    if (_currentBuffer.length >= _chunkSizeLimit) {
      final newChunk = LogChunk(
        entries: List.unmodifiable(_currentBuffer),
        totalBytes: _currentBufferBytes,
        id: state.nextChunkId,
      );

      finalizedChunks = [...finalizedChunks, newChunk];
      _currentBuffer = [];
      _currentBufferBytes = 0;
    }

    // Build display chunks with pending data as last item
    // Use a Set to track which chunks are already in the display list
    // This prevents duplicate chunks from being added multiple times
    final existingChunkIds = <int>{};
    for (final chunk in finalizedChunks) {
      existingChunkIds.add(chunk.id);
    }

    List<LogChunk> displayChunks = List.from(finalizedChunks);

    // Add current buffer as temp chunk if not empty
    // Only add if we haven't already added a temp chunk with the same content
    if (_currentBuffer.isNotEmpty) {
      // Check if the last chunk is already a temp chunk with the same entries
      final lastIsTempWithSameContent = displayChunks.isNotEmpty &&
          displayChunks.last.id == -1 &&
          _listsEqual(displayChunks.last.entries, _currentBuffer);

      if (!lastIsTempWithSameContent) {
        final tempChunk = LogChunk(
          entries: _currentBuffer,
          totalBytes: _currentBufferBytes,
          id: -1,
        );
        displayChunks.add(tempChunk);
      }
    }

    // Add pending data as the very last temp entry
    if (_pendingData.isNotEmpty) {
      final pendingEntry = LogEntry(
        Uint8List.fromList(_pendingData),
        LogEntryType.received,
        _pendingTimestamp ?? DateTime.now(),
      );
      final pendingChunk = LogChunk(
        entries: [pendingEntry],
        id: -1, // Special ID for pending data
        totalBytes: _pendingData.length,
      );
      displayChunks.add(pendingChunk);
    }

    state = LogState(
      chunks: displayChunks,
      totalBytes: newTotalBytes,
      nextChunkId: state.nextChunkId + (displayChunks.length > finalizedChunks.length ? 1 : 0),
    );
  }

  void _addLogEntries(List<LogEntry> entries) {
    if (entries.isEmpty) return;
    _completedBuffer.addAll(entries);
    _updateState();
  }

  /// Add received data with stream buffering
  /// All data goes to pending buffer first, then gets flushed on newline (0x0A)
  void addReceived(Uint8List data) {
    if (data.isEmpty) {
      // Even empty data should trigger state update to ensure UI responsiveness
      _updateState();
      return;
    }

    // Record timestamp on first byte of this line
    _pendingTimestamp ??= DateTime.now();

    int processedIndex = 0;

    // Scan through data looking for newlines (0x0A)
    for (int i = 0; i < data.length; i++) {
      if (data[i] == 0x0A) {
        // Found newline - flush pending + current segment as a completed line

        // Handle CRLF: if previous byte was CR (0x0D), exclude it
        final int lineEndExclusive = (i > processedIndex && data[i - 1] == 0x0D)
            ? i - 1
            : i;

        final chunk = data.sublist(processedIndex, lineEndExclusive);
        final fullLine = Uint8List.fromList([..._pendingData, ...chunk]);

        // Create completed entry
        _completedBuffer.add(LogEntry(
          fullLine,
          LogEntryType.received,
          _pendingTimestamp ?? DateTime.now(),
        ));

        // Reset pending for next line
        _pendingData = [];
        _pendingTimestamp = null; // Will be set on next byte
        processedIndex = i + 1; // Skip the newline
      }
    }

    // Append remaining data (after last newline, or all if no newline found)
    if (processedIndex < data.length) {
      _pendingData.addAll(data.sublist(processedIndex));
    }

    // Defense: Force flush if pending grows too large (no newline scenario)
    if (_pendingData.length > _maxPendingBytes) {
      _completedBuffer.add(LogEntry(
        Uint8List.fromList(_pendingData),
        LogEntryType.received,
        _pendingTimestamp ?? DateTime.now(),
      ));
      _pendingData = [];
      _pendingTimestamp = null;
    }

    _updateState();
  }

  void addSent(Uint8List data) {
    _addLogEntries([LogEntry(data, LogEntryType.sent, DateTime.now())]);
  }

  void clear() {
    _pendingData = [];
    _pendingTimestamp = null;
    _completedBuffer = [];
    _currentBuffer = [];
    _currentBufferBytes = 0;
    state = const LogState();
  }
}

final dataLogProvider = NotifierProvider.autoDispose<DataLogNotifier, LogState>(
    DataLogNotifier.new);
