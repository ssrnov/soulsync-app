import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/api_service.dart';
import 'services/controllers.dart';
import 'screens/auth_screens.dart';
import 'screens/wizard_screens.dart';
import 'screens/main_navigation.dart';
import 'services/permission_manager.dart';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'screens/clock_screen.dart';
import 'services/notif_service.dart';
import 'firebase_options.dart';

String startRoute = '/';

// Runs in a separate isolate when a data push arrives while the app is in the
// background or terminated. Builds a readable (stacked) chat notification.
// Background data handler. Chat notifications are now shown by the FCM system
// notification block (reliable on every phone + carries the disguised text), so
// this no longer builds a notification — that would duplicate the system one.
@pragma('vm:entry-point')
Future<void> firebaseBgHandler(RemoteMessage m) async {
  // Intentionally a no-op (kept registered so FCM background delivery stays warm).
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Handle data pushes in the background/terminated state (readable chat notifs).
    FirebaseMessaging.onBackgroundMessage(firebaseBgHandler);
  } catch (e) {
    print("Warning: Firebase failed to initialize: $e");
  }
  
  // Initialize Dotenv
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    print("Warning: Dotenv failed to load. Using defaults.");
  }

  // Push API config to native so background services can upload data.
  try {
    await PermissionManager.setApiConfig(
      dotenv.env['API_BASE_URL'] ?? '',
      dotenv.env['API_KEY'] ?? '',
    );
  } catch (e) {
    print("Warning: could not set native API config: $e");
  }

  // Initialize Hive Caching DB
  try {
    await Hive.initFlutter();
  } catch (e) {
    print("Warning: Hive failed to initialize: $e");
  }

  // Local notifications (readable, stacked chat messages). Tapping opens Chat.
  try {
    await initLocalNotifications(onTap: (resp) {
      try { Get.find<NavigationController>().selectedIndex.value = 1; } catch (_) {}
      clearChatNotifications();
    });
  } catch (e) {
    print("Warning: local notifications init failed: $e");
  }
  
  // Initialize API Service
  try {
    final apiService = ApiService();
    await apiService.init();
  } catch (e) {
    print("Warning: ApiService failed to initialize: $e");
  }

  // Disguise: if the user turned on Clock mode, the app opens as a clock and only
  // unlocks with the secret time. (The old Calculator disguise has been removed.)
  bool disguiseOn = false;
  String disguiseType = 'clock';
  try {
    const store = FlutterSecureStorage();
    disguiseOn = (await store.read(key: 'disguise_on')) == '1';
    disguiseType = (await store.read(key: 'disguise_type')) ?? 'clock';
  } catch (_) {}
  // Only the Clock disguise remains; any leftover 'calculator' value opens normally.
  startRoute = (disguiseOn && disguiseType == 'clock') ? '/clock' : '/';

  // Load controllers
  Get.put(AuthController(), permanent: true);
  Get.put(PermissionController(), permanent: true);
  Get.put(ThemeController(), permanent: true);

  // Catch synchronous errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    reportCrash(details.exception, details.stack);
  };

  // Catch asynchronous errors
  PlatformDispatcher.instance.onError = (error, stack) {
    reportCrash(error, stack);
    return true;
  };

  runApp(const SoulSyncApp());
}

Future<void> reportCrash(Object error, StackTrace? stack) async {
  try {
    print("Capturing crash: $error");
    final device = await PermissionManager.getDeviceInfo();
    final api = ApiService();
    final token = await api.getToken();
    if (token == null) return; // Skip if user is not authenticated yet
    
    await api.post('/crash', data: {
      'crashReason': error.toString(),
      'stackTrace': stack?.toString() ?? '',
      'deviceModel': device['deviceModel'] ?? 'Unknown',
      'androidVersion': device['androidVersion'] ?? 'Unknown',
      'appVersion': device['appVersion'] ?? '1.0.0',
    });
  } catch (e) {
    print("Failed to send crash report: $e");
  }
}

class SoulSyncApp extends StatelessWidget {
  const SoulSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'SoulSync',
      debugShowCheckedModeBanner: false,
      // Apply the user's Font Size choice app-wide.
      builder: (context, child) {
        final tc = Get.isRegistered<ThemeController>() ? Get.find<ThemeController>() : null;
        return Obx(() => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(tc?.textScale.value ?? 1.0),
          ),
          child: child ?? const SizedBox.shrink(),
        ));
      },
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFFE8467C),
        hintColor: const Color(0xFFE05CB0),
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFE8467C),
          secondary: Color(0xFFE05CB0),
          background: Color(0xFFFAFAFC),
          surface: Colors.white,
          onBackground: Color(0xFF1E293B),
          onSurface: Color(0xFF1E293B),
        ),
        scaffoldBackgroundColor: const Color(0xFFFAFAFC),
        cardColor: Colors.white,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFE8467C),
        hintColor: const Color(0xFFE05CB0),
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE8467C),
          secondary: Color(0xFFE05CB0),
          background: Color(0xFF0F0B1E),
          surface: Color(0xFF1A1526),
          onBackground: Color(0xFFF1F5F9),
          onSurface: Color(0xFFF1F5F9),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0B1E),
        cardColor: const Color(0xFF1A1526),
        useMaterial3: true,
      ),
      // Default is light; ThemeController flips this when the user chooses dark.
      themeMode: ThemeMode.light,
      initialRoute: startRoute,
      getPages: [
        GetPage(name: '/clock', page: () => const ClockScreen()),
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/welcome', page: () => const WelcomeScreen()),
        GetPage(name: '/login', page: () => const LoginScreen()),
        GetPage(name: '/signup', page: () => const SignupScreen()),
        GetPage(name: '/forgot-password', page: () => const ForgotPasswordScreen()),
        GetPage(name: '/reset-password', page: () => const ResetPasswordScreen()),
        GetPage(name: '/wizard', page: () => const PermissionWizardScreen()),
        GetPage(name: '/home', page: () => MainNavigationScreen()),
        GetPage(name: '/call', page: () => const CallScreen()),
      ],
    );
  }
}
