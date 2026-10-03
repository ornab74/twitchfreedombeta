import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Application-layer encryption for encoded media chunks.
///
/// Transport TLS/WSS remains mandatory. This second layer keeps the encoded
/// media payload opaque to the tunnel/proxy and authenticates the chunk header
/// (sequence, duration, keyframe flag, MIME type) as AEAD associated data.
///
/// Nonces are deterministic inside one session: an 8-byte random prefix minted
/// by Stream Scanner + the uint32 chunk sequence. A sequence must therefore
/// never repeat with the same session key.
final class SecureStreamingChunkFrame {
  const SecureStreamingChunkFrame({
    required this.sequence,
    required this.durationMilliseconds,
    required this.keyframe,
    required this.contentType,
    required this.payload,
  });

  static const int protocolVersion = 2;
  static const int fixedHeaderBytes = 12;
  static const int authenticationTagBytes = 16;
  static const int maximumPacketBytes = 2 * 1024 * 1024;

  final int sequence;
  final int durationMilliseconds;
  final bool keyframe;
  final String contentType;
  final Uint8List payload;

  Future<Uint8List> encode({
    required Uint8List mediaKey,
    required Uint8List noncePrefix,
  }) async {
    if (mediaKey.length != 32) {
      throw ArgumentError.value(mediaKey.length, 'mediaKey', 'Expected 32 bytes.');
    }
    if (noncePrefix.length != 8) {
      throw ArgumentError.value(
        noncePrefix.length,
        'noncePrefix',
        'Expected 8 bytes.',
      );
    }
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

    final mime = Uint8List.fromList(utf8.encode(contentType));
    if (mime.isEmpty || mime.length > 0xffff) {
      throw ArgumentError.value(contentType, 'contentType', 'Invalid MIME type.');
    }
    if (payload.isEmpty) {
      throw ArgumentError.value(payload.length, 'payload', 'Payload is empty.');
    }

    final header = Uint8List(fixedHeaderBytes + mime.length);
    final headerData = ByteData.sublistView(header);
    headerData.setUint8(0, protocolVersion);
    headerData.setUint32(1, sequence, Endian.big);
    headerData.setUint32(5, durationMilliseconds, Endian.big);
    headerData.setUint8(9, keyframe ? 1 : 0);
    headerData.setUint16(10, mime.length, Endian.big);
    header.setRange(fixedHeaderBytes, header.length, mime);

    final nonce = Uint8List(12)..setRange(0, 8, noncePrefix);
    ByteData.sublistView(nonce).setUint32(8, sequence, Endian.big);

    final algorithm = AesGcm.with256bits();
    final box = await algorithm.encrypt(
      payload,
      secretKey: SecretKey(mediaKey),
      nonce: nonce,
      aad: header,
    );
    if (box.mac.bytes.length != authenticationTagBytes) {
      throw StateError('Unexpected AES-GCM authentication tag length.');
    }

    final packet = Uint8List(
      header.length + box.cipherText.length + box.mac.bytes.length,
    );
    if (packet.length > maximumPacketBytes) {
      throw ArgumentError.value(packet.length, 'payload', 'Encrypted chunk is too large.');
    }
    packet.setRange(0, header.length, header);
    packet.setRange(
      header.length,
      header.length + box.cipherText.length,
      box.cipherText,
    );
    packet.setRange(
      header.length + box.cipherText.length,
      packet.length,
      box.mac.bytes,
    );
    return packet;
  }

  static Uint8List decodeBase64Url(String value) {
    var normalized = value.trim();
    final remainder = normalized.length % 4;
    if (remainder != 0) normalized += '=' * (4 - remainder);
    return Uint8List.fromList(base64Url.decode(normalized));
  }
}
