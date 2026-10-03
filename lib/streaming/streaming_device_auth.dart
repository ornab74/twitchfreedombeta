import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Stores only the device-scoped Stream Scanner credential on the handset.
/// Provider secrets and Twitch stream keys never enter this storage.
final class StreamingDeviceAuth {
  StreamingDeviceAuth({
    required Uri baseUri,
    FlutterSecureStorage? storage,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _storage = storage ?? const FlutterSecureStorage(),
       _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final FlutterSecureStorage _storage;
  final http.Client _http;

  static const _deviceIdKey = 'stream_scanner.device_id';
  static const _deviceSecretKey = 'stream_scanner.device_secret';

  String? _accessToken;
  DateTime? _accessTokenExpiresAt;

  Future<bool> get enrolled async =>
      (await _storage.read(key: _deviceIdKey))?.isNotEmpty == true &&
      (await _storage.read(key: _deviceSecretKey))?.isNotEmpty == true;

  Future<void> enroll({
    required String bootstrapKey,
    required String label,
    required String platform,
    List<String> capabilities = const <String>[
      'streaming-v2',
      'gps-telemetry',
    ],
  }) async {
    final response = await _http.post(
      _baseUri.resolve('/v1/devices/enroll'),
      headers: <String, String>{
        'content-type': 'application/json',
        'accept': 'application/json',
        'x-bootstrap-key': bootstrapKey,
      },
      body: jsonEncode(<String, Object?>{
        'label': label,
        'platform': platform,
        'capabilities': capabilities,
      }),
    );
    if (response.statusCode != 201) {
      throw StateError('Device enrollment failed (${response.statusCode}).');
    }
    final body = _object(response.body);
    final deviceId = body['deviceId']?.toString() ?? '';
    final secret = body['deviceSecret']?.toString() ?? '';
    if (deviceId.isEmpty || secret.length < 20) {
      throw const FormatException('Stream Scanner returned invalid credentials.');
    }
    await _storage.write(key: _deviceIdKey, value: deviceId);
    await _storage.write(key: _deviceSecretKey, value: secret);
    _accessToken = null;
    _accessTokenExpiresAt = null;
  }

  Future<String?> accessToken() async {
    final now = DateTime.now();
    if (_accessToken != null &&
        _accessTokenExpiresAt != null &&
        now.isBefore(_accessTokenExpiresAt!.subtract(const Duration(seconds: 30)))) {
      return _accessToken;
    }
    final deviceId = await _storage.read(key: _deviceIdKey);
    final secret = await _storage.read(key: _deviceSecretKey);
    if (deviceId == null || secret == null) return null;
    final response = await _http.post(
      _baseUri.resolve('/v1/auth/exchange'),
      headers: const <String, String>{
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'device_id': deviceId,
        'device_secret': secret,
      }),
    );
    if (response.statusCode != 200) return null;
    final body = _object(response.body);
    final token = body['access_token']?.toString() ?? '';
    final expires = (body['expires_in'] as num?)?.toInt() ?? 600;
    if (token.isEmpty) return null;
    _accessToken = token;
    _accessTokenExpiresAt = now.add(Duration(seconds: expires));
    return token;
  }

  Future<void> rotateDeviceSecret() async {
    final deviceId = await _storage.read(key: _deviceIdKey);
    final secret = await _storage.read(key: _deviceSecretKey);
    if (deviceId == null || secret == null) {
      throw StateError('Device is not enrolled.');
    }
    final response = await _http.post(
      _baseUri.resolve('/v1/auth/rotate-device-secret'),
      headers: const <String, String>{
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'device_id': deviceId,
        'device_secret': secret,
      }),
    );
    if (response.statusCode != 200) {
      throw StateError('Credential rotation failed (${response.statusCode}).');
    }
    final body = _object(response.body);
    final nextSecret = body['deviceSecret']?.toString() ?? '';
    if (nextSecret.length < 20) {
      throw const FormatException('Stream Scanner returned an invalid secret.');
    }
    await _storage.write(key: _deviceSecretKey, value: nextSecret);
    _accessToken = null;
    _accessTokenExpiresAt = null;
  }

  Future<void> clear() async {
    await _storage.delete(key: _deviceIdKey);
    await _storage.delete(key: _deviceSecretKey);
    _accessToken = null;
    _accessTokenExpiresAt = null;
  }

  static Map<String, Object?> _object(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Expected JSON object.');
    }
    return Map<String, Object?>.from(decoded);
  }

  void close() => _http.close();
}
