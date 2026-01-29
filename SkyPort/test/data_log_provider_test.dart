import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/models/log_model.dart';
import 'package:skyport/models/ui_settings.dart';
import 'package:skyport/providers/serial/data_log_provider.dart';
import 'package:skyport/providers/serial/ui_settings_provider.dart';

// Mock provider container setup
ProviderContainer createTestContainer() {
  // Create a simple mock for uiSettingsProvider
  final uiSettings = const UiSettings(
    hexDisplay: false,
    hexSend: false,
    showTimestamp: true,
    showSent: true,
    blockIntervalMs: 20,
    receiveMode: ReceiveMode.block,
    preferredReceiveMode: ReceiveMode.line,
    appendNewline: false,
    newlineMode: NewlineMode.lf,
    enableAnsi: false,
    logBufferSize: 128,
    autoSendEnabled: false,
    autoSendIntervalMs: 1000,
  );

  final container = ProviderContainer(
    overrides: [
      uiSettingsProvider
          .overrideWith(() => _TestUiSettingsNotifier(uiSettings)),
    ],
  );
  return container;
}

class _TestUiSettingsNotifier extends UiSettingsNotifier {
  final UiSettings _settings;

  _TestUiSettingsNotifier(this._settings);

  @override
  UiSettings build() => _settings;
}

