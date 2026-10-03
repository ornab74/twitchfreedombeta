import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'secure_chunk_protocol.dart';

/// Mobile-facing gateway for the Stream Scanner / DigitalOcean node.
///
/// Provider credentials stay server-side. The handset uses a device-scoped
/// access token to mint a short-lived stream token, plus a per-session media
/// key used only for application-layer encrypted media chunks.
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
  final Uuid _uuid = const Uuid();

  static const Duration _requestTimeout = Duration(seconds: 12);

  Uri get baseUri => _baseUri;

  Future<BackendHealth> health() async {
    final response = await _send('GET', '/v1/health', authenticated: false);
    final body = _decodeObject(response.body);
    return BackendHealth(
      reachable: response.statusCode >= 200 && response.statusCode < 300,
      region: body['region']?.toString() ?? '',
      version: body['version']?.toString() ?? '',
      encryptedMediaProtocol:
          (body['encrypted_media_protocol'] as num?)?.toInt() ?? 1,
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
      idempotencyKey: _uuid.v4(),
      body: <String, Object?>{
        'channel': channel.trim().toLowerCase(),
        'quality': quality,
        'audio_only': audioOnly,
        'low_latency': lowLatency,
        'client': 'flutter-mobile',
        'protocol_version': 2,
      },
    );
    _requireSuccess(response, operation: 'create streaming session');
    return StreamingSessionTicket.fromJson(_decodeObject(response.body));
  }

  Future<void> heartbeat({
    required StreamingSessionTicket ticket,
    required int bufferedMilliseconds,
    required bool background,
  }) async {
    final response = await _send(
      'POST',
      '/v1/streaming/sessions/${ticket.sessionId}/heartbeat',
      bearerOverride: ticket.websocketToken,
      body: <String, Object?>{
        'buffered_ms': bufferedMilliseconds,
        'background': background,
      },
    );
    _requireSuccess(response, operation: 'heartbeat streaming session');
  }

  Future<void> endSession(StreamingSessionTicket ticket) async {
    final response = await _send(
      'DELETE',
      '/v1/streaming/sessions/${ticket.sessionId}',
      bearerOverride: ticket.websocketToken,
    );
    if (response.statusCode == 404) return;
    _requireSuccess(response, operation: 'end streaming session');
  }

  Future<http.Response> _send(
    String method,
    String path, {
    bool authenticated = true,
    String? bearerOverride,
    String? idempotencyKey,
    Map<String, Object?>? body,
  }) async {
    final uri = _baseUri.resolve(path);
    final headers = <String, String>{
      'accept': 'application/json',
      'content-type': 'application/json',
      'x-client-capability': 'streaming-v2-aead',
    };
    if (idempotencyKey != null) headers['x-idempotency-key'] = idempotencyKey;
    if (authenticated) {
      final token = bearerOverride ?? await _accessTokenProvider?.call();
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
    required this.encryptedMediaProtocol,
  });

  final bool reachable;
  final String region;
  final String version;
  final int encryptedMediaProtocol;
}

final class StreamingSessionTicket {
  const StreamingSessionTicket({
    required this.sessionId,
    required this.playbackUri,
    required this.websocketUri,
    required this.websocketToken,
    required this.expiresAt,
    required this.chunkTargetMilliseconds,
    required this.maxBufferMilliseconds,
    required this.mediaKey,
    required this.noncePrefix,
    required this.protocolVersion,
  });

  factory StreamingSessionTicket.fromJson(Map<String, Object?> json) {
    final playback = Uri.tryParse(json['playback_url']?.toString() ?? '');
    final websocket = Uri.tryParse(json['websocket_url']?.toString() ?? '');
    final expires = DateTime.tryParse(json['expires_at']?.toString() ?? '');
    final crypto = json['crypto'] is Map<Object?, Object?>
        ? Map<String, Object?>.from(json['crypto']! as Map<Object?, Object?>)
        : const <String, Object?>{};
    final websocketToken = json['websocket_token']?.toString() ?? '';
    final keyText = crypto['media_key_b64']?.toString() ?? '';
    final nonceText = crypto['nonce_prefix_b64']?.toString() ?? '';
    final protocol = (crypto['protocol_version'] as num?)?.toInt() ?? 0;
    if (playback == null ||
        websocket == null ||
        expires == null ||
        websocketToken.isEmpty ||
        keyText.isEmpty ||
        nonceText.isEmpty ||
        protocol != SecureStreamingChunkFrame.protocolVersion) {
      throw const FormatException('Backend returned an invalid secure session ticket.');
    }
    final mediaKey = SecureStreamingChunkFrame.decodeBase64Url(keyText);
    final noncePrefix = SecureStreamingChunkFrame.decodeBase64Url(nonceText);
    if (mediaKey.length != 32 || noncePrefix.length != 8) {
      throw const FormatException('Backend returned invalid media key material.');
    }
    return StreamingSessionTicket(
      sessionId: json['session_id']?.toString() ?? '',
      playbackUri: playback,
      websocketUri: websocket,
      websocketToken: websocketToken,
      expiresAt: expires,
      chunkTargetMilliseconds:
          (json['chunk_target_ms'] as num?)?.toInt() ?? 1000,
      maxBufferMilliseconds: (json['max_buffer_ms'] as num?)?.toInt() ?? 10000,
      mediaKey: mediaKey,
      noncePrefix: noncePrefix,
      protocolVersion: protocol,
    );
  }

  final String sessionId;
  final Uri playbackUri;
  final Uri websocketUri;
  final String websocketToken;
  final DateTime expiresAt;
  final int chunkTargetMilliseconds;
  final int maxBufferMilliseconds;
  final Uint8List mediaKey;
  final Uint8List noncePrefix;
  final int protocolVersion;
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
