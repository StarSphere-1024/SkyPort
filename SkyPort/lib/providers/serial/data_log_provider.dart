import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/log_model.dart';
import '../../utils/constants.dart';
import 'ui_settings_provider.dart';

class DataLogNotifier extends Notifier<LogState> {
  // Stream buffering: pending data for current line
  BytesBuilder _pendingData = BytesBuilder(copy: true);
  DateTime? _pendingTimestamp;

  // Completed entries waiting to be packed into chunks
  List<LogEntry> _completedBuffer = [];
  List<LogEntry> _currentBuffer = [];
  int _currentBufferBytes = 0;

  @override
  LogState build() {
    ref.onDispose(LogEntry.clearSpanCache);
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

    // Temporary chunks are rebuilt from notifier-owned buffers on every update.
    // Evict their render cache entries so pending LogEntry snapshots do not
    // survive after the next byte arrives.
    for (final tempChunk in state.chunks.where((c) => c.id == -1)) {
      LogEntry.evictCachedData(tempChunk.entries);
    }

    var finalizedChunks = state.chunks.where((c) => c.id != -1).toList();
    var nextChunkId = state.nextChunkId;

    // Add completed entries to the mutable current buffer.
    if (_completedBuffer.isNotEmpty) {
      _currentBuffer.addAll(_completedBuffer);
      for (final entry in _completedBuffer) {
        _currentBufferBytes += entry.data.length;
      }
      _completedBuffer = [];
    }

    // Commit full buffers before pruning, otherwise an oversized current buffer
    // can evade the byte limit until a later packet arrives.
    if (_currentBuffer.length >= SkyPortConstants.chunkSizeLimit) {
      final newChunk = LogChunk(
        entries: List.unmodifiable(_currentBuffer),
        totalBytes: _currentBufferBytes,
        id: nextChunkId,
      );
      nextChunkId++;

      finalizedChunks = [...finalizedChunks, newChunk];
      _currentBuffer = [];
      _currentBufferBytes = 0;
    }

    var finalizedSize = finalizedChunks.fold(0, (sum, c) => sum + c.totalBytes);
    final pendingBytes = _pendingData.length;
    var newTotalBytes = finalizedSize + _currentBufferBytes + pendingBytes;

    while (finalizedChunks.isNotEmpty &&
        newTotalBytes > maxBytes &&
        (finalizedChunks.length > 1 ||
            _currentBuffer.isNotEmpty ||
            pendingBytes > 0)) {
      final removed = finalizedChunks.removeAt(0);
      finalizedSize -= removed.totalBytes;
      newTotalBytes -= removed.totalBytes;
      LogEntry.evictCachedData(removed.entries);
    }

    while (_currentBuffer.isNotEmpty &&
        newTotalBytes > maxBytes &&
        (_currentBuffer.length > 1 || pendingBytes > 0)) {
      final removed = _currentBuffer.removeAt(0);
      _currentBufferBytes -= removed.data.length;
      newTotalBytes -= removed.data.length;
      removed.clearDisplayCache();
    }

    // Build display chunks with pending data as last item
    final displayChunks = List<LogChunk>.from(finalizedChunks);

    // Add current buffer as temp chunk if not empty
    // Only add if we haven't already added a temp chunk with the same content
    if (_currentBuffer.isNotEmpty) {
      // Check if the last chunk is already a temp chunk with the same entries
      final lastIsTempWithSameContent = displayChunks.isNotEmpty &&
          displayChunks.last.id == -1 &&
          _listsEqual(displayChunks.last.entries, _currentBuffer);

      if (!lastIsTempWithSameContent) {
        final tempChunk = LogChunk(
          entries: List.unmodifiable(_currentBuffer),
          totalBytes: _currentBufferBytes,
          id: -1,
        );
        displayChunks.add(tempChunk);
      }
    }

    // Add pending data as the very last temp entry
    if (_pendingData.length > 0) {
      final pendingEntry = LogEntry(
        _pendingData.toBytes(),
        LogEntryType.received,
        _pendingTimestamp ?? DateTime.now(),
      );
      final pendingChunk = LogChunk(
        entries: List.unmodifiable([pendingEntry]),
        id: -1, // Special ID for pending data
        totalBytes: _pendingData.length,
      );
      displayChunks.add(pendingChunk);
    }

    state = LogState(
      chunks: displayChunks,
      totalBytes: newTotalBytes,
      nextChunkId: nextChunkId,
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
        final int lineEndExclusive =
            (i > processedIndex && data[i - 1] == 0x0D) ? i - 1 : i;

        Uint8List fullLine;
        if (_pendingData.length == 0) {
          fullLine = Uint8List(lineEndExclusive - processedIndex);
          fullLine.setRange(0, fullLine.length, data, processedIndex);
        } else {
          if (lineEndExclusive > processedIndex) {
            _pendingData.add(
              Uint8List.sublistView(data, processedIndex, lineEndExclusive),
            );
          }
          fullLine = _pendingData.takeBytes();
          _pendingData = BytesBuilder(copy: true);
        }
        // Create completed entry
        _completedBuffer.add(LogEntry(
          fullLine,
          LogEntryType.received,
          _pendingTimestamp ?? DateTime.now(),
        ));

        // Reset pending for next line
        _pendingData = BytesBuilder(copy: true);
        _pendingTimestamp = null; // Will be set on next byte
        processedIndex = i + 1; // Skip the newline
      }
    }

    // Append remaining data (after last newline, or all if no newline found)
    if (processedIndex < data.length) {
      _pendingData.add(Uint8List.sublistView(data, processedIndex));
    }

    // Defense: Force flush if pending grows too large (no newline scenario)
    if (_pendingData.length > SkyPortConstants.maxPendingBytes) {
      _completedBuffer.add(LogEntry(
        _pendingData.takeBytes(),
        LogEntryType.received,
        _pendingTimestamp ?? DateTime.now(),
      ));
      _pendingData = BytesBuilder(copy: true);
      _pendingTimestamp = null;
    }

    _updateState();
  }

  void addSent(Uint8List data) {
    _addLogEntries([LogEntry(data, LogEntryType.sent, DateTime.now())]);
  }

  void clear() {
    _pendingData = BytesBuilder(copy: true);
    _pendingTimestamp = null;
    _completedBuffer = [];
    _currentBuffer = [];
    _currentBufferBytes = 0;
    state = const LogState();
    LogEntry.clearSpanCache();
  }
}

final dataLogProvider = NotifierProvider.autoDispose<DataLogNotifier, LogState>(
    DataLogNotifier.new);
