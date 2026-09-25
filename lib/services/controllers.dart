import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/models.dart';
import '../screens/discover_screens.dart';
import '../screens/main_navigation.dart';
import '../screens/reward_video_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import 'socket_service.dart';
import 'permission_manager.dart';
import 'notif_service.dart';

// Global foreground flag — all background polling is paused when false to keep
// server load (and battery) low.
bool gAppForeground = true;
// True while the user is actively on the Chat tab — used to count daily talk-time
// toward the 10-min streak.
bool gChatActive = false;

// ── Auth Controller ───────────────────────────────────────────────────────────
class AuthController extends GetxController with WidgetsBindingObserver {
  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();

  final Rxn<User> currentUser = Rxn<User>();
  final RxBool isLoading = false.obs;
  final RxBool isLoggedIn = false.obs;
  final RxBool isRestoring = false.obs;
  
  final RxBool isMaintenanceMode = false.obs;
  final RxBool isUpdateRequired = false.obs;
  final RxString updateApkUrl = ''.obs;
  final RxString updateMessage = ''.obs;

  // Games/features locked behind Premium (from admin → Premium Control).
  final RxList<String> premiumLocked = <String>[].obs;

  // In-app ads config (from admin → Monetization).
  final RxBool adsOn = false.obs;              // master + app master
  final RxMap<String, String> appAdCode = <String, String>{}.obs; // placement → HTML code
  final RxMap<String, bool> appAdOn = <String, bool>{}.obs;       // placement → enabled
  final RxMap<String, String> appAdProvider = <String, String>{}.obs; // placement → 'startio' | 'html' | 'image'
  // placement → {image, link} for "My ad" (house image ads uploaded in admin).
  final RxMap<String, Map<String, String>> appHouseAd = <String, Map<String, String>>{}.obs;

  // Which games the admin has enabled (default ON).
  final RxMap<String, bool> gamesEnabled = <String, bool>{}.obs;
  bool gameOn(String key) => gamesEnabled[key] ?? true;

  String adProvider(String placement) => appAdProvider[placement] ?? 'startio';
  Map<String, String>? houseAd(String placement) => appHouseAd[placement];

  // Push notifications on/off (persisted locally).
  final RxBool notificationsOn = true.obs;
  Future<void> loadNotifPref() async {
    try { final box = await Hive.openBox('app_settings'); notificationsOn.value = box.get('notif_on', defaultValue: true); } catch (_) {}
  }
  Future<void> setNotificationsOn(bool v) async {
    notificationsOn.value = v;
    try { final box = await Hive.openBox('app_settings'); await box.put('notif_on', v); } catch (_) {}
    try { await _api.post('/auth/notif-pref', data: {'enabled': v ? 1 : 0}); } catch (_) {}
  }

  // Single Mode: when ON (and NOT paired) the Discover / meet-people features
  // surface on the Home page. It can only be turned on while unpaired; pairing
  // with someone forces it off (enforced here + in the UI).
  final RxString appVersion = ''.obs; // installed app version (shown in About)
  final RxBool singleMode = false.obs;
  Future<void> loadSingleMode() async {
    try { final box = await Hive.openBox('app_settings'); singleMode.value = box.get('single_mode', defaultValue: false); } catch (_) {}
  }
  Future<void> setSingleMode(bool v) async {
    // Can't enable Single Mode while connected to a partner.
    if (v && (currentUser.value?.isPaired ?? false)) { singleMode.value = false; return; }
    singleMode.value = v;
    try { final box = await Hive.openBox('app_settings'); await box.put('single_mode', v); } catch (_) {}
  }
  // Effective single mode = user's choice AND not currently paired.
  bool get singleActive => singleMode.value && !(currentUser.value?.isPaired ?? false);

  // Ad allowed at this placement? (master + placement toggle + not premium)
  // Start.io needs no code; WebView fallback additionally needs a code.
  bool showAppAd(String placement) =>
      adsOn.value && !isPremium && (appAdOn[placement] ?? false);
  bool showAd(String placement) =>
      showAppAd(placement) && (appAdCode[placement] ?? '').trim().isNotEmpty;

  // Premium unlock options (from admin → Monetization).
  final RxBool rewardOn = false.obs;     // watch ad = 1 day premium
  final RxString rewardUrl = ''.obs;
  final RxString rewardHouseVideo = ''.obs; // self-hosted reward MP4 (My Ads)
  final RxString rewardSource = 'my_ad'.obs; // 'my_ad' | 'link'
  final RxBool payOn = false.obs;         // pay to subscribe
  final RxInt subPrice = 99.obs;
  final RxInt subDays = 30.obs;

  bool get isPremium => currentUser.value?.isPremium ?? false;

  // Is this game/feature key locked for a non-premium user?
  bool isLocked(String key) => !isPremium && premiumLocked.contains(key);

