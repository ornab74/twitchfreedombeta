import 'dart:convert';
import 'dart:typed_data';

/// Compact binary frame sent over the authenticated ingest WebSocket.
///
/// Layout (big-endian):
/// byte 0: protocol version
/// bytes 1..4: sequence
/// bytes 5..8: duration milliseconds
/// byte 9: flags (bit 0 = keyframe)
/// bytes 10..11: UTF-8 MIME type length
/// bytes 12..N: MIME type + encoded media bytes
final class StreamingChunkFrame {
  const StreamingChunkFrame({
    required this.sequence,
    required this.durationMilliseconds,
    required this.keyframe,
    required this.contentType,
    required this.payload,
  });

  static const int protocolVersion = 1;
  static const int fixedHeaderBytes = 12;
  static const int maximumPayloadBytes = 2 * 1024 * 1024 - fixedHeaderBytes;

  final int sequence;
  final int durationMilliseconds;
  final bool keyframe;
  final String contentType;
  final Uint8List payload;

  Uint8List encode() {
    if (sequence < 0 || sequence > 0xffffffff) {
      throw RangeError.range(sequence, 0, 0xffffffff, 'sequence');
    }
    if (durationMilliseconds < 100 || durationMilliseconds > 5000) {
      throw RangeError.range(
        durationMilliseconds,
        100,
        5000,
        'durationMilliseconds',
      );
    }
    final mime = utf8.encode(contentType);
    if (mime.isEmpty || mime.length > 0xffff) {
      throw ArgumentError.value(contentType, 'contentType', 'Invalid MIME type.');
    }
    if (payload.isEmpty || payload.length > maximumPayloadBytes - mime.length) {
      throw ArgumentError.value(payload.length, 'payload', 'Chunk payload is invalid.');
    }

    final output = Uint8List(fixedHeaderBytes + mime.length + payload.length);
    final bytes = ByteData.sublistView(output);
    bytes.setUint8(0, protocolVersion);
    bytes.setUint32(1, sequence, Endian.big);
    bytes.setUint32(5, durationMilliseconds, Endian.big);
    bytes.setUint8(9, keyframe ? 1 : 0);
    bytes.setUint16(10, mime.length, Endian.big);
    output.setRange(fixedHeaderBytes, fixedHeaderBytes + mime.length, mime);
    output.setRange(fixedHeaderBytes + mime.length, output.length, payload);
    return output;
  }
}
