import 'dart:typed_data';

Float32List pcm16LittleEndianToFloat32(
  Uint8List bytes, {
  int? leadingByte,
}) {
  final byteCount = bytes.length + (leadingByte == null ? 0 : 1);
  final sampleCount = byteCount ~/ 2;
  if (sampleCount == 0) return Float32List(0);

  final samples = Float32List(sampleCount);
  var sourceIndex = 0;
  var sampleIndex = 0;

  if (leadingByte != null && bytes.isNotEmpty) {
    final value = leadingByte | (bytes[0] << 8);
    samples[sampleIndex++] = _signedPcm16(value) / 32768.0;
    sourceIndex = 1;
  }

  while (sourceIndex + 1 < bytes.length) {
    final value = bytes[sourceIndex] | (bytes[sourceIndex + 1] << 8);
    samples[sampleIndex++] = _signedPcm16(value) / 32768.0;
    sourceIndex += 2;
  }
  return samples;
}

int _signedPcm16(int value) => value >= 0x8000 ? value - 0x10000 : value;