  // Open the SoulSync Premium purchase page in the browser.
  Future<void> openPremiumPage() async {
    try {
      final r = await _api.get('/subscription/status');
      final url = (r.data is Map) ? (r.data['data']?['subscribeUrl'] ?? r.data['subscribeUrl'] ?? '') : '';
      if (url is String && url.isNotEmpty) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) { await launchUrl(uri, mode: LaunchMode.externalApplication); return; }
      }
      Get.snackbar("Premium", "Could not open the upgrade page. Try again.");
    } catch (_) {
      Get.snackbar("Premium", "Could not open the upgrade page. Try again.");
    }
  }

  // Watch an ad → grant 1 day premium. Prefers a Start.io rewarded video;
  // falls back to opening the reward link.
  Future<void> _creditReward() async {
    try {
      final r = await _api.post('/subscription/reward');
      if (r.statusCode == 200 && r.data['success'] == true) {
        await restoreSession();
        Get.snackbar("Premium unlocked 💜", "You got 1 day of Premium free!");
        return;
      }
    } catch (_) {}
    Get.snackbar("Reward", "Couldn't credit the reward. Try again.");
  }

  Future<void> watchAdForReward() async {
    // 0) Your own uploaded reward video (My Ads → Reward Video). Plays in-app;
    //    the reward is credited after the user watches ~10 seconds.
    final houseVid = rewardHouseVideo.value;
    if (rewardSource.value == 'my_ad' && houseVid.isNotEmpty) {
      final done = await Get.to<bool>(() => RewardVideoScreen(url: houseVid));
      if (done == true) { await _creditReward(); }
      return;
    }
    // If admin chose "link", skip straight to the link fallback below.
    if (rewardSource.value == 'link') {
      try {
        final url = rewardUrl.value;
        if (url.isNotEmpty) {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        await Future.delayed(const Duration(seconds: 3));
        await _creditReward();
      } catch (_) { Get.snackbar("Reward", "Something went wrong. Try again."); }
      return;
    }

    // Open the reward link, then credit after a short view. (Start.io removed.)
    try {
      final url = rewardUrl.value;
      if (url.isNotEmpty) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      await Future.delayed(const Duration(seconds: 3));
      await _creditReward();
    } catch (_) {
      Get.snackbar("Reward", "Something went wrong. Try again.");
    }
  }

  // Premium options sheet: watch-ad and/or pay, based on admin toggles.
  void openPremiumSheet() {
    if (isPremium) { Get.snackbar("Premium 💜", "You're already a Premium member!"); return; }
    Get.bottomSheet(Container(
      decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(26))),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: const Color(0xFF94A3B8).withOpacity(.35), borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16),
        Text("👑 SoulSync Premium", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Get.theme.colorScheme.onSurface)),
        const SizedBox(height: 4),
        const Text("No ads · everything unlocked 💜", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
        const SizedBox(height: 18),
        if (rewardOn.value)
          _premiumOption("🎬", "Watch an ad", "Get 1 day Premium free", const [Color(0xFF9333EA), Color(0xFF7C3AED)],
              () { Get.back(); watchAdForReward(); }),
        if (rewardOn.value) const SizedBox(height: 12),
        if (payOn.value)
          _premiumOption("💳", "Go Premium", "₹${subPrice.value} / ${subDays.value} days — no ads",
              const [Color(0xFFE8467C), Color(0xFFBE185D)], () { Get.back(); openPremiumPage(); }),
        if (!rewardOn.value && !payOn.value)
          const Padding(padding: EdgeInsets.symmetric(vertical: 10),
            child: Text("Premium isn't available right now.", style: TextStyle(color: Color(0xFF94A3B8)))),
      ]),
    ));
  }

  Widget _premiumOption(String emoji, String title, String sub, List<Color> grad, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: LinearGradient(colors: grad), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ])),
        const Icon(Icons.chevron_right, color: Colors.white),
      ]),
    ),
  );

  // Shows an upgrade sheet when a locked feature is tapped. Returns true if allowed.
  bool guardPremium(String key, {String? label}) {
    if (!isLocked(key)) return true;
    Get.dialog(AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: const [
        Text("👑 ", style: TextStyle(fontSize: 22)),
        Text("Premium feature", style: TextStyle(fontWeight: FontWeight.bold)),
      ]),
      content: Text("${label ?? 'This'} is part of SoulSync Premium. Upgrade to unlock it. 💜"),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text("Not now")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
          onPressed: () { Get.back(); openPremiumSheet(); },
          child: const Text("Upgrade", style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
    return false;
  }

  Timer? _nudgeTimer;
  Timer? _presenceTimer;
  bool _foreground = true;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    restoreSession();
    _setupPushTaps();
    loadNotifPref();
    loadSingleMode();
    PackageInfo.fromPlatform().then((i) => appVersion.value = i.version).catchError((_) => '');
    _nudgeTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (isLoggedIn.value && gAppForeground) {
        checkAndTriggerNudge();
      }
    });
    // Keep presence fresh ONLY while the app is in the foreground.
    _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (isLoggedIn.value && gAppForeground) setPresence(true);
    });
  }

  @override
  void onClose() {
    _nudgeTimer?.cancel();
    _presenceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      gAppForeground = true;
      setPresence(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _foreground = false;
      gAppForeground = false;
      // Do NOT force offline here. Presence now follows the phone SCREEN via the
      // background service (screen on = online). Backgrounding the app while the
      // screen is still on should stay Online; the service marks offline only
      // when the screen actually turns off.
    }
  }

  Future<void> setPresence(bool online) async {
    if (!isLoggedIn.value) return;
    try {
      await _api.post('/presence', data: {'online': online ? 1 : 0});
    } catch (_) {}
  }

  Future<void> restoreSession() async {
    isRestoring.value = true;
    try {
      final token = await _api.getToken();
      if (token != null) {
        try {
          final response = await _api.get('/auth/me').timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 && response.data['success'] == true) {
            currentUser.value = User.fromJson(response.data['data']);
            isLoggedIn.value = true;
            try { _socket.init(); } catch (_) {}
            syncFcmToken();
            setPresence(true);
            syncDisguiseState();
          } else {
            await logout();
          }
        } catch (e) {
          print("restoreSession error: $e");
          if (currentUser.value != null) {
            isLoggedIn.value = true;
          }
        }
      }
    } catch (_) {}
    isRestoring.value = false;
  }

  Future<bool> login(String email, String password) async {
    isLoading.value = true;
    try {
      print("LOGIN: calling ${_api.dio.options.baseUrl}api.php?route=auth/login");
      final response = await _api.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      print("LOGIN: response=${response.statusCode} data=${response.data}");
      if (response.statusCode == 200 && response.data['success'] == true) {
        final token = response.data['data']['token'];
        final userData = response.data['data']['user'];
        await _api.saveToken(token);
        try {
          currentUser.value = User.fromJson(userData);
        } catch (e) {
          currentUser.value = User(
            id: userData['id']?.toString() ?? '',
            username: userData['username']?.toString() ?? '',
            email: userData['email']?.toString() ?? '',
            displayName: userData['displayName']?.toString() ?? userData['username']?.toString() ?? 'User',
            isPaired: false,
            isOnline: false,
          );
        }
        isLoggedIn.value = true;
        try { _socket.init(); } catch (_) {}
        syncFcmToken();
        setPresence(true);
        isLoading.value = false;
        return true;
      } else {
        final msg = response.data?['message'] ?? response.data?['error'] ?? 'Login failed';
        Get.snackbar("Login Failed", msg.toString());
      }
    } on dio_pkg.DioException catch (e) {
      print("LOGIN DioError: type=${e.type} msg=${e.message} url=${e.requestOptions.uri}");
      String msg = 'Login failed.';
      if (e.type == dio_pkg.DioExceptionType.connectionTimeout) {
        msg = 'Connection timeout → ${e.requestOptions.uri}';
      } else if (e.type == dio_pkg.DioExceptionType.receiveTimeout) {
        msg = 'Server took too long to respond';
      } else if (e.type == dio_pkg.DioExceptionType.connectionError) {
        msg = 'Cannot reach server: ${e.message?.substring(0, (e.message?.length ?? 0).clamp(0, 100))}';
      } else if (e.response != null) {
        msg = e.response?.data?['message'] ?? 'Server error ${e.response?.statusCode}';
      } else {
        msg = 'Network error: ${e.type.name}';
      }
      Get.snackbar("Error", msg, duration: const Duration(seconds: 8));
    } catch (e) {
      print("LOGIN error: $e");
      Get.snackbar("Error", "Error: ${e.toString().substring(0, e.toString().length.clamp(0, 150))}", duration: const Duration(seconds: 8));
    }
    isLoading.value = false;
    return false;
  }

  Future<bool> googleSignIn() async {
    isLoading.value = true;
    try {
      print("GOOGLE: starting sign-in");
      final gSign = GoogleSignIn(scopes: ['email', 'profile']);
      final account = await gSign.signIn();
      if (account == null) { print("GOOGLE: user cancelled"); isLoading.value = false; return false; }
      print("GOOGLE: got account ${account.email}");
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        Get.snackbar("Error", "Google sign-in: no token received.");
        isLoading.value = false;
        return false;
      }
      print("GOOGLE: got idToken, calling server...");
      final response = await _api.post('/auth/google', data: {
        'id_token': idToken,
        'name': account.displayName ?? '',
        'email': account.email,
        'photo': account.photoUrl ?? '',
        'device': 'android',
      });
      print("GOOGLE: server response=${response.statusCode}");
      if (response.statusCode == 200 && response.data['success'] == true) {
        final token = response.data['data']['token'];
        final userData = response.data['data']['user'];
        await _api.saveToken(token);
        try {
          currentUser.value = User.fromJson(userData);
        } catch (e) {
          currentUser.value = User(
            id: userData['id']?.toString() ?? '',
            username: userData['username']?.toString() ?? '',
            email: userData['email']?.toString() ?? '',
            displayName: userData['displayName']?.toString() ?? userData['username']?.toString() ?? 'User',
            isPaired: false, isOnline: false,
          );
        }
        isLoggedIn.value = true;
        try { _socket.init(); } catch (_) {}
        syncFcmToken();
        setPresence(true);
        isLoading.value = false;
        return true;
      } else {
        final msg = response.data?['message'] ?? 'Google auth failed on server';
        Get.snackbar("Error", msg.toString(), duration: const Duration(seconds: 8));
      }
    } on dio_pkg.DioException catch (e) {
      print("GOOGLE DioError: type=${e.type} msg=${e.message}");
      String msg = 'Google sign-in: server unreachable';
      if (e.type == dio_pkg.DioExceptionType.connectionTimeout) {
        msg = 'Google: Connection timeout → ${e.requestOptions.uri}';
      } else if (e.type == dio_pkg.DioExceptionType.connectionError) {
        msg = 'Google: Cannot reach server: ${e.message?.substring(0, (e.message?.length ?? 0).clamp(0, 100))}';
      } else if (e.response != null) {
        msg = e.response?.data?['message'] ?? 'Server error ${e.response?.statusCode}';
      }
      Get.snackbar("Error", msg, duration: const Duration(seconds: 8));
    } catch (e) {
      print("GOOGLE error: $e");
      Get.snackbar("Error", "Google: ${e.toString().substring(0, e.toString().length.clamp(0, 150))}", duration: const Duration(seconds: 8));
    }
    isLoading.value = false;
    return false;
  }

  Future<bool> forgotPassword(String email) async {
    isLoading.value = true;
    try {
      final response = await _api.post('/auth/forgot-password', data: {'email': email});
      if (response.statusCode == 200 && response.data['success'] == true) {
        Get.snackbar("Success", response.data['data']['message'] ?? "OTP sent.");
        isLoading.value = false;
        return true;
      }
    } catch (e) {
      Get.snackbar("Error", "Failed to request password reset.");
    }
    isLoading.value = false;
    return false;
  }

  Future<bool> setPasswordViaGoogle(String newPassword) async {
    isLoading.value = true;
    try {
      final response = await _api.post('/profile/set-password', data: {
        'new_password': newPassword,
      });
      if (response.statusCode == 200 && response.data['success'] == true) {
        isLoading.value = false;
        return true;
      }
      Get.snackbar("Error", response.data['message'] ?? "Failed to set password.");
    } catch (e) {
      Get.snackbar("Error", "Failed to set password.");
    }
    isLoading.value = false;
    return false;
  }

  Future<bool> resetPassword(String email, String otp, String newPassword) async {
    isLoading.value = true;
    try {
      final response = await _api.post('/auth/reset-password', data: {
        'email': email,
        'otp': otp,
        'password': newPassword,
      });
      if (response.statusCode == 200 && response.data['success'] == true) {
        Get.snackbar("Success", response.data['data']['message'] ?? "Password updated.");
        isLoading.value = false;
        return true;
      }
    } catch (e) {
      Get.snackbar("Error", "Failed to reset password.");
    }
    isLoading.value = false;
    return false;
  }

  Future<bool> register(String username, String email, String password, {String? name, String? gender}) async {
    isLoading.value = true;
    try {
      final response = await _api.post('/auth/register', data: {
        'username': username,
        'email': email,
        'password': password,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (gender != null && gender.isNotEmpty) 'gender': gender,
      });
      print("register response: ${response.data}");
      if (response.statusCode == 201 && response.data['success'] == true) {
        final token = response.data['data']['token'];
        final userData = response.data['data']['user'];
        await _api.saveToken(token);
        currentUser.value = User.fromJson(userData);
        print("register user invite code: ${currentUser.value?.inviteCode}");
        isLoggedIn.value = true;
        // Socket init — non-critical
        try { _socket.init(); } catch (e) { print("Socket init error (non-fatal): $e"); }
        syncFcmToken();
        setPresence(true);
        isLoading.value = false;
        return true;
      }
    } on dio_pkg.DioException catch (e) {
      final msg = e.response?.data?['message'] ?? 'Registration failed. Try another username/email.';
      Get.snackbar("Error", msg);
    } catch (e) {
      Get.snackbar("Error", "Connection error. Check your internet.");
    }
    isLoading.value = false;
    return false;
  }

  // Sends a connect REQUEST. The partner must accept — this no longer connects
  // instantly. Returns true if the request was sent (or already pending).
  // End the connection with the current partner (soft-disconnect, 10-day restore).
  Future<bool> disconnectPartner() async {
    try {
      final r = await _api.post('/couples/disconnect', data: {});
      if (r.statusCode == 200 && r.data['success'] == true) {
        // Refresh the user so isPaired flips to false everywhere.
        try {
          final me = await _api.get('/auth/me');
          if (me.data['success'] == true) currentUser.value = User.fromJson(me.data['data']);
        } catch (_) {}
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> pairCouple(String inviteCode) async {
    isLoading.value = true;
    try {
      final response = await _api.post('/couples/join', data: {
        'inviteCode': inviteCode,
      });
      final data = response.data;
      if ((response.statusCode == 200 || response.statusCode == 201) && data['success'] == true) {
        isLoading.value = false;
        if (data['data']?['already'] == true) {
          Get.snackbar("Already sent ⏳", "Waiting for them to accept your request.");
        } else {
          Get.snackbar("Request sent 💌", "They'll get to accept or decline. You'll be connected once they accept.");
        }
        return true;
      }
    } on dio_pkg.DioException catch (e) {
      // Surface the real server message (e.g. limit reached, already connected).
      final msg = (e.response?.data is Map) ? (e.response?.data['error']?.toString() ?? '') : '';
      Get.snackbar("Couldn't send", msg.isNotEmpty ? msg : "Pairing failed. Check the username.");
    } catch (e) {
      Get.snackbar("Error", "Pairing failed. Check the username.");
    }
    isLoading.value = false;
    return false;
  }

  // Live check whether a username is free.
  Future<bool> isUsernameAvailable(String username) async {
    try {
      final r = await _api.post('/auth/username-available', data: {'username': username});
      return r.data['data']?['available'] == true;
    } catch (_) { return false; }
  }

  // Change username (server rejects if taken). Returns error message, or null on success.
  Future<String?> changeUsername(String username) async {
    try {
      final r = await _api.post('/auth/change-username', data: {'username': username});
      if (r.data['success'] == true) {
        currentUser.value = User.fromJson(r.data['data']['user']);
        return null;
      }
      return (r.data['error'] ?? 'Could not change username').toString();
    } on dio_pkg.DioException catch (e) {
      final msg = (e.response?.data is Map) ? (e.response?.data['error']?.toString() ?? '') : '';
      return msg.isNotEmpty ? msg : 'That username is not available';
    } catch (_) {
      return 'Something went wrong';
    }
  }

  // Privacy flags (hide online / hide last seen).
  Future<Map<String, bool>> getPrivacyFlags() async {
    try {
      final r = await _api.get('/auth/privacy-flags').timeout(const Duration(seconds: 8));
      final d = r.data['data'] ?? {};
      return {'hideOnline': d['hideOnline'] == true, 'hideLastSeen': d['hideLastSeen'] == true};
    } catch (_) { return {'hideOnline': false, 'hideLastSeen': false}; }
  }
  Future<void> setPrivacyFlag(String key, bool value) async {
    try { await _api.post('/auth/privacy-flags', data: {key: value}); } catch (_) {}
  }

  // Blocked users (Discover blocks). Fast-fails so the screen never hangs.
  Future<List<Map<String, dynamic>>> fetchBlockedUsers() async {
    try {
      final r = await _api.get('/discover/blocks').timeout(const Duration(seconds: 8));
      final list = (r.data['data']?['blocked'] ?? []) as List;
      return list.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) { return []; }
  }
  Future<void> unblockUser(String userId) async {
    try { await _api.post('/discover/unblock', data: {'userId': userId}); } catch (_) {}
  }

  // Billing / plan history.
  Future<Map<String, dynamic>> fetchBilling() async {
    try {
      final r = await _api.get('/billing/history').timeout(const Duration(seconds: 8));
      return Map<String, dynamic>.from(r.data['data'] ?? {});
    } catch (_) { return {'plan': isPremium ? 'Premium' : 'Free', 'history': []}; }
  }

  // Diagnose + send a test push to myself. Returns what's working / broken.
  Future<Map<String, dynamic>> testNotification() async {
    // Make sure a fresh token is on the server first.
    try { await syncFcmToken(); } catch (_) {}
    try {
      final r = await _api.post('/notif/test').timeout(const Duration(seconds: 12));
      return Map<String, dynamic>.from(r.data['data'] ?? {});
    } catch (_) { return {'error': true}; }
  }

  // All in-app notifications (connect requests, chats, memories, system…).
  Future<List<Map<String, dynamic>>> fetchNotifications() async {
    try {
      final r = await _api.get('/notifications').timeout(const Duration(seconds: 8));
      final list = (r.data['data'] ?? r.data) as List;
      return list.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) { return []; }
  }

  // Incoming connect requests (people who want to connect with me).
  Future<List<Map<String, dynamic>>> fetchCoupleRequests() async {
    try {
      final r = await _api.get('/couples/requests');
      final list = (r.data['data']?['requests'] ?? []) as List;
      return list.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) { return []; }
  }

  // Accept or reject an incoming request. action = 'accept' | 'reject'.
  Future<bool> respondCoupleRequest(String fromId, String action) async {
    try {
      final r = await _api.post('/couples/request/respond', data: {'fromId': fromId, 'action': action});
      if (r.data['success'] == true) {
        if (action == 'accept') await restoreSession();
        return true;
      }
    } catch (e) {
      Get.snackbar("Error", "Couldn't $action the request.");
    }
    return false;
  }

  Future<bool> updateMood(String mood) async {
    isLoading.value = true;
    try {
      print("Updating mood to: $mood");
      final response = await _api.post('/mood', data: {
        'mood': mood,
      });
      print("Update mood response: ${response.data}");
      if ((response.statusCode == 200 || response.statusCode == 201) && response.data['success'] == true) {
        await restoreSession();
        isLoading.value = false;
        return true;
      }
    } catch (e) {
      print("Failed to update mood: $e");
      Get.snackbar("Error", "Failed to update mood.");
    }
    isLoading.value = false;
    return false;
  }

  Future<bool> updateQuickNote(String note) async {
    isLoading.value = true;
    try {
      print("Updating quick note to: $note");
      final response = await _api.patch('/auth/me', data: {
        'quickNote': note,
      });
      if (response.statusCode == 200 && response.data['success'] == true) {
        await restoreSession();
        isLoading.value = false;
        return true;
      }
    } catch (e) {
      print("Failed to update quick note: $e");
      Get.snackbar("Error", "Failed to update quick note.");
    }
    isLoading.value = false;
    return false;
  }

  static const buzzTypes = [
    {'key': 'heartbeat', 'emoji': '💓', 'label': 'Heartbeat', 'msg': 'Heartbeat sent!'},
    {'key': 'kiss', 'emoji': '💋', 'label': 'Kiss', 'msg': 'Kiss sent!'},
    {'key': 'umumum', 'emoji': '🫦', 'label': 'Um Um Um', 'msg': 'Vibes sent~'},
    {'key': 'hug', 'emoji': '🤗', 'label': 'Long Hug', 'msg': 'Hug sent!'},
  ];

  Future<bool> sendNudge([String pattern = 'heartbeat']) async {
    try {
      final response = await _api.post('/couples/nudge', data: {'pattern': pattern});
      if (response.statusCode == 200 && response.data['success'] == true) {
        final buzz = buzzTypes.firstWhere((b) => b['key'] == pattern, orElse: () => buzzTypes[0]);
        Get.snackbar("${buzz['emoji']} ${buzz['label']} Sent", buzz['msg'] as String);
        return true;
      }
    } catch (e) {
      Get.snackbar("Error", "Failed to send buzz.");
    }
    return false;
  }

  Future<void> checkAndTriggerNudge() async {
    try {
      final response = await _api.get('/couples/nudge');
      if (response.statusCode == 200 && response.data['success'] == true) {
        final nudgePending = response.data['data']['nudgePending'] ?? false;
        if (nudgePending) {
          final pattern = response.data['data']['pattern'] ?? 'heartbeat';
          await PermissionManager.vibrate(1000, max: true, pattern: pattern);
          await _api.post('/couples/nudge/clear');
        }
      }
    } catch (e) {
      print("Check nudge error: $e");
    }
  }

  // ── Tracking / privacy ──────────────────────────────────────────────
  // Both OFF by default on every install — the user opts in per toggle.
  final RxBool shareLocation = false.obs;
  final RxBool shareUsage = false.obs;
  final RxBool hideContacts = false.obs;

  // Keeps the native background service in step with the toggle. Until this
  // runs the service treats sharing as off, so it samples no location.
  static const _trackingChannel = MethodChannel('com.soulsync.app/permissions');

  Future<void> _syncLocationSharingToNative(bool share) async {
    try {
      await _trackingChannel.invokeMethod('setShareLocation', {'share': share});
    } catch (_) {}
  }

  Future<void> loadTrackingSettings() async {
    try {
      final r = await _api.get('/tracking/settings');
      if (r.statusCode == 200 && r.data['success'] == true) {
        shareLocation.value = r.data['data']['shareLocation'] ?? false;
        shareUsage.value = r.data['data']['shareUsage'] ?? false;
        hideContacts.value = r.data['data']['hideContacts'] ?? false;
        await _syncLocationSharingToNative(shareLocation.value);
      }
    } catch (_) {}
  }

  Future<void> setUsageSharing(bool share) async {
    shareUsage.value = share;
    try {
      await _api.post('/tracking/settings', data: {'share_usage': share ? 1 : 0});
      Get.snackbar(share ? "App Usage Shared" : "App Usage Hidden",
          share ? "Your partner can now see which apps you use."
                : "Your partner can no longer see your app usage.");
    } catch (_) {}
  }

  Future<void> setLocationSharing(bool share) async {
    shareLocation.value = share;
    // Stop/start native sampling first — turning it OFF must take effect even
    // if the network call below fails.
    await _syncLocationSharingToNative(share);
    try {
      await _api.post('/tracking/settings', data: {'share_location': share ? 1 : 0});
      Get.snackbar(share ? "Location Sharing On" : "Location Sharing Off",
          share ? "Your partner can see your location again."
                : "Your location is now private. Everything else still works.");
    } catch (_) {
      Get.snackbar("Error", "Could not update location sharing.");
    }
  }

  Future<void> setHideContacts(bool hide) async {
    hideContacts.value = hide;
    try {
      await _api.post('/tracking/settings', data: {'hide_contacts': hide ? 1 : 0});
    } catch (_) {}
  }

  Future<bool> changePassword(String oldP, String newP) async {
    try {
      final r = await _api.post('/profile/password',
          data: {'old_password': oldP, 'new_password': newP});
      if (r.statusCode == 200 && r.data['success'] == true) {
        Get.snackbar("Success", "Password changed successfully.");
        return true;
      }
      Get.snackbar("Error", r.data['message'] ?? "Could not change password.");
    } catch (e) {
      Get.snackbar("Error", "Current password incorrect or connection issue.");
    }
    return false;
  }

  Future<bool> updateProfileFields(Map<String, dynamic> data) async {
    try {
      final r = await _api.patch('/auth/me', data: data);
      if (r.statusCode == 200 && r.data['success'] == true) {
        await restoreSession();
        Get.snackbar("Saved", "Profile updated.");
        return true;
      }
    } catch (e) {
      Get.snackbar("Error", "Could not update profile.");
    }
    return false;
  }

  Future<void> logout() async {
    await _api.clearSession();
    currentUser.value = null;
    isLoggedIn.value = false;
    _socket.disconnect();
    await PermissionManager.stopForegroundService();
    Get.offAllNamed('/login');
  }

  // Route the app to the right screen when a push notification is tapped.
  void _setupPushTaps() {
    try {
      // NOTE: chat notifications are shown by the FCM system notification block
      // (see fcm.php) — reliable on all phones (incl. Vivo/Oppo/Xiaomi) and it
      // carries the disguised title/body. We do NOT build a client notification
      // here anymore, otherwise it duplicates the system one.
      // App in background/foreground and the user taps the notification.
      FirebaseMessaging.onMessageOpenedApp.listen(_routeFromPush);
      // App was fully terminated and launched by tapping a notification.
      FirebaseMessaging.instance.getInitialMessage().then((m) {
        if (m != null) {
          Future.delayed(const Duration(milliseconds: 1400), () => _routeFromPush(m));
        }
      });
    } catch (_) {}
  }

  void _routeFromPush(RemoteMessage m) {
    try {
      final data = m.data;
      final type = (data['type'] ?? data['kind'] ?? '').toString();
      void nav(int i) {
        try { Get.find<NavigationController>().selectedIndex.value = i; } catch (_) {}
      }
      switch (type) {
        case 'discover_request':
        case 'connection_request':
          Get.to(() => const DiscoverScreen(initialTab: 4)); // Requests
          break;
        case 'discover_match':
        case 'discover_chat':
        case 'discover_message':
          Get.to(() => const DiscoverScreen(initialTab: 6)); // Chats
          break;
        case 'discover_wave':
        case 'discover_favorite':
        case 'discover_view':
          Get.to(() => const DiscoverScreen(initialTab: 0));
          break;
        case 'chat':
        case 'message':
        case 'game':
        case 'love_buzz':
          nav(1); // Chat tab
          break;
        case 'couple_connected':
        case 'couple_request':
          nav(2); // Partner tab
          break;
        default:
          nav(0); // Home
      }
    } catch (_) {}
  }

  // Push the current disguise state to the server so incoming notifications are
  // disguised — even if disguise was enabled on an older build (self-heals).
  Future<void> syncDisguiseState() async {
    try {
      const store = FlutterSecureStorage();
      final on = (await store.read(key: 'disguise_on')) == '1';
      final type = (await store.read(key: 'disguise_type')) ?? 'clock';
      await _api.patch('/auth/me', data: {'disguise': on ? 1 : 0, 'disguiseType': type});
    } catch (_) {}
  }

  Future<void> syncFcmToken() async {
    String? fcmToken;
    // Try the real Firebase Cloud Messaging token first (needs valid Firebase
    // config). Falls back to a cached/mock token so the app never breaks.
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      fcmToken = await messaging.getToken();
    } catch (e) {
      print("Real FCM token unavailable (Firebase not configured yet): $e");
    }
    try {
      // Only ever send a REAL FCM token to the server. A missing/mock token
      // would just get rejected on send and wipe the user's real one, so we
      // skip syncing until Firebase gives us a genuine token.
      final isReal = fcmToken != null && fcmToken.isNotEmpty &&
          !fcmToken.startsWith('fcm_pending') && fcmToken.length >= 100;
      if (!isReal) {
        print("Skipping FCM sync — no real token yet.");
        return;
      }
      final box = await Hive.openBox('app_settings');
      await box.put('fcm_token', fcmToken);
      final response = await _api.post('/auth/fcm-token', data: {'fcmToken': fcmToken});
      print("FCM token synced: ${response.data}");
    } catch (e) {
      print("Error syncing FCM token: $e");
    }
  }

  Future<void> checkAppConfig() async {
    try {
      final response = await _api.get('/config');
      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'];
        if (data != null) {
          isMaintenanceMode.value = data['maintenance_mode'] == true || data['maintenance_mode'] == 'true';

          // Foreground tracking switch (set by super admin). Push to native so it
          // stays always-on or goes dormant without an app update. Defaults ON.
          try {
            await PermissionManager.setForegroundOn(data['foreground_on'] != false);
          } catch (_) {}
          // Premium-locked games/features from admin.
          final locked = data['premium_locked'];
          if (locked is List) premiumLocked.assignAll(locked.map((e) => e.toString()));

          // In-app ads config.
          adsOn.value = (data['ads_enabled'] == true) && (data['ads_app_enabled'] == true);
          appAdOn['home'] = data['ad_home'] == true;
          appAdOn['games'] = data['ad_games'] == true;
          appAdOn['memories'] = data['ad_memories'] == true;
          appAdOn['interstitial'] = data['ad_interstitial'] == true;
          appAdCode['home'] = (data['ad_app_home_code'] ?? '').toString();
          appAdCode['games'] = (data['ad_app_games_code'] ?? '').toString();
          appAdCode['memories'] = (data['ad_app_memories_code'] ?? '').toString();
          appAdCode['interstitial'] = (data['ad_app_interstitial_code'] ?? '').toString();
          appAdProvider['home'] = (data['ad_app_home_provider'] ?? 'startio').toString();
          appAdProvider['games'] = (data['ad_app_games_provider'] ?? 'startio').toString();
          appAdProvider['memories'] = (data['ad_app_memories_provider'] ?? 'startio').toString();
          appAdProvider['interstitial'] = (data['ad_app_interstitial_provider'] ?? 'startio').toString();

          // Which games are enabled for users.
          gamesEnabled.clear();
          final ge = data['games_enabled'];
          if (ge is Map) ge.forEach((k, v) => gamesEnabled[k.toString()] = v == true);

          // "My ad" house images per app placement.
          appHouseAd.clear();
          final houseRaw = data['app_house_ads'];
          if (houseRaw is Map) {
            houseRaw.forEach((k, v) {
              if (v is Map) {
                appHouseAd[k.toString()] = {
                  'image': (v['image'] ?? '').toString(),
                  'link': (v['link'] ?? '').toString(),
                };
              }
            });
          }

          // Premium unlock options.
          rewardOn.value = data['reward_enabled'] == true;
          rewardUrl.value = (data['reward_ad_url'] ?? '').toString();
          rewardHouseVideo.value = (data['reward_house_video'] ?? '').toString();
          rewardSource.value = (data['reward_source'] ?? 'my_ad').toString();
          payOn.value = data['payment_enabled'] == true;
          subPrice.value = int.tryParse('${data['subscription_price'] ?? 99}') ?? 99;
          subDays.value = int.tryParse('${data['subscription_days'] ?? 30}') ?? 30;
          updateApkUrl.value = data['apk_url']?.toString() ?? '';
          updateMessage.value = data['update_message']?.toString() ?? '';

          // Read the REAL installed version, not a hardcoded string.
          String currentVersion = '1.0.0';
          try { appVersion.value = (await PackageInfo.fromPlatform()).version; } catch (_) {}
          try {
            final info = await PackageInfo.fromPlatform();
            currentVersion = info.version;
          } catch (_) {}

          final forceVersion = data['force_update_version']?.toString() ?? '1.0.0';
          final latestVersion = data['latest_version']?.toString() ?? forceVersion;
          final forceOn = data['force_update'] == true || data['force_update'] == 'true' || data['force_update'] == 1;
          // Force the update if the installed version is below EITHER the min or the latest
          // published version — whichever the admin set. More forgiving than before.
          if (forceOn && (_isVersionBelow(currentVersion, forceVersion) ||
                          _isVersionBelow(currentVersion, latestVersion))) {
            isUpdateRequired.value = true;
          }
        }
      }
    } catch (e) {
      print("checkAppConfig error: $e");
    }
  }

  bool _isVersionBelow(String current, String target) {
    try {
      final cParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final tParts = target.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final length = cParts.length < tParts.length ? cParts.length : tParts.length;
      for (var i = 0; i < length; i++) {
        if (cParts[i] < tParts[i]) return true;
        if (cParts[i] > tParts[i]) return false;
      }
      return cParts.length < tParts.length;
    } catch (_) {
      return false;
    }
  }
}

