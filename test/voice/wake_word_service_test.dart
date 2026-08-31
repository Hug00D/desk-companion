import 'dart:typed_data';

import 'package:desk_companion/voice/pcm_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pcm16LittleEndianToFloat32', () {
    test('converts signed little-endian PCM samples', () {
      final samples = pcm16LittleEndianToFloat32(
        Uint8List.fromList(<int>[
          0x00,
          0x00,
          0xFF,
          0x7F,
          0x00,
          0x80,
          0x00,
          0xC0,
        ]),
      );

      expect(samples, hasLength(4));
      expect(samples[0], 0);
      expect(samples[1], closeTo(32767 / 32768, 0.00001));
      expect(samples[2], -1);
      expect(samples[3], -0.5);
    });

    test('combines a carried byte with the next chunk', () {
      final samples = pcm16LittleEndianToFloat32(
        Uint8List.fromList(<int>[0x80]),
        leadingByte: 0x00,
      );

      expect(samples, hasLength(1));
      expect(samples.single, -1);
    });
  });
}
