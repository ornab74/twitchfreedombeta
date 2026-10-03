import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Mobile-facing gateway for the DigitalOcean streaming node.
///
/// Twitch credentials stay out of this class. The app authenticates to the
/// backend with a short-lived bearer token minted by the backend's auth layer;
/// the node owns server-side Twitch/EventSub credentials and other secrets.
final class StreamingBackendClient {
  StreamingBackendClient({
    required Uri baseUri,
    http.Client? httpClient,
    Future<String?> Function()? accessTokenProvider,
  }) : _baseUri = baseUri,
       _http = httpClient ?? http.Client(),
       _accessTokenProvider = accessTokenProvider;

  factory StreamingBackendClient.fromEnvironment({
    http.Client? httpClient,
    Future<String?> Function()? accessTokenProvider,
  }) {
    const raw = String.fromEnvironment(
      'STREAMING_BACKEND_URL',
      defaultValue: 'https://stream.invalid',
    );
    return StreamingBackendClient(
      baseUri: Uri.parse(raw),
      httpClient: httpClient,
      accessTokenProvider: accessTokenProvider,
    );
  }

  final Uri _baseUri;
  final http.Client _http;
  final Future<String?> Function()? _accessTokenProvider;

  static const Duration _requestTimeout = Duration(seconds: 12);

  Uri get baseUri => _baseUri;

  Future<BackendHealth> health() async {
    final response = await _send('GET', '/v1/health', authenticated: false);
    final body = _decodeObject(response.body);
    return BackendHealth(
      reachable: response.statusCode >= 200 && response.statusCode < 300,
      region: body['region']?.toString() ?? '',
      version: body['version']?.toString() ?? '',
      websocketReady: body['websocket_ready'] == true,
      twitchReady: body['twitch_ready'] == true,
    );
  }

  Future<StreamingSessionTicket> createSession({
    required String channel,
    required String quality,
    required bool audioOnly,
    bool lowLatency = true,
  }) async {
    final response = await _send(
      'POST',
      '/v1/streaming/sessions',
      body: <String, Object?>{
        'channel': channel.trim().toLowerCase(),
        'quality': quality,
        'audio_only': audioOnly,
        'low_latency': lowLatency,
        'client': 'flutter-mobile',
      },
    );
    _requireSuccess(response, operation: 'create streaming session');
    final body = _decodeObject(response.body);
    return StreamingSessionTicket.fromJson(body);
  }

  Future<void> heartbeat({
    required String sessionId,
    required int bufferedMilliseconds,
    required bool background,
  }) async {
    final response = await _send(
      'POST',
      '/v1/streaming/sessions/$sessionId/heartbeat',
      body: <String, Object?>{
        'buffered_ms': bufferedMilliseconds,
        'background': background,
      },
    );
    _requireSuccess(response, operation: 'heartbeat streaming session');
  }

  Future<void> endSession(String sessionId) async {
    final response = await _send(
      'DELETE',
      '/v1/streaming/sessions/$sessionId',
    );
    if (response.statusCode == 404) return;
    _requireSuccess(response, operation: 'end streaming session');
  }

  Future<http.Response> _send(
    String method,
    String path, {
    bool authenticated = true,
    Map<String, Object?>? body,
  }) async {
    final uri = _baseUri.resolve(path);
    final headers = <String, String>{
      'accept': 'application/json',
      'content-type': 'application/json',
      'x-client-capability': 'streaming-v1',
    };
    if (authenticated) {
      final token = await _accessTokenProvider?.call();
      if (token != null && token.isNotEmpty) {
        headers['authorization'] = 'Bearer $token';
      }
    }

    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _http.send(request).timeout(_requestTimeout);
    return http.Response.fromStream(streamed);
  }

  static Map<String, Object?> _decodeObject(String source) {
    if (source.trim().isEmpty) return const <String, Object?>{};
    final decoded = jsonDecode(source);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Expected a JSON object from backend.');
    }
    return Map<String, Object?>.from(decoded);
  }

  static void _requireSuccess(
    http.Response response, {
    required String operation,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw StreamingBackendException(
      operation: operation,
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }

  void close() => _http.close();
}

final class BackendHealth {
  const BackendHealth({
    required this.reachable,
    required this.region,
    required this.version,
    required this.websocketReady,
    required this.twitchReady,
  });

  final bool reachable;
  final String region;
  final String version;
  final bool websocketReady;
  final bool twitchReady;
}

final class StreamingSessionTicket {
  const StreamingSessionTicket({
    required this.sessionId,
    required this.playbackUri,
    required this.websocketUri,
    required this.expiresAt,
    required this.chunkTargetMilliseconds,
    required this.maxBufferMilliseconds,
  });

  factory StreamingSessionTicket.fromJson(Map<String, Object?> json) {
    final playback = Uri.tryParse(json['playback_url']?.toString() ?? '');
    final websocket = Uri.tryParse(json['websocket_url']?.toString() ?? '');
    final expires = DateTime.tryParse(json['expires_at']?.toString() ?? '');
    if (playback == null || websocket == null || expires == null) {
      throw const FormatException('Backend returned an invalid session ticket.');
    }
    return StreamingSessionTicket(
      sessionId: json['session_id']?.toString() ?? '',
      playbackUri: playback,
      websocketUri: websocket,
      expiresAt: expires,
      chunkTargetMilliseconds:
          (json['chunk_target_ms'] as num?)?.toInt() ?? 1500,
      maxBufferMilliseconds: (json['max_buffer_ms'] as num?)?.toInt() ?? 8000,
    );
  }

  final String sessionId;
  final Uri playbackUri;
  final Uri websocketUri;
  final DateTime expiresAt;
  final int chunkTargetMilliseconds;
  final int maxBufferMilliseconds;
}

final class StreamingBackendException implements Exception {
  const StreamingBackendException({
    required this.operation,
    required this.statusCode,
    required this.responseBody,
  });

  final String operation;
  final int statusCode;
  final String responseBody;

  @override
  String toString() =>
      'StreamingBackendException($operation, HTTP $statusCode)';
}