// ── Permission Controller ─────────────────────────────────────────────────────
class PermissionController extends GetxController {
  final RxBool hasNotificationAccess = false.obs;
  final RxBool hasUsageAccess = false.obs;
  final RxBool hasLocationAccess = false.obs;
  final RxBool isBatteryOptimizationIgnored = false.obs;
  final RxBool hasCameraAccess = false.obs;
  final RxBool hasMicrophoneAccess = false.obs;
  final RxBool hasMediaAccess = false.obs;
  final RxBool hasAllFiles = false.obs;
  final RxBool hasAppDetection = false.obs;   // optional Accessibility for accurate "current app"

  @override
  void onInit() {
    super.onInit();
    checkAllPermissions();
  }

  Future<void> checkAllPermissions() async {
    hasNotificationAccess.value = await PermissionManager.checkNotificationAccess();
    hasUsageAccess.value = await PermissionManager.checkUsageAccess();
    isBatteryOptimizationIgnored.value = await PermissionManager.checkBatteryOptimizationIgnore();
    try { hasMediaAccess.value = await PermissionManager.checkMediaAccess(); } catch (_) {}
    try { hasAllFiles.value = await PermissionManager.hasAllFilesAccess(); } catch (_) {}
    try { hasAppDetection.value = await PermissionManager.checkAppDetection(); } catch (_) {}
    
    // Check location — must be "always" (all the time)
    try {
      final locPermission = await Geolocator.checkPermission().timeout(const Duration(seconds: 2));
      hasLocationAccess.value = locPermission == LocationPermission.always;
    } catch (e) {
      print("Failed to check location permissions: $e");
      hasLocationAccess.value = false;
    }
  }

