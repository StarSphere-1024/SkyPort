import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:skyport/models/serial_config.dart';

void main() {
  group('SerialConfig', () {
    group('Construction', () {
      test('creates with required portName parameter', () {
        final config = SerialConfig(portName: 'COM1');
        expect(config.portName, 'COM1');
        expect(config.baudRate, 9600); // default
        expect(config.dataBits, 8); // default
        expect(config.parity, SerialPortParity.none); // default
        expect(config.stopBits, 1); // default
        expect(config.autoReconnect, true); // default
      });

      test('creates with all custom parameters', () {
        final config = SerialConfig(
          portName: 'COM3',
          baudRate: 115200,
          dataBits: 7,
          parity: SerialPortParity.even,
          stopBits: 2,
          autoReconnect: false,
        );
        expect(config.portName, 'COM3');
        expect(config.baudRate, 115200);
        expect(config.dataBits, 7);
        expect(config.parity, SerialPortParity.even);
        expect(config.stopBits, 2);
        expect(config.autoReconnect, false);
      });

      test('uses default baudRate when not specified', () {
        final config = SerialConfig(portName: 'COM1');
        expect(config.baudRate, 9600);
      });

      test('uses default dataBits when not specified', () {
        final config = SerialConfig(portName: 'COM1');
        expect(config.dataBits, 8);
      });

      test('uses default parity when not specified', () {
        final config = SerialConfig(portName: 'COM1');
        expect(config.parity, SerialPortParity.none);
      });

      test('uses default stopBits when not specified', () {
        final config = SerialConfig(portName: 'COM1');
        expect(config.stopBits, 1);
      });

      test('uses default autoReconnect when not specified', () {
        final config = SerialConfig(portName: 'COM1');
        expect(config.autoReconnect, true);
      });
    });

    group('copyWith', () {
      test('updates portName while keeping other values', () {
        final original = SerialConfig(
          portName: 'COM1',
          baudRate: 9600,
          dataBits: 8,
          parity: SerialPortParity.none,
          stopBits: 1,
          autoReconnect: true,
        );
        final updated = original.copyWith(portName: 'COM2');

        expect(updated.portName, 'COM2');
        expect(updated.baudRate, 9600);
        expect(updated.dataBits, 8);
        expect(updated.parity, SerialPortParity.none);
        expect(updated.stopBits, 1);
        expect(updated.autoReconnect, true);
      });

      test('updates all fields independently', () {
        final original = SerialConfig(portName: 'COM1');
        final updated = original.copyWith(
          portName: 'COM3',
          baudRate: 115200,
          dataBits: 7,
          parity: SerialPortParity.odd,
          stopBits: 2,
          autoReconnect: false,
        );

        expect(updated.portName, 'COM3');
        expect(updated.baudRate, 115200);
        expect(updated.dataBits, 7);
        expect(updated.parity, SerialPortParity.odd);
        expect(updated.stopBits, 2);
        expect(updated.autoReconnect, false);
      });

      test('creates independent copy - modifying copy does not affect original',
          () {
        final original = SerialConfig(portName: 'COM1', baudRate: 9600);
        final copy = original.copyWith(baudRate: 115200);

        expect(original.baudRate, 9600); // unchanged
        expect(copy.baudRate, 115200); // modified
      });
    });

    group('Equality', () {
      test('considers two configs with same values as equal', () {
        final config1 = SerialConfig(
          portName: 'COM1',
          baudRate: 9600,
          dataBits: 8,
          parity: SerialPortParity.none,
          stopBits: 1,
          autoReconnect: true,
        );
        final config2 = SerialConfig(
          portName: 'COM1',
          baudRate: 9600,
          dataBits: 8,
          parity: SerialPortParity.none,
          stopBits: 1,
          autoReconnect: true,
        );

        // SerialConfig doesn't override ==, so we check properties
        expect(config1.portName, config2.portName);
        expect(config1.baudRate, config2.baudRate);
        expect(config1.dataBits, config2.dataBits);
        expect(config1.parity, config2.parity);
        expect(config1.stopBits, config2.stopBits);
        expect(config1.autoReconnect, config2.autoReconnect);
      });
    });
  });
}