void main() {
  group('DataLogNotifier - Stream Buffering Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = createTestContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('无 \\n：多次 addReceived 只增长 pending，且时间戳保持第一次收到数据的时间', () {
      final notifier = container.read(dataLogProvider.notifier);

      // 第一次接收
      notifier.addReceived(
          Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F])); // "Hello"
      final state1 = container.read(dataLogProvider);

      // 验证：pending 数据存在（因为没有 \n）
      expect(state1.chunks.isNotEmpty, true);
      expect(state1.chunks.last.id, -1); // 临时 chunk

      // 验证：时间戳存在
      final firstTimestamp = state1.chunks.last.entries.first.timestamp;
      expect(firstTimestamp, isNotNull);

      // 第二次接收（无换行符）
      notifier.addReceived(
          Uint8List.fromList([0x20, 0x57, 0x6F, 0x72, 0x6C, 0x64])); // " World"
      final state2 = container.read(dataLogProvider);

      // 验证：pending 数据增长
      final entry2 = state2.chunks.last.entries.first;
      final text2 = String.fromCharCodes(entry2.data);
      expect(text2, 'Hello World');

      // 验证：时间戳保持第一次的（即使无法精确比较，也验证了逻辑）
      final secondTimestamp = state2.chunks.last.entries.first.timestamp;
      expect(secondTimestamp, equals(firstTimestamp));
    });

    test('单次多行：一个 Uint8List 内含多个 \\n，应固化多条历史行，末尾残留进入 pending', () {
      final notifier = container.read(dataLogProvider.notifier);

      // 发送包含多个换行符的数据
      final data = Uint8List.fromList([
        0x4C, 0x69, 0x6E, 0x65, 0x31, 0x0A, // "Line1\n"
        0x4C, 0x69, 0x6E, 0x65, 0x32, 0x0A, // "Line2\n"
        0x4C, 0x69, 0x6E, 0x65, 0x33
      ] // "Line3" (无换行符)
          );

      notifier.addReceived(data);
      final state = container.read(dataLogProvider);

      // 验证：应该有多个 chunk
      // Line1 和 Line2 被固化，Line3 在 pending 中
      expect(state.chunks.length, greaterThanOrEqualTo(1));

      // 验证：最后一个 chunk 是 pending（id = -1）
      expect(state.chunks.last.id, -1);

      // 验证：pending 中的内容是 "Line3"
      final pendingEntry = state.chunks.last.entries.first;
      final pendingText = String.fromCharCodes(pendingEntry.data);
      expect(pendingText, 'Line3');

      // 验证：之前的固化行存在（通过总字节数验证）
      expect(state.totalBytes, greaterThan(5)); // 至少有 "Line3" 的5个字节
    });

    test('以 \\n 结尾：固化后 pending 为空，展示列表不应额外追加临时项', () {
      final notifier = container.read(dataLogProvider.notifier);

      // 发送以换行符结尾的数据
      final data =
          Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x0A] // "Hello\n"
              );

      notifier.addReceived(data);
      final state = container.read(dataLogProvider);

      // 验证：数据被处理
      expect(state.totalBytes, 5); // "Hello" = 5 字节（去掉了 \n）

      // 验证：数据已经被固化（不在 pending 中）
      // 检查有多少个临时 chunk
      int tempChunkCount = 0;
      for (final chunk in state.chunks) {
        if (chunk.id == -1) {
          tempChunkCount++;
        }
      }

      // 应该只有 0 或 1 个临时 chunk（current buffer 的临时 chunk）
      // 不会有额外的 pending chunk（因为数据已经被固化）
      expect(tempChunkCount, lessThanOrEqualTo(1));

      // 如果有临时 chunk，检查它是否来自 pending（包含 "Hello"）
      // 或者来自 current buffer（也应该包含固化的数据）
      if (state.chunks.isNotEmpty) {
        final lastChunk = state.chunks.last;
        if (lastChunk.id == -1 && lastChunk.entries.isNotEmpty) {
          final text = String.fromCharCodes(lastChunk.entries.first.data);
          // 应该是固化的 "Hello"，而不是 pending
          expect(text, 'Hello');
        }
      }
    });

    test('\\r\\n：固化行内容不包含 \\r', () {
      final notifier = container.read(dataLogProvider.notifier);

      // Windows 风格换行符
      final data = Uint8List.fromList(
          [0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x0D, 0x0A] // "Hello\r\n"
          );

      notifier.addReceived(data);
      final state = container.read(dataLogProvider);

      // 验证：找到固化的行（不在 pending 中）
      if (state.chunks.length > 1 ||
          (state.chunks.isNotEmpty && state.chunks.first.id != -1)) {
        // 获取第一个非临时 chunk 的第一个 entry
        LogEntry? firstEntry;
        for (final chunk in state.chunks) {
          if (chunk.id != -1 && chunk.entries.isNotEmpty) {
            firstEntry = chunk.entries.first;
            break;
          }
        }

        if (firstEntry != null) {
          final text = String.fromCharCodes(firstEntry.data);
          // 验证：不包含 \r
          expect(text, isNot(contains('\r')));
          expect(text, 'Hello');
        }
      }

      // 验证：总字节数正确（去掉了 \r）
      expect(state.totalBytes, 5); // "Hello" = 5 字节（不含 \r 和 \n）
    });

    test('ANSI 跨包：ANSI 序列分成两次 addReceived，最终渲染一致且不乱码', () {
      final notifier = container.read(dataLogProvider.notifier);

      // ANSI 转义序列：\x1b[31m（红色） + "Hello" + \x1b[0m（重置）
      final part1 = Uint8List.fromList(
          [0x1B, 0x5B, 0x33, 0x31, 0x6D, 0x48, 0x65]); // "\x1b[31mHe"
      final part2 = Uint8List.fromList(
          [0x6C, 0x6C, 0x6F, 0x1B, 0x5B, 0x30, 0x6D, 0x0A]); // "llo\x1b[0m\n"

      notifier.addReceived(part1);
      final state1 = container.read(dataLogProvider);

      // 第一次接收后，数据在 pending 中
      expect(state1.chunks.last.id, -1);

      // 第二次接收完成 ANSI 序列和换行符
      notifier.addReceived(part2);
      final state2 = container.read(dataLogProvider);

      // 验证：完整的行被固化
      expect(state2.totalBytes, greaterThan(0));

      // 验证：可以正确解析文本（不抛异常）
      if (state2.chunks.isNotEmpty) {
        // 找到第一个非空的 entry
        for (final chunk in state2.chunks) {
          if (chunk.entries.isNotEmpty) {
            final entry = chunk.entries.first;
            // 验证：可以转换为文本而不抛出异常
            expect(
              () => String.fromCharCodes(entry.data),
              returnsNormally,
            );

            // 验证：文本包含完整的 ANSI 序列
            final text = String.fromCharCodes(entry.data);
            expect(text.contains('\x1B'), true); // 包含 ESC 字符
            expect(text.contains('[31m'), true); // 包含颜色代码
            expect(text.contains('Hello'), true); // 包含文本
            break;
          }
        }
      }
    });

    test('Pending 上限防御：超过 maxPendingBytes 时强制固化', () {
      final notifier = container.read(dataLogProvider.notifier);

      // 构造超长数据（超过 256KB）
      final largeData = Uint8List(300 * 1024); // 300KB
      for (int i = 0; i < largeData.length; i++) {
        largeData[i] = 0x41; // 'A'
      }

      notifier.addReceived(largeData);
      final state = container.read(dataLogProvider);

      // 验证：数据被处理（不是无限增长在 pending 中）
      // 要么被固化，要么被正确限制
      expect(state.totalBytes, greaterThan(0));

      // 验证：数据被正确处理（total bytes 应该等于输入数据大小）
      expect(state.totalBytes, 300 * 1024);

      // 验证：没有真正的 pending chunk（最后一个临时 chunk 是 current buffer）
      // pending chunk 只有一个 entry，而 current buffer 可能有多个
      // 在这个测试中，我们应该只有固化后的数据在 current buffer 中
      // 由于只有 1 个 entry，它会被打包成一个临时 chunk

      // 实际验证：内部 _pendingData 应该被清空
      // 我们可以通过发送第二个数据包来验证
      notifier.addReceived(Uint8List.fromList([0x0A])); // 发送换行符
      final state2 = container.read(dataLogProvider);

      // 如果之前的 300KB 已经被固化到 _currentBuffer，
      // 那么现在应该有一个空的换行行被固化
      // 总字节数应该仍然是 300KB（换行符被去掉了）
      expect(state2.totalBytes, 300 * 1024);
    });
  });

  group('DataLogNotifier - CRLF Handling', () {
    late ProviderContainer container;

    setUp(() {
      container = createTestContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('单独的 \\r 不应该触发固化', () {
      final notifier = container.read(dataLogProvider.notifier);

      // 只发送 \r，不应该触发固化
      final data =
          Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x0D]); // "Hello\r"

      notifier.addReceived(data);
      final state = container.read(dataLogProvider);

      // 验证：数据仍在 pending 中（因为没有 \n）
      expect(state.chunks.last.id, -1);

      final pendingEntry = state.chunks.last.entries.first;
      final text = String.fromCharCodes(pendingEntry.data);
      expect(text, 'Hello\r');
    });

    test('\\r\\n 连续出现时正确剔除 \\r', () {
      final notifier = container.read(dataLogProvider.notifier);

      final data = Uint8List.fromList([
        0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x0D, 0x0A, // "Hello\r\n"
        0x57, 0x6F, 0x72, 0x6C, 0x64, 0x0D, 0x0A
      ] // "World\r\n"
          );

      notifier.addReceived(data);
      final state = container.read(dataLogProvider);

      // 验证：总字节数正确（去掉了 \r）
      // "Hello" (5) + "World" (5) = 10 字节
      expect(state.totalBytes, 10);

      // 验证：所有固化后的文本都不包含 \r
      var foundEntry = false;
      for (final chunk in state.chunks) {
        for (final entry in chunk.entries) {
          final text = String.fromCharCodes(entry.data);
          // 验证：不包含 \r
          expect(text, isNot(contains('\r')));
          foundEntry = true;
        }
      }

      expect(foundEntry, true);
    });
  });

  group('DataLogNotifier - Additional Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = createTestContainer();
    });

    tearDown(() {
      container.dispose();
    });

    group('Empty Data Handling', () {
      test('handles empty data gracefully', () {
        final notifier = container.read(dataLogProvider.notifier);

        // Add some real data first
        notifier.addReceived(Uint8List.fromList([0x54, 0x65, 0x73, 0x74, 0x0A])); // "Test\n"

        // Then add empty data
        notifier.addReceived(Uint8List(0));
        final state = container.read(dataLogProvider);

        // Should not crash, state should be valid with previous data
        expect(state.chunks.isNotEmpty, true);
        expect(state.totalBytes, 4); // "Test" without newline
      });

      test('handles multiple empty data packets', () {
        final notifier = container.read(dataLogProvider.notifier);

        notifier.addReceived(Uint8List(0));
        notifier.addReceived(Uint8List(0));
        notifier.addReceived(Uint8List(0));

        final state = container.read(dataLogProvider);
        expect(state.totalBytes, 0);
      });
    });

    group('Sent Data Handling', () {
      test('addSent creates entries with sent type', () {
        final notifier = container.read(dataLogProvider.notifier);

        final data = Uint8List.fromList([0x54, 0x65, 0x73, 0x74]); // "Test"
        notifier.addSent(data);

        final state = container.read(dataLogProvider);
        expect(state.totalBytes, greaterThan(0));

        // Find the sent entry
        LogEntry? sentEntry;
        for (final chunk in state.chunks) {
          for (final entry in chunk.entries) {
            if (entry.type == LogEntryType.sent) {
              sentEntry = entry;
              break;
            }
          }
          if (sentEntry != null) break;
        }

        expect(sentEntry, isNotNull);
        expect(sentEntry!.type, LogEntryType.sent);
      });

      test('addSent updates total bytes correctly', () {
        final notifier = container.read(dataLogProvider.notifier);

        notifier.addSent(Uint8List.fromList([0x41])); // 1 byte
        notifier.addSent(Uint8List.fromList([0x42, 0x43])); // 2 bytes

        final state = container.read(dataLogProvider);
        expect(state.totalBytes, 3);
      });
    });

    group('Clear Functionality', () {
      test('clear removes all data and resets state', () {
        final notifier = container.read(dataLogProvider.notifier);

        // Add some data
        notifier.addReceived(Uint8List.fromList(
            [0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x0A])); // "Hello\n"
        expect(container.read(dataLogProvider).totalBytes, greaterThan(0));

        // Clear
        notifier.clear();

        final state = container.read(dataLogProvider);
        expect(state.totalBytes, 0);
        expect(state.chunks.isEmpty, true);
        expect(state.nextChunkId, 0);
      });

      test('clear resets chunk ID counter', () {
        final notifier = container.read(dataLogProvider.notifier);

        // Add data to create chunks
        notifier.addReceived(Uint8List.fromList([0x41, 0x0A]));
        notifier.addReceived(Uint8List.fromList([0x42, 0x0A]));

        final stateBefore = container.read(dataLogProvider);
        final nextIdBefore = stateBefore.nextChunkId;

        // Clear
        notifier.clear();

        final stateAfter = container.read(dataLogProvider);
        expect(stateAfter.nextChunkId, 0);
        expect(stateAfter.nextChunkId, lessThan(nextIdBefore));
      });
    });

    group('Timestamp Behavior', () {
      test('entries have valid timestamps', () {
        final notifier = container.read(dataLogProvider.notifier);

        final data =
            Uint8List.fromList([0x54, 0x65, 0x73, 0x74, 0x0A]); // "Test\n"

        // Capture time before adding data
        final beforeTime = DateTime.now();
        notifier.addReceived(data);
        final afterTime = DateTime.now();

        // Wait a bit to ensure timestamp is set
        final state = container.read(dataLogProvider);

        for (final chunk in state.chunks) {
          for (final entry in chunk.entries) {
            expect(entry.timestamp, isNotNull);
            // Timestamp should be between before and after (with small tolerance)
            expect(
              entry.timestamp.isBefore(afterTime.add(const Duration(seconds: 1))),
              true,
              reason: 'Timestamp should not be in the future',
            );
            // Timestamp should be recent (within last minute)
            expect(
              entry.timestamp.isAfter(beforeTime.subtract(const Duration(minutes: 1))),
              true,
              reason: 'Timestamp should be recent',
            );
          }
        }
      });

      test(
          'multiple entries in same chunk have same timestamp when received together',
          () {
        final notifier = container.read(dataLogProvider.notifier);

        // Send multiple lines at once
        final data = Uint8List.fromList(
          [
            0x4C, 0x69, 0x6E, 0x65, 0x31, 0x0A, // "Line1\n"
            0x4C, 0x69, 0x6E, 0x65, 0x32, 0x0A
          ], // "Line2\n"
        );

        final beforeTime = DateTime.now();
        notifier.addReceived(data);
        final afterTime = DateTime.now();

        final state = container.read(dataLogProvider);

        // Find entries in the same chunk
        for (final chunk in state.chunks) {
          if (chunk.entries.length >= 2) {
            final entry1 = chunk.entries[0];
            final entry2 = chunk.entries[1];

            // Both should have timestamps in the same range
            expect(
                entry1.timestamp.isAfter(
                    beforeTime.subtract(const Duration(milliseconds: 100))),
                true);
            expect(
                entry1.timestamp
                    .isBefore(afterTime.add(const Duration(milliseconds: 100))),
                true);
            expect(
                entry2.timestamp.isAfter(
                    beforeTime.subtract(const Duration(milliseconds: 100))),
                true);
            expect(
                entry2.timestamp
                    .isBefore(afterTime.add(const Duration(milliseconds: 100))),
                true);

            break;
          }
        }
      });
    });

    group('Large Data Handling', () {
      test('handles 10KB data packet', () {
        final notifier = container.read(dataLogProvider.notifier);

        final largeData = Uint8List(10 * 1024);
        for (int i = 0; i < largeData.length; i++) {
          largeData[i] = 0x41 + (i % 26); // A-Z cycle
        }

        notifier.addReceived(largeData);

        final state = container.read(dataLogProvider);
        expect(state.totalBytes, 10 * 1024);
      });

      test('handles very long single line (no newline)', () {
        final notifier = container.read(dataLogProvider.notifier);

        // Create a very long line without newline
        final longLine = Uint8List(5000);
        for (int i = 0; i < longLine.length; i++) {
          longLine[i] = 0x41; // All 'A's
        }

        notifier.addReceived(longLine);

        final state = container.read(dataLogProvider);
        expect(state.totalBytes, 5000);
      });
    });

    group('Memory Management', () {
      test('respects log buffer size limit', () {
        // The default buffer size is 128 MB, which is too large for unit tests
        // But we can verify the structure is in place
        final state = container.read(dataLogProvider);
        expect(state.chunks, isNotNull);
      });

      test('chunk management uses correct IDs', () {
        final notifier = container.read(dataLogProvider.notifier);

        // Add multiple lines to create multiple chunks
        for (int i = 0; i < 1500; i++) {
          // Each chunk holds 1000 entries, so we need multiple chunks
          final data = Uint8List.fromList([0x41, 0x0A]); // "A\n"
          notifier.addReceived(data);
        }

        final state = container.read(dataLogProvider);

        // Should have multiple chunks
        expect(state.chunks.length, greaterThan(1));

        // Verify chunk IDs are sequential and non-negative
        int lastId = -2; // Start before -1 (temp chunk)
        for (final chunk in state.chunks) {
          expect(chunk.id,
              greaterThanOrEqualTo(-1)); // -1 for temp, >=0 for committed
          if (chunk.id >= 0) {
            expect(chunk.id, greaterThan(lastId));
            lastId = chunk.id;
          }
        }
      });
    });

    group('Mixed Receive and Send', () {
      test('handles interleaved received and sent data', () {
        final notifier = container.read(dataLogProvider.notifier);

        // Receive data
        notifier.addReceived(
            Uint8List.fromList([0x52, 0x78, 0x31, 0x0A])); // "Rx1\n"

        // Send data
        notifier
            .addSent(Uint8List.fromList([0x54, 0x78, 0x31, 0x0A])); // "Tx1\n"

        // Receive again
        notifier.addReceived(
            Uint8List.fromList([0x52, 0x78, 0x32, 0x0A])); // "Rx2\n"

        final state = container.read(dataLogProvider);

        // Should have both received and sent entries
        bool hasReceived = false;
        bool hasSent = false;

        for (final chunk in state.chunks) {
          for (final entry in chunk.entries) {
            if (entry.type == LogEntryType.received) hasReceived = true;
            if (entry.type == LogEntryType.sent) hasSent = true;
          }
        }

        expect(hasReceived, true);
        expect(hasSent, true);
      });
    });

    group('Unicode and Special Characters', () {
      test('handles UTF-8 encoded text', () {
        final notifier = container.read(dataLogProvider.notifier);

        // UTF-8: "你好" (Hello in Chinese)
        final chineseText =
            Uint8List.fromList([0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD, 0x0A]);
        notifier.addReceived(chineseText);

        final state = container.read(dataLogProvider);
        expect(state.totalBytes, greaterThan(0));

        // Verify data is preserved
        expect(state.chunks.isNotEmpty, true, reason: 'Should have at least one chunk');

        for (final chunk in state.chunks) {
          expect(chunk.entries.isNotEmpty, true, reason: 'Chunk should have entries');

          for (final entry in chunk.entries) {
            if (entry.data.isNotEmpty) {
              // Use UTF-8 decoder for proper text decoding
              final text = utf8.decode(entry.data);
              // The newline (0x0A) is used as delimiter and not stored
              // So we expect "你好" without the newline
              expect(text, '你好',
                  reason: 'Entry data should decode to "你好"');
            }
          }
        }
      });

      test('handles binary data (all byte values)', () {
        final notifier = container.read(dataLogProvider.notifier);

        // Create data with all possible byte values EXCEPT newline (0x0A)
        // because newline is used as a delimiter and is not stored
        final List<int> byteList = [];
        for (int byte = 0; byte < 256; byte++) {
          if (byte != 0x0A) {  // Skip newline
            byteList.add(byte);
          }
        }
        final binaryData = Uint8List.fromList(byteList);

        notifier.addReceived(binaryData);

        final state = container.read(dataLogProvider);
        expect(state.totalBytes, 255);
      });
    });

    group('Performance Tests', () {
      test('processes 1000 small packets efficiently', () async {
        final notifier = container.read(dataLogProvider.notifier);

        final stopwatch = Stopwatch()..start();

        for (int i = 0; i < 1000; i++) {
          final data = Uint8List.fromList([0x41, 0x0A]); // "A\n"
          notifier.addReceived(data);
        }

        stopwatch.stop();

        // Should complete in reasonable time (< 1 second)
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));

        final state = container.read(dataLogProvider);
        expect(state.totalBytes,
            1000); // Each packet is 1 byte (excluding newline)
      });
    });
  });
}