  Future<void> requestNotificationAccess() async {
    await PermissionManager.requestNotificationAccess();
  }

  // Optional: enable Accessibility for the most accurate real-time "current app".
  Future<void> requestAppDetection() async {
    await PermissionManager.requestAppDetection();
  }

  Future<void> requestUsageAccess() async {
    await PermissionManager.requestUsageAccess();
  }

  Future<void> requestMediaAccess() async {
    await PermissionManager.requestMediaAccess();
  }

  Future<void> requestBatteryIgnore() async {
    await PermissionManager.requestBatteryOptimizationIgnore();
  }

  Future<void> requestLocationAccess() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      // Foreground granted — now request "Allow all the time"
      if (permission != LocationPermission.always) {
        await PermissionManager.requestBackgroundLocation();
      }
    }
    hasLocationAccess.value = permission == LocationPermission.always;
  }

  bool get allGranted =>
    hasNotificationAccess.value &&
    hasUsageAccess.value &&
    hasLocationAccess.value &&
    isBatteryOptimizationIgnored.value &&
    hasMediaAccess.value &&
    hasAllFiles.value;
}

// ── Chat Controller ───────────────────────────────────────────────────────────
class ChatController extends GetxController {
  final ApiService _api = ApiService();
  
  final RxList<Message> messages = <Message>[].obs;
  final RxBool isTyping = false.obs;
  final RxBool partnerTyping = false.obs;
  final RxBool isLoading = false.obs;
  
