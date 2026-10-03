import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:twitch_freedom_ultra/streaming/streaming_backend_client.dart';

void main() {
  test('health decodes encrypted media protocol', () async {
    final client = StreamingBackendClient(
      baseUri: Uri.parse('https://stream.example.test'),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/health');
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response(
          jsonEncode(<String, Object?>{
            'region': 'nyc3',
            'version': '2.0.0',
            'encrypted_media_protocol': 2,
          }),
          200,
        );
      }),
    );

    final health = await client.health();

    expect(health.reachable, isTrue);
    expect(health.region, 'nyc3');
    expect(health.encryptedMediaProtocol, 2);
  });

  test('createSession sends replay key and parses secure media ticket', () async {
    final key = base64UrlEncode(List<int>.generate(32, (index) => index));
    final nonce = base64UrlEncode(List<int>.generate(8, (index) => index + 1));
    final client = StreamingBackendClient(
      baseUri: Uri.parse('https://stream.example.test'),
      accessTokenProvider: () async => 'short-lived-token',
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/streaming/sessions');
        expect(request.headers['authorization'], 'Bearer short-lived-token');
        expect(request.headers['x-idempotency-key'], isNotEmpty);
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['channel'], 'examplechannel');
        expect(body['audio_only'], isTrue);
        expect(body['protocol_version'], 2);
        return http.Response(
          jsonEncode(<String, Object?>{
            'session_id': 'session-1',
            'playback_url': 'https://stream.example.test/play/session-1.m3u8',
            'websocket_url': 'wss://stream.example.test/ws/session-1',
            'websocket_token': 'session-scoped-stream-token',
            'expires_at': '2026-10-03T12:00:00Z',
            'chunk_target_ms': 1000,
            'max_buffer_ms': 10000,
            'crypto': <String, Object?>{
              'media_key_b64': key,
              'nonce_prefix_b64': nonce,
              'cipher': 'AES-256-GCM',
              'protocol_version': 2,
            },
          }),
          201,
        );
      }),
    );

    final ticket = await client.createSession(
      channel: 'ExampleChannel',
      quality: 'audio_only',
      audioOnly: true,
    );

    expect(ticket.sessionId, 'session-1');
    expect(ticket.chunkTargetMilliseconds, 1000);
    expect(ticket.maxBufferMilliseconds, 10000);
    expect(ticket.websocketUri.scheme, 'wss');
    expect(ticket.websocketToken, 'session-scoped-stream-token');
    expect(ticket.mediaKey, hasLength(32));
    expect(ticket.noncePrefix, hasLength(8));
    expect(ticket.protocolVersion, 2);
  });
}
