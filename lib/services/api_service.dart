import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late Dio dio;
  final _storage = const FlutterSecureStorage();
  late Box _offlineQueueBox;

  ApiService._internal() {
    var baseUrl = dotenv.env['API_BASE_URL'] ?? 'https://soulsyncc.site/soulpages/app/';
    if (!baseUrl.endsWith('/')) {
      baseUrl += '/';
    }
    
    print("API BASE URL: $baseUrl");
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // ── Direct Route Translation ──
        // Convert /chat/send → api.php?route=chat/send
        // This bypasses .htaccess mod_rewrite which fails on shared hosting
        String path = options.path;
        if (!path.contains('api.php')) {
          path = path.startsWith('/') ? path.substring(1) : path;
          // If the path already has query params, append with &
          if (path.contains('?')) {
            final parts = path.split('?');
            options.path = 'api.php?route=${parts[0]}&${parts.sublist(1).join('&')}';
          } else {
            options.path = 'api.php?route=$path';
          }
        }

        final apiKey = dotenv.env['API_KEY'];
        if (apiKey != null && apiKey.isNotEmpty) {
          options.headers['X-API-Key'] = apiKey;
        }
        final token = await _storage.read(key: 'jwt_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) async {
        // Retry logic for transient/connection errors
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            (e.response != null && e.response!.statusCode != null && e.response!.statusCode! >= 500)) {
          final requestOptions = e.requestOptions;
          int retries = requestOptions.extra['retries'] ?? 0;
          if (retries < 1) {
            retries++;
            requestOptions.extra['retries'] = retries;
            await Future.delayed(const Duration(seconds: 2));
            try {
              final response = await dio.fetch(requestOptions);
              return handler.resolve(response);
            } catch (retryError) {
              if (retryError is DioException) {
                e = retryError;
              }
            }
          }
        }

        // If network issue, check if we can queue the request for offline sync
        if (e.type == DioExceptionType.connectionTimeout || 
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.connectionError) {
          _queueOfflineRequest(e.requestOptions);
        }
        return handler.next(e);
      },
    ));
  }

  Future<void> init() async {
    _offlineQueueBox = await Hive.openBox('offline_requests_queue');
    syncOfflineRequests();
  }

  static const _nativeChannel = MethodChannel('com.soulsync.app/permissions');

  // Save Token (also syncs to native SharedPreferences for Kotlin service)
  Future<void> saveToken(String token) async {
    await _storage.write(key: 'jwt_token', value: token);
    // Sync to native SharedPreferences so SoulSyncService can use it
    try {
      await _nativeChannel.invokeMethod('startForegroundService', {'token': token});
    } catch (_) {}
  }

  // Get Token
  Future<String?> getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  // Clear Session
  Future<void> clearSession() async {
    await _storage.delete(key: 'jwt_token');
    try {
      await _nativeChannel.invokeMethod('stopForegroundService');
    } catch (_) {}
  }

  // Queue request when offline
  void _queueOfflineRequest(RequestOptions options) {
    if (options.method == 'POST' && options.path.contains('tracking')) {
      final queueItem = {
        'path': options.path,
        'data': options.data,
        'timestamp': DateTime.now().toIso8601String(),
      };
      _offlineQueueBox.add(queueItem);
    }
  }

  // Sync queued requests when back online
  Future<void> syncOfflineRequests() async {
    if (_offlineQueueBox.isEmpty) return;

    final List keysToRemove = [];
    for (var key in _offlineQueueBox.keys) {
      final item = _offlineQueueBox.get(key);
      try {
        final response = await dio.post(item['path'], data: item['data']);
        if (response.statusCode == 200 || response.statusCode == 201) {
          keysToRemove.add(key);
        }
      } catch (e) {
        print("Failed to sync offline item: $e");
        break; // Stop syncing to avoid spamming / out-of-order execution
      }
    }

    for (var key in keysToRemove) {
      await _offlineQueueBox.delete(key);
    }
  }

  // POST Request Helper
  Future<Response> post(String path, {dynamic data}) async {
    return await dio.post(path, data: data);
  }

  // GET Request Helper
  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) async {
    return await dio.get(path, queryParameters: queryParameters);
  }

  // PATCH Request Helper
  Future<Response> patch(String path, {dynamic data}) async {
    return await dio.patch(path, data: data);
  }

  // DELETE Request Helper
  Future<Response> delete(String path, {dynamic data}) async {
    return await dio.delete(path, data: data);
  }
}