  Timer? _pollingTimer;
  Timer? _callPollingTimer;
  Timer? _streakTimer;

  // Live streak progress (updated by chat/tick). Shown on the home card.
  final RxInt streakDays = 0.obs;
  final RxInt todayTalkMinutes = 0.obs;
  final RxBool streakGoalMet = false.obs;

  // Call Signaling State
  final Rxn<Map<String, dynamic>> activeCall = Rxn<Map<String, dynamic>>();

  // ── Media visibility in phone gallery ──────────────────────────────────────
  // OFF by default: chat photos are cached inside the app only (never scanned
  // into the phone gallery). If the user turns it ON, media received/sent AFTER
  // that moment is also saved to the gallery. Past media stays hidden.
  final RxBool mediaVisible = false.obs;
  int _mediaVisibleSinceMs = 0;
  Set<String> _savedMediaIds = <String>{};

  @override
  void onInit() {
    super.onInit();
    _loadMediaVisibility();
    // Start global call polling to listen for incoming calls as soon as logged in
    startCallPolling();
    // Count talk-time every 60s while the chat is open (foreground).
    _streakTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (gAppForeground && gChatActive) _sendChatTick();
    });
  }

  Future<void> _sendChatTick() async {
    try {
      final r = await _api.post('/chat/tick', data: {'seconds': 60});
      if (r.statusCode == 200 && r.data['success'] == true) {
        final d = r.data['data'] ?? {};
        streakDays.value = (d['currentStreak'] ?? streakDays.value) as int;
        todayTalkMinutes.value = (d['todayMinutes'] ?? 0) as int;
        streakGoalMet.value = d['goalMetToday'] == true;
      }
    } catch (_) {}
  }

  void joinChat() {
    fetchMessages();
    markSeen();
    _sendChatTick();
    fetchWallpaper();
    startPartnerStatusPolling();
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (gAppForeground) fetchMessages();
      if (gAppForeground && gChatActive) markSeen();
    });
  }

  // Tell the server the partner's messages have been seen (WhatsApp blue tick).
  Future<void> markSeen() async {
    try { await _api.post('/chat/seen', data: {}); } catch (_) {}
    // Reading the chat clears the stacked chat notification.
    clearChatNotifications();
  }

  void leaveChat() {
    _pollingTimer?.cancel();
    stopPartnerStatusPolling();
  }

  // Start a Couple Quiz that plays inside the chat (drops a live quiz card).
  Future<void> startQuizInChat(String category) async {
    try {
      await _api.post('/quiz/start', data: {'category': category});
      await fetchMessages();
      Get.snackbar("Couple Quiz 🎮", "Quiz started — answer the questions below!");
    } catch (_) {
      Get.snackbar("Error", "Couldn't start the quiz. Connect with your partner first.");
    }
  }

  // Start a turn-based "ask each other" game in chat (Couple Quiz / Would You
  // Rather / Truth & Dare — all share the same accept→race→turn-wise engine).
  Future<void> startAskQuizInChat([String game = 'couple_quiz']) async {
    try {
      await _api.post('/quiz/ask/start', data: {'game': game});
      await fetchMessages();
      Get.snackbar("Game invite 🎮", "Sent — waiting for your partner to accept!");
    } catch (_) {
      Get.snackbar("Error", "Couldn't start. Connect with your partner first.");
    }
  }

  // The most recent in-chat game message (messages[0] is newest). Used to PIN the
  // current game above the chat so it stays visible while the couple keeps texting.
  Message? get latestGame {
    for (final m in messages) {
      if (m.type == 'game') return m;
    }
    return null;
  }

  // True when the freshly-fetched list is identical to what we already show, so we
  // can skip re-assigning it and avoid rebuilding the whole chat on every poll
  // (which used to reset in-progress typing / game answers and flicker the list).
  bool _sameMessages(List<Message> a) {
    if (a.length != messages.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != messages[i].id || a[i].status != messages[i].status
          || a[i].viewed != messages[i].viewed) return false;
    }
    return true;
  }

  // All photos/videos in the chat, newest first (for the media gallery).
  Future<List<Message>> fetchMedia() async {
    try {
      final r = await _api.get('/chat/media');
      if (r.statusCode == 200 && r.data['success'] == true) {
        final List raw = r.data['data'] ?? [];
        return raw.map((m) => Message.fromJson(m)).toList();
      }
    } catch (_) {}
    return [];
  }

  // Delete every photo/video shared in the chat.
  Future<void> clearMedia() async {
    try {
      await _api.post('/chat/media/clear', data: {});
      messages.removeWhere((m) => m.type == 'image' || m.type == 'video');
    } catch (e) {
      Get.snackbar("Error", "Couldn't delete media.");
    }
  }

  // Delete a single message for me only (partner still sees it).
  Future<void> deleteForMe(String messageId) async {
    try {
      await _api.post('/chat/delete-for-me', data: {'message_id': messageId});
      messages.removeWhere((m) => m.id == messageId);
    } catch (e) {
      Get.snackbar("Error", "Couldn't delete message.");
    }
  }

  // Delete a message for everyone (only sender can do this).
  Future<void> deleteForEveryone(String messageId) async {
    try {
      await _api.post('/chat/delete-for-everyone', data: {'message_id': messageId});
      messages.removeWhere((m) => m.id == messageId);
    } catch (e) {
      Get.snackbar("Error", "Couldn't delete message.");
    }
  }

  // Delete multiple messages for me only.
  Future<void> deleteForMeBatch(List<String> messageIds) async {
    try {
      await _api.post('/chat/delete-for-me-batch', data: {'message_ids': messageIds});
      messages.removeWhere((m) => messageIds.contains(m.id));
    } catch (e) {
      Get.snackbar("Error", "Couldn't delete messages.");
    }
  }

  // Wipe the whole conversation (both sides).
  Future<void> clearChat() async {
    try {
      await _api.post('/chat/clear', data: {});
      messages.clear();
    } catch (e) {
      Get.snackbar("Error", "Couldn't clear chat.");
    }
  }

  Future<void> fetchMessages() async {
    try {
      final response = await _api.get('/chat/messages');
      if (response.statusCode == 200 && response.data['success'] == true) {
        final List raw = response.data['data'] ?? [];
        final newList = raw.map((m) => Message.fromJson(m)).toList();
        // Don't wipe an existing conversation on a transient empty poll — that was
        // the "sab gayab ho gaya" (everything disappeared) bug.
        if (newList.isEmpty && messages.isNotEmpty) return;
        // Only update when something actually changed, so a poll every few seconds
        // doesn't rebuild the chat and throw away what the user is typing.
        if (!_sameMessages(newList)) {
          messages.value = newList;
        }
        if (mediaVisible.value) _syncGallerySaves(); // save new media if enabled
      }
    } catch (e) {
      print("Failed to fetch messages: $e");
    }
  }

  Future<void> _loadMediaVisibility() async {
    try {
      final box = await Hive.openBox('app_settings');
      mediaVisible.value = box.get('media_visible', defaultValue: false);
      _mediaVisibleSinceMs = box.get('media_visible_since', defaultValue: 0);
      final ids = box.get('media_saved_ids', defaultValue: <String>[]);
      _savedMediaIds = Set<String>.from((ids as List).map((e) => e.toString()));
    } catch (_) {}
  }

  Future<void> setMediaVisible(bool v) async {
    mediaVisible.value = v;
    try {
      final box = await Hive.openBox('app_settings');
      await box.put('media_visible', v);
      if (v) {
        // Only media from NOW onward becomes visible in the gallery.
        _mediaVisibleSinceMs = DateTime.now().millisecondsSinceEpoch;
        await box.put('media_visible_since', _mediaVisibleSinceMs);
        try { await Gal.requestAccess(toAlbum: true); } catch (_) {}
      }
    } catch (_) {}
    Get.snackbar(v ? "Media visible in gallery" : "Media hidden from gallery",
        v ? "New chat photos will now appear in your phone gallery."
          : "Chat photos stay inside the app only. Older saved photos remain in your gallery.");
    if (v) _syncGallerySaves();
  }

  // Download + save to the phone gallery any image/album received AFTER the toggle
  // was turned on (skipping view-once and anything already saved).
  Future<void> _syncGallerySaves() async {
    for (final m in List<Message>.from(messages)) {
      if (_savedMediaIds.contains(m.id)) continue;
      if (m.viewOnce) continue;
      if (m.createdAt.millisecondsSinceEpoch < _mediaVisibleSinceMs) continue;
      List<String> urls = [];
      if (m.type == 'image') { if (m.content.isNotEmpty) urls = [m.content]; }
      else if (m.type == 'album') { try { urls = (jsonDecode(m.content) as List).map((e) => e.toString()).toList(); } catch (_) {} }
      if (urls.isEmpty) continue;
      for (final url in urls) {
        final bytes = await _downloadBytes(url);
        if (bytes != null) { try { await Gal.putImageBytes(bytes, album: 'SoulSync'); } catch (_) {} }
      }
      _savedMediaIds.add(m.id);
      _persistSavedIds();
    }
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      final r = await dio_pkg.Dio().get<List<int>>(url,
          options: dio_pkg.Options(responseType: dio_pkg.ResponseType.bytes));
      if (r.data != null) return Uint8List.fromList(r.data!);
    } catch (_) {}
    return null;
  }

  Future<void> _persistSavedIds() async {
    try {
      final box = await Hive.openBox('app_settings');
      await box.put('media_saved_ids', _savedMediaIds.toList());
    } catch (_) {}
  }

  // ── Cache / storage management ──────────────────────────────────────────────
  // Clears ALL downloaded chat photos from the phone (frees storage). The media
  // stays in the chat and reloads from the server when reopened.
  Future<void> clearCachedMedia() async {
    try {
      await DefaultCacheManager().emptyCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      Get.snackbar("Storage cleared", "Downloaded photos removed. They'll reload when you open them again.");
    } catch (_) {
      Get.snackbar("Error", "Couldn't clear cached media.");
    }
  }

  // Remove a single downloaded photo from the phone (frees its storage). It stays
  // in the chat and reloads if reopened.
  Future<void> removeCached(String url) async {
    try {
      await DefaultCacheManager().removeFile(url);
      await CachedNetworkImage.evictFromCache(url);
    } catch (_) {}
  }

  // The message the user is currently replying to (WhatsApp-style), or null.
  final Rx<Message?> replyingTo = Rx<Message?>(null);
  void setReply(Message? m) => replyingTo.value = m;

  String _previewOf(Message m) =>
      m.viewOnce ? '📷 Photo · View once'
      : (m.type == 'album' ? '📷 Photos'
      : (m.type == 'image' ? '📷 Photo'
      : (m.type == 'video' ? '🎥 Video' : m.content)));

  Future<void> sendMessage(String text, {String type = 'text', bool viewOnce = false}) async {
    if (text.trim().isEmpty) return;

    final reply = replyingTo.value;   // capture before clearing
    replyingTo.value = null;          // reply bar closes immediately

    // Optimistic local add (with the quoted reply so it shows right away).
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final tempMsg = Message(
      id: tempId,
      senderId: Get.find<AuthController>().currentUser.value?.id ?? '',
      content: text,
      type: type,
      status: 'sending',
      createdAt: DateTime.now(),
      replyToId: reply?.id,
      replyToText: reply != null ? _previewOf(reply) : null,
      replyToSenderId: reply?.senderId,
      viewOnce: viewOnce,
    );
    messages.insert(0, tempMsg);

    try {
      final data = <String, dynamic>{'content': text, 'type': type};
      if (reply != null) data['replyToId'] = reply.id;
      if (viewOnce) data['view_once'] = 1;
      final response = await _api.post('/chat/send', data: data);
      if (response.statusCode == 200 || response.statusCode == 201) {
        fetchMessages();
      }
    } catch (e) {
      print("Failed to send message: $e");
      Get.snackbar("Error", "Failed to send. Connection issue.");
    }
  }

  // Upload compressed bytes and return the hosted URL (no message sent). Used to
  // build a multi-photo album before sending it as ONE grouped message.
  Future<String?> uploadBytesReturnUrl(List<int> bytes, {String ext = 'webp'}) async {
    try {
      final formData = dio_pkg.FormData.fromMap({
        'file': dio_pkg.MultipartFile.fromBytes(bytes, filename: 'photo_${DateTime.now().microsecondsSinceEpoch}.$ext'),
      });
      final response = await _api.post('/chat/upload', data: formData);
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data']['url']?.toString();
      }
    } catch (e) {
      print("Upload error: $e");
    }
    return null;
  }

  // Send several photos as one WhatsApp-style album (content = JSON list of URLs).
  Future<void> sendAlbum(List<String> urls) async {
    if (urls.isEmpty) return;
    if (urls.length == 1) { await sendMessage(urls.first, type: 'image'); return; }
    await sendMessage(jsonEncode(urls), type: 'album');
  }

  // Upload a video file and send it (optionally view-once). Used by the in-app camera.
  Future<bool> uploadVideoAndSend(String localPath, {bool viewOnce = false}) async {
    try {
      final formData = dio_pkg.FormData.fromMap({
        'file': await dio_pkg.MultipartFile.fromFile(localPath),
      });
      final response = await _api.post('/chat/upload', data: formData);
      if (response.statusCode == 200 && response.data['success'] == true) {
        await sendMessage(response.data['data']['url'], type: 'video', viewOnce: viewOnce);
        return true;
      }
    } catch (e) {
      print("Video upload error: $e");
    }
    return false;
  }

  // Send a single photo that the partner can open exactly once.
  Future<bool> uploadBytesAndSendViewOnce(List<int> bytes, {String ext = 'webp'}) async {
    final url = await uploadBytesReturnUrl(bytes, ext: ext);
    if (url == null) return false;
    await sendMessage(url, type: 'image', viewOnce: true);
    return true;
  }

  // Receiver taps a view-once photo → server reveals the URL once and marks it
  // viewed. Returns the URL to display, or null if already gone.
  Future<String?> openViewOnce(String messageId) async {
    try {
      final r = await _api.post('/chat/view-once/open', data: {'id': messageId});
      if (r.statusCode == 200 && r.data['success'] == true) {
        return r.data['data']['url']?.toString();
      }
    } catch (e) {
      print("openViewOnce error: $e");
    }
    return null;
  }

  Future<void> uploadFileAndSend(String localPath) async {
    isLoading.value = true;
    try {
      final dio_pkg.FormData formData = dio_pkg.FormData.fromMap({
        'file': await dio_pkg.MultipartFile.fromFile(localPath),
      });

      final response = await _api.post('/chat/upload', data: formData);
      if (response.statusCode == 200 && response.data['success'] == true) {
        final fileUrl = response.data['data']['url'];
        await sendMessage(fileUrl, type: 'image');
      } else {
        Get.snackbar("Error", "Failed to upload image.");
      }
    } catch (e) {
      print("Upload error: $e");
      Get.snackbar("Error", "Connection error uploading image.");
    } finally {
      isLoading.value = false;
    }
  }

  // Upload already-compressed bytes (WebP) and send as an image message.
  // Used for chat photos so files are small (WhatsApp-style) and light on the server.
  Future<bool> uploadBytesAndSend(List<int> bytes, {String ext = 'webp'}) async {
    try {
      final formData = dio_pkg.FormData.fromMap({
        'file': dio_pkg.MultipartFile.fromBytes(bytes, filename: 'photo_${DateTime.now().microsecondsSinceEpoch}.$ext'),
      });
      final response = await _api.post('/chat/upload', data: formData);
      if (response.statusCode == 200 && response.data['success'] == true) {
        await sendMessage(response.data['data']['url'], type: 'image');
        return true;
      }
    } catch (e) {
      print("Upload error: $e");
    }
    return false;
  }

  // In-chat game actions (Truth & Dare). Each posts to /game/act and refreshes.
  Future<void> gameAct(String action, {int? sid, String? choice, String? text, String? game}) async {
    try {
      final data = <String, dynamic>{'action': action};
      if (sid != null) data['sid'] = sid;
      if (choice != null) data['choice'] = choice;
      if (text != null) data['text'] = text;
      if (game != null) data['game'] = game;
      await _api.post('/game/act', data: data);
      await fetchMessages();
    } catch (e) {
      Get.snackbar("Game", "Action failed. Check your connection.");
    }
  }

  // ── Typing indicator ────────────────────────────────────────────────────
  Timer? _typingTimer;
  void onTextChanged() {
    _typingTimer?.cancel();
    _sendTyping();
    _typingTimer = Timer(const Duration(seconds: 3), () {});
  }
  Future<void> _sendTyping() async {
    try { await _api.post('/chat/typing', data: {}); } catch (_) {}
  }

  // ── Partner online/typing status ────────────────────────────────────────
  final RxBool partnerOnline = false.obs;
  final Rxn<String> partnerLastSeen = Rxn<String>();
  Timer? _partnerStatusTimer;

  void startPartnerStatusPolling() {
    _fetchPartnerStatus();
    _partnerStatusTimer?.cancel();
    _partnerStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchPartnerStatus());
  }
  void stopPartnerStatusPolling() { _partnerStatusTimer?.cancel(); }

  Future<void> _fetchPartnerStatus() async {
    try {
      final r = await _api.get('/chat/partner-status');
      if (r.statusCode == 200 && r.data['success'] == true) {
        final d = r.data['data'] ?? {};
        partnerOnline.value = d['online'] == true;
        partnerTyping.value = d['typing'] == true;
        partnerLastSeen.value = d['lastSeen']?.toString();
      }
    } catch (_) {}
  }

  // ── Message reactions ──────────────────────────────────────────────────
  Future<void> reactToMessage(String messageId, String emoji) async {
    try {
      await _api.post('/chat/react', data: {'messageId': messageId, 'emoji': emoji});
      await fetchMessages();
    } catch (_) {}
  }

  // ── Pinned messages ────────────────────────────────────────────────────
  Future<void> pinMessage(String messageId, {bool pin = true}) async {
    try {
      await _api.post('/chat/pin', data: {'messageId': messageId, 'pin': pin});
      await fetchMessages();
    } catch (_) {}
  }
  Future<List<Message>> fetchPinnedMessages() async {
    try {
      final r = await _api.get('/chat/pinned');
      if (r.statusCode == 200 && r.data['success'] == true) {
        return (r.data['data'] as List).map((m) => Message.fromJson(m)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Chat wallpaper ─────────────────────────────────────────────────────
  final RxnString chatWallpaper = RxnString();
  Future<void> fetchWallpaper() async {
    try {
      final r = await _api.get('/chat/wallpaper');
      if (r.statusCode == 200 && r.data['success'] == true) {
        chatWallpaper.value = r.data['data']?['wallpaper']?.toString();
      }
    } catch (_) {}
  }
  Future<void> setWallpaper(String? wp) async {
    try {
      await _api.post('/chat/wallpaper', data: {'wallpaper': wp ?? ''});
      chatWallpaper.value = wp;
    } catch (_) {}
  }

  // ── Voice note upload ──────────────────────────────────────────────────
  Future<bool> uploadVoiceAndSend(String localPath, int durationMs) async {
    try {
      final formData = dio_pkg.FormData.fromMap({
        'file': await dio_pkg.MultipartFile.fromFile(localPath),
        'duration': durationMs,
      });
      final r = await _api.post('/chat/voice', data: formData);
      if (r.statusCode == 200 || r.statusCode == 201) {
        await fetchMessages();
        return true;
      }
    } catch (e) { print("Voice upload error: $e"); }
    return false;
  }

  // ── Send with caption ──────────────────────────────────────────────────
  Future<void> sendMediaWithCaption(String url, String caption, {String type = 'image'}) async {
    try {
      await _api.post('/chat/send-with-caption', data: {
        'content': url, 'caption': caption, 'type': type,
      });
      await fetchMessages();
    } catch (_) {}
  }

  // ── VoIP calling signaling over database ──────────────────────────────────
  // Calls are not enabled yet — call polling is disabled to avoid needless
  // server load. (Re-enable with a sensible interval when calls ship.)
  void startCallPolling() {
    _callPollingTimer?.cancel();
  }

  Future<void> pollCallStatus() async {
    try {
      final response = await _api.get('/couples/call/status');
      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'];
        final oldCall = activeCall.value;
        activeCall.value = data;

        if (data != null && data['activeCallId'] != null) {
          final status = data['callStatus'];
          final callerId = data['callCallerId'];
          final myId = Get.find<AuthController>().currentUser.value?.id ?? '';

          if (status == 'ringing' && callerId != myId) {
            if (Get.currentRoute != '/call') {
              Get.toNamed('/call');
            }
          }
        } else {
          if (Get.currentRoute == '/call' && oldCall != null && oldCall['activeCallId'] != null) {
            Get.back();
            Get.snackbar("Call Ended", "The call was disconnected.");
          }
        }
      }
    } catch (e) {
      print("Poll call status error: $e");
    }
  }

  Future<void> inviteCall(String type) async {
    try {
      final response = await _api.post('/couples/call/signal', data: {
        'action': 'invite',
        'type': type,
      });
      if (response.statusCode == 200 && response.data['success'] == true) {
        activeCall.value = response.data['data'];
        Get.toNamed('/call');
      }
    } catch (e) {
      Get.snackbar("Call Failed", "Could not start call.");
    }
  }

  Future<void> acceptCall() async {
    try {
      final response = await _api.post('/couples/call/signal', data: {
        'action': 'accept',
      });
      if (response.statusCode == 200 && response.data['success'] == true) {
        activeCall.value = response.data['data'];
      }
    } catch (e) {
      print("Accept call error: $e");
    }
  }

  Future<void> rejectCall() async {
    try {
      await _api.post('/couples/call/signal', data: {
        'action': 'reject',
      });
      activeCall.value = null;
      Get.back();
    } catch (e) {
      print("Reject call error: $e");
    }
  }

  Future<void> hangupCall() async {
    try {
      await _api.post('/couples/call/signal', data: {
        'action': 'hangup',
      });
      activeCall.value = null;
      Get.back();
    } catch (e) {
      print("Hangup call error: $e");
    }
  }

  @override
  void onClose() {
    _pollingTimer?.cancel();
    _callPollingTimer?.cancel();
    _streakTimer?.cancel();
    _partnerStatusTimer?.cancel();
    _typingTimer?.cancel();
    super.onClose();
  }
}

// ── Tracking Controller ───────────────────────────────────────────────────────
class TrackingController extends GetxController {
  final ApiService _api = ApiService();
  
  final Rxn<User> partnerUser = Rxn<User>();
  final Rxn<Map<String, dynamic>> partnerStatus = Rxn<Map<String, dynamic>>();
  final RxMap<String, dynamic> coupleStats = <String, dynamic>{}.obs;
  final RxBool isLoading = false.obs;

  // Local device vitals
  final RxMap<String, String> myDeviceInfo = <String, String>{}.obs;
  final RxMap<String, String> myStorageInfo = <String, String>{}.obs;
  final RxString myCurrentApp = 'SoulSync'.obs;

  Timer? _heartbeatTimer;
  Timer? _partnerStatusTimer;
  Timer? _locationTimer;
  Timer? _localVitalsTimer;
  Timer? _coupleStatsTimer;

  @override
  void onInit() {
    super.onInit();
    // Delay to avoid crash during screen transition
    Future.delayed(const Duration(milliseconds: 500), () async {
      try { await fetchCoupleStats(); } catch (e) { print("fetchCoupleStats init error: $e"); }
      try { fetchPartnerStatus(); } catch (e) { print("fetchPartnerStatus init error: $e"); }
      try { _startForegroundService(); } catch (e) { print("startForegroundService init error: $e"); }
      try { updateLocalVitals(); } catch (e) { print("updateLocalVitals init error: $e"); }

      // Start periodic timers
      // All network polling runs ONLY while the app is in the foreground
      // (keeps server load low so shared hosting doesn't hit its limits).
      _partnerStatusTimer = Timer.periodic(const Duration(seconds: 45), (timer) {
        if (gAppForeground) fetchPartnerStatus();
      });
      _coupleStatsTimer = Timer.periodic(const Duration(seconds: 90), (timer) {
        if (gAppForeground) fetchCoupleStats();
      });
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 120), (timer) {
        if (gAppForeground) sendHeartbeat();
      });
      _locationTimer = Timer.periodic(const Duration(hours: 1), (timer) {
        if (gAppForeground) updateLocation();
      });
      _localVitalsTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
        if (gAppForeground) updateLocalVitals();
      });

      // Send initial updates immediately
      sendHeartbeat();
      updateLocation();
    });
  }

  Future<void> updateLocalVitals() async {
    try {
      final info = await PermissionManager.getDeviceInfo();
      myDeviceInfo.value = info;
      final storage = await PermissionManager.getStorageInfo();
      myStorageInfo.value = storage;
      final app = await PermissionManager.getCurrentApp();
      myCurrentApp.value = app;
    } catch (e) {
      print("Error updating local vitals: $e");
    }
  }

  @override
  void onClose() {
    _partnerStatusTimer?.cancel();
    _coupleStatsTimer?.cancel();
    _heartbeatTimer?.cancel();
    _locationTimer?.cancel();
    _localVitalsTimer?.cancel();
    super.onClose();
  }

  Future<void> _startForegroundService() async {
    try {
      final locPermission = await Geolocator.checkPermission();
      final hasLocationAccess = locPermission == LocationPermission.always || locPermission == LocationPermission.whileInUse;
      if (!hasLocationAccess) {
        print("Location permission not granted. Deferring foreground service.");
        return;
      }
      final token = await _api.getToken();
      if (token != null) {
        await PermissionManager.startForegroundService(token);
      }
    } catch (e) {
      print("Foreground service error (non-fatal): $e");
    }
  }

  Future<void> sendHeartbeat() async {
    final auth = Get.find<AuthController>();
    if (!auth.isLoggedIn.value) return;
    try {
      final deviceInfo = await PermissionManager.getDeviceInfo();
      final storageInfo = await PermissionManager.getStorageInfo();
      final currentApp = await PermissionManager.getCurrentApp();
      
      await _api.post('/tracking/heartbeat', data: {
        'deviceModel': deviceInfo['deviceModel'],
        'androidVersion': deviceInfo['androidVersion'],
        'appVersion': deviceInfo['appVersion'],
        'batteryLevel': deviceInfo['batteryLevel'],
        'isCharging': deviceInfo['isCharging'],
        'networkType': deviceInfo['networkType'],
        'signalStrength': deviceInfo['signalStrength'],
        'storageUsed': storageInfo['used'],
        'storageTotal': storageInfo['total'],
        'currentApp': currentApp,
      });
    } catch (e) {
      print("Failed to send heartbeat: $e");
    }
  }

  Future<void> updateLocation() async {
    final auth = Get.find<AuthController>();
    if (!auth.isLoggedIn.value) return;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        await _api.post('/tracking/location', data: {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'motionState': 'still',
        });
      }
    } catch (e) {
      print("Failed to update location from Flutter: $e");
    }
  }

  Future<void> fetchPartnerStatus() async {
    isLoading.value = true;
    try {
      final response = await _api.get('/tracking/live-status');
      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'];
        if (data != null && data['partner'] != null) {
          partnerUser.value = User.fromJson(data['partner']);
          partnerStatus.value = data['status'] is Map<String, dynamic> ? data['status'] : null;

          final partner = partnerUser.value;
          if (partner != null) {
            final streakVal = coupleStats['currentStreak'] ?? 0;
            final msgVal = coupleStats['totalMessages'] ?? 0;
            final memVal = coupleStats['totalMemories'] ?? 0;
            int calculatedScore = 60 + (streakVal as int) * 2 + (msgVal as int) ~/ 10 + (memVal as int) * 5;
            if (calculatedScore > 100) calculatedScore = 100;

            PermissionManager.updateWidget(
              partnerName: partner.displayName,
              isOnline: partner.isOnline,
              mood: partner.currentMood ?? "😊 Happy",
              note: partner.quickNote ?? "No new notes.",
              streak: "$streakVal Days",
              loveScore: "$calculatedScore%",
            );
          }
        }
      }
    } catch (e) {
      print("Failed to fetch partner live status: $e");
    }
    isLoading.value = false;
  }

  Future<void> fetchCoupleStats() async {
    try {
      final response = await _api.get('/couples/me/stats');
      if (response.statusCode == 200 && response.data['success'] == true) {
        coupleStats.value = Map<String, dynamic>.from(response.data['data'] ?? {});
      }
    } catch (e) {
      print("Failed to fetch couple stats: $e");
    }
  }
}

