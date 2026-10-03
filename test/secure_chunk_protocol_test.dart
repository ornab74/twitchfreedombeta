import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/streaming/secure_chunk_protocol.dart';

void main() {
  test('secure chunk v2 uses bounded authenticated packet layout', () async {
    final frame = SecureStreamingChunkFrame(
      sequence: 42,
      durationMilliseconds: 1000,
      keyframe: true,
      contentType: 'video/mp2t',
      payload: Uint8List.fromList(List<int>.generate(1024, (i) => i & 0xff)),
    );
    final encoded = await frame.encode(
      mediaKey: Uint8List.fromList(List<int>.generate(32, (i) => i)),
      noncePrefix: Uint8List.fromList(List<int>.generate(8, (i) => i + 7)),
    );

    expect(encoded[0], SecureStreamingChunkFrame.protocolVersion);
    expect(encoded.length, greaterThan(frame.payload.length));
    expect(encoded.length, lessThan(SecureStreamingChunkFrame.maximumPacketBytes));
  });

  test('secure chunk rejects nonce-prefix reuse preconditions', () async {
    final frame = SecureStreamingChunkFrame(
      sequence: 1,
      durationMilliseconds: 1000,
      keyframe: false,
      contentType: 'video/mp4',
      payload: Uint8List.fromList(<int>[1, 2, 3]),
    );

    expect(
      () => frame.encode(
        mediaKey: Uint8List(32),
        noncePrefix: Uint8List(7),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
