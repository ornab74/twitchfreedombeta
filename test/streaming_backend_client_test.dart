import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:twitch_freedom_ultra/streaming/streaming_backend_client.dart';

void main() {
  test('health decodes backend capability state', () async {
    final client = StreamingBackendClient(
      baseUri: Uri.parse('https://stream.example.test'),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/health');
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response(
          jsonEncode(<String, Object?>{
            'region': 'nyc3',
            'version': '1.0.0',
            'websocket_ready': true,
            'twitch_ready': true,
          }),
          200,
        );
      }),
    );

    final health = await client.health();

    expect(health.reachable, isTrue);
    expect(health.region, 'nyc3');
    expect(health.websocketReady, isTrue);
    expect(health.twitchReady, isTrue);
  });

  test('createSession sends bearer token and parses chunk policy', () async {
    final client = StreamingBackendClient(
      baseUri: Uri.parse('https://stream.example.test'),
      accessTokenProvider: () async => 'short-lived-token',
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/streaming/sessions');
        expect(request.headers['authorization'], 'Bearer short-lived-token');
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['channel'], 'examplechannel');
        expect(body['audio_only'], isTrue);
        return http.Response(
          jsonEncode(<String, Object?>{
            'session_id': 'session-1',
            'playback_url': 'https://stream.example.test/play/session-1.m3u8',
            'websocket_url': 'wss://stream.example.test/ws/session-1',
            'expires_at': '2026-10-03T12:00:00Z',
            'chunk_target_ms': 1200,
            'max_buffer_ms': 7000,
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
    expect(ticket.chunkTargetMilliseconds, 1200);
    expect(ticket.maxBufferMilliseconds, 7000);
    expect(ticket.websocketUri.scheme, 'wss');
  });
}