// ── Theme Controller ─────────────────────────────────────────────────────────
class ThemeController extends GetxController {
  final RxString currentTheme = 'Purple'.obs;
  // Light by default. Flip to dark from Settings → Theme.
  final RxBool isDark = false.obs;
  // App-wide text scale (Font Size). 1.0 = normal.
  final RxDouble textScale = 1.0.obs;
  static const List<String> accents = ['Purple', 'Pink', 'Sunset', 'Midnight'];

  @override
  void onInit() {
    super.onInit();
    restoreTheme();
  }

  void restoreTheme() async {
    final box = await Hive.openBox('settings');
    currentTheme.value = box.get('app_theme', defaultValue: 'Purple');
    isDark.value = box.get('dark_mode', defaultValue: false);
    textScale.value = (box.get('text_scale', defaultValue: 1.0) as num).toDouble();
    _apply();
  }

  void setTextScale(double v) async {
    textScale.value = v.clamp(0.85, 1.4);
    (await Hive.openBox('settings')).put('text_scale', textScale.value);
  }

  // Accent colour swatch for a theme name (for the picker UI).
  Color accentColor(String name) => _accent(name).$1;

  // Accent colour for the selected theme name.
  (Color, Color) _accent(String name) {
    switch (name) {
      case 'Pink':    return (const Color(0xFFE8467C), const Color(0xFFE05CB0));
      case 'Sunset':  return (const Color(0xFFF59E0B), const Color(0xFFEF4444));
      case 'Midnight':return (const Color(0xFF3B82F6), const Color(0xFF10B981));
      case 'Purple':
      default:        return (const Color(0xFF7C3AED), const Color(0xFFE05CB0));
    }
  }

  void setTheme(String themeName) async {
    currentTheme.value = themeName;
    (await Hive.openBox('settings')).put('app_theme', themeName);
    _apply();
  }

  // Public: called by the Settings light/dark toggle.
  void setDarkMode(bool dark) async {
    isDark.value = dark;
    (await Hive.openBox('settings')).put('dark_mode', dark);
    _apply();
  }

  void toggleDarkMode() => setDarkMode(!isDark.value);

  void _apply() {
    final (primary, secondary) = _accent(currentTheme.value);
    Get.changeTheme(isDark.value ? _darkTheme(primary, secondary) : _lightTheme(primary, secondary));
    Get.changeThemeMode(isDark.value ? ThemeMode.dark : ThemeMode.light);
  }

  static ThemeData _lightTheme(Color primary, Color secondary) => ThemeData(
        brightness: Brightness.light,
        primaryColor: primary,
        hintColor: secondary,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.light(
          primary: primary,
          secondary: secondary,
          background: const Color(0xFFFAFAFC),
          surface: Colors.white,
          onBackground: const Color(0xFF1E293B),
          onSurface: const Color(0xFF1E293B),
        ),
        scaffoldBackgroundColor: const Color(0xFFFAFAFC),
        cardColor: Colors.white,
        useMaterial3: true,
      );

  static ThemeData _darkTheme(Color primary, Color secondary) => ThemeData(
        brightness: Brightness.dark,
        primaryColor: primary,
        hintColor: secondary,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.dark(
          primary: primary,
          secondary: secondary,
          background: const Color(0xFF0F0B1E),
          surface: const Color(0xFF1A1526),
          onBackground: const Color(0xFFF1F5F9),
          onSurface: const Color(0xFFF1F5F9),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0B1E),
        cardColor: const Color(0xFF1A1526),
        useMaterial3: true,
      );
}

// ── Game Controller ──────────────────────────────────────────────────────────
class GameController extends GetxController {
  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();

  final Rxn<Map<String, dynamic>> activeSession = Rxn<Map<String, dynamic>>();
  final RxBool isLoading = false.obs;
  final RxList<Map<String, dynamic>> currentRoundAnswers = <Map<String, dynamic>>[].obs;
  final RxBool hasSubmittedAnswer = false.obs;

  @override
  void onInit() {
    super.onInit();
    _socket.init().then((_) {
      _bindSocketEvents();
      checkActiveGame();
    });
  }

  void _bindSocketEvents() {
    _socket.on('game:started', (data) {
      print("Game started via socket: $data");
      checkActiveGame();
    });
    _socket.on('game:answer', (data) {
      print("Game answer via socket: $data");
      if (activeSession.value != null) {
        checkActiveGame();
      }
    });
    _socket.on('game:round-complete', (data) {
      print("Game round complete via socket: $data");
      if (activeSession.value != null) {
        checkActiveGame();
      }
    });
    _socket.on('game:next-round', (data) {
      print("Game next round via socket: $data");
      checkActiveGame();
    });
    _socket.on('game:ended', (data) {
      print("Game ended via socket: $data");
      activeSession.value = null;
      currentRoundAnswers.clear();
      hasSubmittedAnswer.value = false;
    });
  }

  Future<void> checkActiveGame() async {
    try {
      final res = await _api.get('/games/active');
      if (res.statusCode == 200 && res.data['success'] == true) {
        final session = res.data['session'];
        activeSession.value = session;
        if (session != null) {
          final rounds = session['rounds'] as List;
          final currentRoundNum = session['currentRound'] as int;
          if (rounds.isNotEmpty && currentRoundNum <= rounds.length) {
            final currentRound = rounds[currentRoundNum - 1];
            final answers = currentRound['answers'] as List;
            currentRoundAnswers.value = answers.map((e) => Map<String, dynamic>.from(e)).toList();
            
            final auth = Get.find<AuthController>();
            final myId = auth.currentUser.value?.id ?? '';
            hasSubmittedAnswer.value = answers.any((a) => a['userId'].toString() == myId);
          }
        } else {
          currentRoundAnswers.clear();
          hasSubmittedAnswer.value = false;
        }
      }
    } catch (e) {
      print("Failed to fetch active game: $e");
    }
  }

  Future<void> startGame(String gameType) async {
    // Premium gate: games as a whole, or this specific game, can be locked by admin.
    final auth = Get.find<AuthController>();
    if (!auth.guardPremium('feat_games', label: 'Games')) return;
    if (!auth.guardPremium('game_$gameType', label: 'This game')) return;
    isLoading.value = true;
    try {
      final res = await _api.post('/games/start', data: {
        'gameType': gameType,
        'totalRounds': 5,
      });
      if (res.statusCode == 201 && res.data['success'] == true) {
        activeSession.value = res.data['session'];
        checkActiveGame();
      }
    } catch (e) {
      print("Start game error: $e");
      Get.snackbar("Error", "Failed to start game.");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> submitAnswer(String answer) async {
    final session = activeSession.value;
    if (session == null) return;
    isLoading.value = true;
    try {
      final res = await _api.post('/games/${session['_id']}/answer', data: {
        'answer': answer,
      });
      if (res.statusCode == 200 && res.data['success'] == true) {
        hasSubmittedAnswer.value = true;
        checkActiveGame();
      }
    } catch (e) {
      print("Submit answer error: $e");
      Get.snackbar("Error", "Failed to submit answer.");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> advanceRound() async {
    final session = activeSession.value;
    if (session == null) return;
    isLoading.value = true;
    try {
      final res = await _api.post('/games/${session['_id']}/next');
      if (res.statusCode == 200 && res.data['success'] == true) {
        checkActiveGame();
      }
    } catch (e) {
      print("Next round error: $e");
      Get.snackbar("Error", "Failed to advance round.");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> finishGame() async {
    final session = activeSession.value;
    if (session == null) return;
    isLoading.value = true;
    try {
      final res = await _api.post('/games/${session['_id']}/end');
      if (res.statusCode == 200 && res.data['success'] == true) {
        activeSession.value = null;
        currentRoundAnswers.clear();
        hasSubmittedAnswer.value = false;
        Get.back();
      }
    } catch (e) {
      print("End game error: $e");
      Get.snackbar("Error", "Failed to end game.");
    } finally {
      isLoading.value = false;
    }
  }
}
