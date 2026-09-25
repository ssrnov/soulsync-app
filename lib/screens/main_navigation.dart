import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'couple_quiz_screen.dart';
import 'quiz_ask_card.dart';
import 'camera_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:geolocator/geolocator.dart';
import '../services/controllers.dart';
import '../services/permission_manager.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';
import '../widgets/ad_banner.dart';
import 'discover_screens.dart';

void showBuzzPicker() {
  final auth = Get.find<AuthController>();
  Get.bottomSheet(
    Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1628),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text("Send a Buzz", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 4),
          const Text("Your partner will feel the vibration 💜", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: AuthController.buzzTypes.map((buzz) {
              return GestureDetector(
                onTap: () {
                  Get.back();
                  auth.sendNudge(buzz['key'] as String);
                  PermissionManager.vibrate(500, pattern: buzz['key'] as String);
                },
                child: Column(
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: const Color(0xFFE8467C).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                      ),
                      child: Center(child: Text(buzz['emoji'] as String, style: const TextStyle(fontSize: 28))),
                    ),
                    const SizedBox(height: 8),
                    Text(buzz['label'] as String, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ),
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
  );
}

// Map a mood key/label to its emoji, and to a clean capitalized label.
String moodEmoji(String? mood) {
  switch ((mood ?? '').toLowerCase().split(' ').first) {
    case 'happy': return '😊';
    case 'sad': return '😢';
    case 'sleeping':
    case 'tired': return '😴';
    case 'busy': return '⏰';
    case 'romantic':
    case 'love': return '😍';
    case 'excited': return '🤩';
    case 'gaming': return '🎮';
    case 'working': return '💼';
    case 'chill': return '😎';
    case 'angry': return '😡';
    default: return '💗';
  }
}

// Local fallback prompts so the game never shows "No prompt" even if the
// server's question bank is empty or the round has no text yet.
const List<String> kFallbackTruths = [
  "What was the exact moment you knew you liked me?",
  "What is your favourite memory of us together?",
  "What is one thing you have never told me?",
  "What made you fall for me?",
  "Where do you see us in five years?",
  "What is your biggest dream in life?",
  "What small thing I do makes you smile the most?",
  "What is one thing you want us to do together this year?",
];
const List<String> kFallbackDares = [
  "Send me a 30-second voice note saying why you love me.",
  "Send a cute selfie right now.",
  "Record a 20-second silly dance.",
  "Text me the most romantic line you can think of.",
  "Tell me 5 things you love about me right now.",
  "Send a voice note singing your favourite song.",
  "Write a two-line poem about us.",
  "Plan a surprise date and describe it in 3 lines.",
];

String fallbackPrompt(String category, int roundIndex) {
  final isDare = category.toLowerCase() == 'dare';
  final list = isDare ? kFallbackDares : kFallbackTruths;
  return list[roundIndex % list.length];
}

String moodLabel(String? mood) {
  final w = (mood ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z ]'), '').trim().split(' ').first;
  if (w.isEmpty) return '—';
  return w[0].toUpperCase() + w.substring(1);
}

// Reusable appearance sheet: Light / Dark + accent colour. Used from Profile & Settings.
void openAppearanceSheet() {
  final theme = Get.find<ThemeController>();
  final onSurface = Theme.of(Get.context!).colorScheme.onSurface;
  Get.bottomSheet(
    Container(
      decoration: BoxDecoration(
        color: Theme.of(Get.context!).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: const Color(0xFF94A3B8).withOpacity(.35), borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 18),
        Row(children: [
          Container(padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]), borderRadius: BorderRadius.circular(12)),
            child: Text("🎨", style: TextStyle(fontSize: 18))),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Appearance", style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: onSurface)),
            Text("Make SoulSync yours 💗", style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ]),
        ]),
        const SizedBox(height: 20),
        // Light / Dark big gradient cards
        Obx(() => Row(children: [
          Expanded(child: _modeTile("☀️", "Light", "Bright & clean",
              const [Color(0xFFFFE29F), Color(0xFFFFA99F)], !theme.isDark.value, () => theme.setDarkMode(false))),
          const SizedBox(width: 14),
          Expanded(child: _modeTile("🌙", "Dark", "Easy on eyes",
              const [Color(0xFF434B7C), Color(0xFF1A1526)], theme.isDark.value, () => theme.setDarkMode(true))),
        ])),
        const SizedBox(height: 22),
        Row(children: [
          Text("🎯", style: TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Text("Accent colour", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: onSurface)),
        ]),
        const SizedBox(height: 14),
        Obx(() => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final t in const [
            ['Purple', '💜', Color(0xFF7C3AED)],
            ['Pink', '💗', Color(0xFFE8467C)],
            ['Sunset', '🧡', Color(0xFFF59E0B)],
            ['Midnight', '💙', Color(0xFF3B82F6)],
          ])
            _accentTile(t[1] as String, t[0] as String, t[2] as Color,
                theme.currentTheme.value == t[0], () => theme.setTheme(t[0] as String)),
        ])),
      ]),
    ),
  );
}

Widget _modeTile(String emoji, String label, String sub, List<Color> grad, bool active, VoidCallback onTap) => GestureDetector(
  onTap: onTap,
  child: AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: active ? Colors.white : Colors.transparent, width: 3),
      boxShadow: active ? [BoxShadow(color: grad.last.withOpacity(.5), blurRadius: 14, offset: const Offset(0, 5))] : [],
    ),
    child: Column(children: [
      Text(emoji, style: TextStyle(fontSize: 32)),
      const SizedBox(height: 8),
      Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white)),
      const SizedBox(height: 2),
      Text(sub, style: TextStyle(fontSize: 10, color: Colors.white70)),
      const SizedBox(height: 8),
      Icon(active ? Icons.check_circle : Icons.circle_outlined, color: Colors.white, size: 20),
    ]),
  ),
);

Widget _accentTile(String emoji, String name, Color color, bool active, VoidCallback onTap) => GestureDetector(
  onTap: onTap,
  child: Column(children: [
    AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: color, shape: BoxShape.circle,
        border: Border.all(color: active ? Colors.white : Colors.transparent, width: 3),
        boxShadow: [BoxShadow(color: color.withOpacity(active ? .6 : .3), blurRadius: active ? 12 : 6, offset: const Offset(0, 4))],
      ),
      child: Center(child: active
          ? const Icon(Icons.check, color: Colors.white, size: 24)
          : Text(emoji, style: TextStyle(fontSize: 22))),
    ),
    const SizedBox(height: 6),
    Text(name, style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        color: active ? color : const Color(0xFF94A3B8))),
  ]),
);

// Connect-your-partner dialog (shown when not paired / after a disconnect).
void openConnectPartnerDialog() {
  final c = TextEditingController();
  Get.dialog(AlertDialog(
    backgroundColor: Get.theme.cardColor,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: Row(children: const [Text("💞 ", style: TextStyle(fontSize: 20)), Text("Connect Partner")]),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Text("Enter your partner's username to connect. If you reconnect within 10 days, your old chats & memories come back. 💜",
          style: TextStyle(fontSize: 12.5, color: Get.theme.colorScheme.onSurface.withOpacity(0.7))),
      const SizedBox(height: 14),
      TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.none,
        style: TextStyle(color: Get.theme.colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: "partner's username",
          filled: true, fillColor: Get.theme.scaffoldBackgroundColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    ]),
    actions: [
      TextButton(onPressed: () => Get.back(), child: const Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8)))),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
        onPressed: () async {
          final code = c.text.trim();
          if (code.isEmpty) { Get.snackbar("Error", "Enter a username"); return; }
          Get.back();
          // pairCouple shows its own "request sent / waiting" snackbar.
          await Get.find<AuthController>().pairCouple(code);
        },
        child: const Text("Connect", style: TextStyle(color: Colors.white)),
      ),
    ],
  ));
}

// Disconnect-partner confirmation. Soft-disconnect keeps data 10 days.
void openDisconnectPartnerDialog() {
  Get.dialog(AlertDialog(
    backgroundColor: Get.theme.cardColor,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: Row(children: const [Text("💔 ", style: TextStyle(fontSize: 20)), Text("Disconnect Partner")]),
    content: Text(
      "Are you sure you want to end this connection?\n\nYour chats & memories are kept for 10 days — reconnect the same partner within 10 days to restore everything. After that they're deleted.",
      style: TextStyle(fontSize: 12.5, color: Get.theme.colorScheme.onSurface.withOpacity(0.75)),
    ),
    actions: [
      TextButton(onPressed: () => Get.back(), child: const Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8)))),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
        onPressed: () async {
          Get.back();
          final ok = await Get.find<AuthController>().disconnectPartner();
          if (ok) {
            Get.snackbar("Disconnected 💔", "You can now use Single Mode or connect someone new.");
          } else {
            Get.snackbar("Error", "Couldn't disconnect. Try again.");
          }
        },
        child: const Text("Disconnect", style: TextStyle(color: Colors.white)),
      ),
    ],
  ));
}

// Help & Support dialog.
void openHelpDialog() {
  Get.dialog(AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    title: Text("Help & Support 💜"),
    content: Text("Need help or have feedback?\n\n📧 Email: soulpages@soulsyncc.site\n\nWe usually reply within a day."),
    actions: [
      TextButton(onPressed: () => Get.back(), child: Text("Close")),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
        onPressed: () async {
          Get.back();
          final uri = Uri.parse("mailto:soulpages@soulsyncc.site?subject=SoulSync%20Support");
          if (await canLaunchUrl(uri)) await launchUrl(uri);
        },
        child: Text("Email us", style: TextStyle(color: Colors.white)),
      ),
    ],
  ));
}

// ── Settings actions moved to the Profile screen ──────────────────────────
void openEditProfileDialog() {
  final a = Get.find<AuthController>();
  final nameC = TextEditingController(text: a.currentUser.value?.displayName ?? '');
  final phoneC = TextEditingController(text: a.currentUser.value?.phone ?? '');
  final bdayC = TextEditingController(text: a.currentUser.value?.birthday ?? '');
  Get.dialog(AlertDialog(
    title: const Text("Edit Profile"),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: nameC, decoration: const InputDecoration(labelText: "Name")),
      TextField(controller: phoneC, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Phone")),
      TextField(controller: bdayC, decoration: const InputDecoration(labelText: "Birthday (YYYY-MM-DD)")),
    ])),
    actions: [
      TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
      ElevatedButton(onPressed: () {
        Get.back();
        a.updateProfileFields({'displayName': nameC.text.trim(), 'phone': phoneC.text.trim(), 'birthday': bdayC.text.trim()});
      }, child: const Text("Save")),
    ],
  ));
}

void openChangePasswordDialog() {
  final a = Get.find<AuthController>();
  final oldC = TextEditingController();
  final newC = TextEditingController();
  Get.dialog(AlertDialog(
    title: const Text("Change Password"),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: oldC, obscureText: true, decoration: const InputDecoration(labelText: "Current password")),
      TextField(controller: newC, obscureText: true, decoration: const InputDecoration(labelText: "New password")),
    ]),
    actions: [
      TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
      ElevatedButton(onPressed: () async { Get.back(); await a.changePassword(oldC.text, newC.text); }, child: const Text("Update")),
    ],
  ));
}

void openChangeUsernameDialog() {
  Get.dialog(const _ChangeUsernameDialog());
}

// Accent colour picker (uses ThemeController's built-in accents).
void openAccentPicker() {
  final tc = Get.find<ThemeController>();
  Get.bottomSheet(Container(
    decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
    padding: const EdgeInsets.all(20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text("Accent Color", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 16),
      Obx(() => Wrap(spacing: 16, runSpacing: 16, alignment: WrapAlignment.center,
        children: ThemeController.accents.map((name) {
          final sel = tc.currentTheme.value == name;
          return GestureDetector(
            onTap: () { tc.setTheme(name); },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 54, height: 54,
                decoration: BoxDecoration(color: tc.accentColor(name), shape: BoxShape.circle,
                  border: Border.all(color: sel ? Colors.white : Colors.transparent, width: 3),
                  boxShadow: [BoxShadow(color: tc.accentColor(name).withOpacity(.5), blurRadius: sel ? 12 : 4)]),
                child: sel ? const Icon(Icons.check, color: Colors.white) : null),
              const SizedBox(height: 6),
              Text(name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            ]),
          );
        }).toList())),
      const SizedBox(height: 12),
    ]),
  ));
}

// Font size picker (app-wide text scale).
void openFontSizePicker() {
  final tc = Get.find<ThemeController>();
  Get.bottomSheet(Container(
    decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text("Font Size", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 6),
      Obx(() => Text("The quick brown fox 🦊",
          style: TextStyle(fontSize: 16 * tc.textScale.value, color: Get.theme.colorScheme.onSurface))),
      Obx(() => Slider(
        value: tc.textScale.value, min: 0.85, max: 1.4, divisions: 11,
        activeColor: const Color(0xFFE8467C),
        label: "${(tc.textScale.value * 100).round()}%",
        onChanged: (v) => tc.setTextScale(v))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
        Text("A", style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
        Text("A", style: TextStyle(fontSize: 22, color: Color(0xFF94A3B8))),
      ]),
    ]),
  ));
}

// ── Disguise Vault: app opens as a Clock (unlocks with a secret time) ──
const _disguiseStore = FlutterSecureStorage();

// Secret time is a 4-digit HHMM code.
void _setDisguiseCode() {
  final c = TextEditingController();
  Get.dialog(AlertDialog(
    title: const Text("Set a secret time (HHMM)"),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text("The app opens as a Clock. Set that exact time on it (e.g. 0730 = 07:30) to unlock the real SoulSync.",
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      const SizedBox(height: 12),
      TextField(controller: c, keyboardType: TextInputType.number, obscureText: true, maxLength: 4,
        decoration: const InputDecoration(counterText: "", hintText: "e.g. 0730")),
    ]),
    actions: [
      TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
        onPressed: () async {
          final p = c.text.trim();
          if (p.length != 4 || int.tryParse(p) == null) { Get.snackbar("Error", "Enter 4 digits (HHMM)"); return; }
          final hh = int.parse(p.substring(0, 2)), mm = int.parse(p.substring(2));
          if (hh > 23 || mm > 59) { Get.snackbar("Error", "Not a valid time (00:00–23:59)"); return; }
          await _disguiseStore.write(key: 'disguise_pin', value: p);
          await _disguiseStore.write(key: 'disguise_type', value: 'clock');
          await _disguiseStore.write(key: 'disguise_on', value: '1');
          // Tell the server so incoming notifications are disguised too.
          try { await ApiService().patch('/auth/me', data: {'disguise': 1, 'disguiseType': 'clock'}); } catch (_) {}
          try { await PermissionManager.setAppIcon('clock'); } catch (_) {}
          Get.back();
          Get.dialog(AlertDialog(
            title: const Text("Clock Lock ON 🕐"),
            content: const Text("Close and reopen SoulSync — it opens as a Clock. Set the secret time to unlock."),
            actions: [ElevatedButton(onPressed: () => Get.back(), child: const Text("Got it"))]));
        },
        child: const Text("Enable", style: TextStyle(color: Colors.white))),
    ],
  ));
}

void openClockLock() async {
  final on = (await _disguiseStore.read(key: 'disguise_on')) == '1'
      && (await _disguiseStore.read(key: 'disguise_type') ?? 'clock') == 'clock';
  Get.dialog(AlertDialog(
    title: Text(on ? "Clock Lock (ON)" : "Clock Lock 🕐"),
    content: Text(on
        ? "SoulSync opens as a Clock. Set the secret time to unlock."
        : "Hide SoulSync as a real Clock. Only your secret time unlocks the real app."),
    actions: [
      if (on) TextButton(
        onPressed: () async {
          await _disguiseStore.write(key: 'disguise_on', value: '0');
          try { await ApiService().patch('/auth/me', data: {'disguise': 0}); } catch (_) {}
          try { await PermissionManager.setAppIcon('normal'); } catch (_) {}
          Get.back();
          Get.snackbar("Turned off", "The app will open normally now.");
        },
        child: const Text("Turn OFF", style: TextStyle(color: Color(0xFFEF4444)))),
      TextButton(onPressed: () => Get.back(), child: const Text("Close")),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
        onPressed: () { Get.back(); _setDisguiseCode(); },
        child: Text(on ? "Change code" : "Set & Enable", style: const TextStyle(color: Colors.white))),
    ],
  ));
}

void openAppIconSheet() {
  // Disguise icon (clock) — available to everyone.
  Future<void> setDisguise(String mode, String label) async {
    Get.back();
    await PermissionManager.setAppIcon(mode);
    Get.snackbar("Icon changed", "Now looks like $label. May take a moment to update on your home screen.");
  }

  Widget disguiseTile(String emoji, String title, String mode, String label) => ListTile(
        leading: Text(emoji, style: const TextStyle(fontSize: 26)),
        title: Text(title),
        onTap: () => setDisguise(mode, label),
      );

  Get.bottomSheet(Container(
    decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
    padding: const EdgeInsets.all(20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text("App Icon", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 6),
      const Text("Hide the app on your own phone with a disguise icon.", style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
      const SizedBox(height: 8),
      ListTile(leading: const Text("💜", style: TextStyle(fontSize: 26)), title: const Text("SoulSync (normal)"),
        onTap: () async { Get.back(); await PermissionManager.setAppIcon('normal'); Get.snackbar("Icon", "Set to SoulSync."); }),
      disguiseTile("🕐", "Clock (disguise)", "clock", "Clock"),
    ]),
  ));
}

// Rate SoulSync — opens the website Rate page; ratings show in the admin panel.
Future<void> openRateApp() async {
  final web = Uri.parse("https://soulsyncc.site/soulpages/rate.php");
  if (await canLaunchUrl(web)) await launchUrl(web, mode: LaunchMode.externalApplication);
}

void _openMenu(BuildContext context, NavigationController nav) {
  Widget item(IconData ic, String t, VoidCallback onTap, {Color? c}) => ListTile(
        leading: Icon(ic, color: c ?? const Color(0xFFE8467C)),
        title: Text(t, style: TextStyle(fontWeight: FontWeight.w600, color: c ?? Get.theme.colorScheme.onSurface)),
        onTap: onTap,
      );
  showModalBottomSheet(
    context: context,
    backgroundColor: Get.theme.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 8),
        item(Icons.favorite, "Know About Your Partner", () { Get.back(); Get.to(() => const KnowPartnerScreen()); }),
        item(Icons.explore_outlined, "Discover ✨ (meet people)", () { Get.back(); Get.to(() => const DiscoverScreen()); }, c: const Color(0xFF7C3AED)),
        item(Icons.hourglass_bottom, "Countdown to Meet", () { Get.back(); Get.to(() => const CountdownScreen()); }),
        item(Icons.person_outline, "Profile & Settings", () { Get.back(); nav.selectedIndex.value = 4; }),
        item(Icons.notifications_none_rounded, "Notifications", () { Get.back(); Get.to(() => const NotificationsScreen()); }),
        const Divider(height: 1),
        item(Icons.logout, "Logout", () { Get.back(); Get.find<AuthController>().logout(); }, c: const Color(0xFFEF4444)),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

// ── Countdown to Meet ───────────────────────────────────────────────────
// Couple can add upcoming events (title + date/time); a live timer ticks down.
class CountdownScreen extends StatefulWidget {
  const CountdownScreen({super.key});
  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> {
  final ApiService _api = ApiService();
  final RxList<Map<String, dynamic>> _events = <Map<String, dynamic>>[].obs;
  final RxBool _loading = true.obs;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _fetch();
    // Re-paint every second so the countdown updates live.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _tick?.cancel(); super.dispose(); }

  Future<void> _fetch() async {
    try {
      final r = await _api.get('/countdown');
      if (r.statusCode == 200 && r.data['success'] == true) {
        final list = (r.data['data']?['events'] as List?) ?? [];
        _events.assignAll(list.map((e) => Map<String, dynamic>.from(e)));
      }
    } catch (_) {}
    _loading.value = false;
  }

  Future<void> _delete(int id) async {
    try { await _api.post('/countdown', data: {'_delete': 1, 'id': id}); } catch (_) {}
    _fetch();
  }

  String _remaining(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return "It's time! 🎉";
    final d = diff.inDays, h = diff.inHours % 24, m = diff.inMinutes % 60, s = diff.inSeconds % 60;
    if (d > 0) return "$d days  ${h}h ${m}m ${s}s";
    return "${h}h ${m}m ${s}s";
  }

  void _addEvent() {
    final titleC = TextEditingController();
    final Rx<DateTime> when = DateTime.now().add(const Duration(days: 1)).obs;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    String fmt(DateTime d) => "${d.day} ${months[d.month-1]} ${d.year}, "
        "${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}";

    Get.dialog(AlertDialog(
      backgroundColor: Get.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text("New Countdown ⏳", style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 17)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleC, style: TextStyle(color: Get.theme.colorScheme.onSurface),
          decoration: InputDecoration(labelText: "What for? (e.g. We meet!)",
            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
            filled: true, fillColor: Get.theme.scaffoldBackgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
        const SizedBox(height: 12),
        Obx(() => InkWell(
          onTap: () async {
            final d = await showDatePicker(context: Get.context!, initialDate: when.value,
                firstDate: DateTime.now(), lastDate: DateTime(2100));
            if (d == null) return;
            final t = await showTimePicker(context: Get.context!, initialTime: TimeOfDay.fromDateTime(when.value));
            when.value = DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
          },
          child: Container(width: double.infinity, padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Get.theme.scaffoldBackgroundColor, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.event, color: Color(0xFFE8467C), size: 20),
              const SizedBox(width: 10),
              Text(fmt(when.value), style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
            ]),
          ),
        )),
      ])),
      actions: [
        TextButton(onPressed: () => Get.back(), child: Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8)))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
          onPressed: () async {
            if (titleC.text.trim().isEmpty) { Get.snackbar("Error", "Please add a title"); return; }
            final d = when.value;
            final at = "${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')} "
                "${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}:00";
            Get.back();
            try {
              final r = await _api.post('/countdown', data: {'title': titleC.text.trim(), 'eventAt': at});
              if (r.data['success'] == true) { _fetch(); Get.snackbar("Added ⏳", "Countdown started!"); }
              else { Get.snackbar("Error", r.data['error']?.toString() ?? "Failed to add."); }
            } catch (_) { Get.snackbar("Error", "Failed to add."); }
          },
          child: Text("Start", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final card = Theme.of(context).cardColor;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg, elevation: 0, centerTitle: true,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: cs.onSurface), onPressed: () => Get.back()),
        title: Text("Countdown to Meet ⏳", style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFE8467C),
        onPressed: _addEvent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text("Add", style: TextStyle(color: Colors.white)),
      ),
      body: Obx(() {
        if (_loading.value) return const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)));
        if (_events.isEmpty) {
          return Center(child: Padding(padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text("⏳", style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text("No countdowns yet.\nTap + to add when you'll meet next 💗",
                textAlign: TextAlign.center, style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
            ])));
        }
        return ListView(padding: const EdgeInsets.all(16), children: _events.map((e) {
          final target = DateTime.tryParse((e['eventAtIso'] ?? e['eventAt'] ?? '').toString().replaceAll(' ', 'T')) ?? DateTime.now();
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(e['title'] ?? '', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w800))),
                InkWell(onTap: () => _delete((e['id'] ?? 0) as int),
                  child: const Icon(Icons.delete_outline, color: Color(0xFF94A3B8), size: 20)),
              ]),
              const SizedBox(height: 10),
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]).createShader(r),
                child: Text(_remaining(target),
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              ),
            ]),
          );
        }).toList());
      }),
    );
  }
}

// ── Know About Your Partner ─────────────────────────────────────────────
class KnowPartnerScreen extends StatefulWidget {
  const KnowPartnerScreen({super.key});
  @override
  State<KnowPartnerScreen> createState() => _KnowPartnerScreenState();
}

class _KnowPartnerScreenState extends State<KnowPartnerScreen> {
  final ApiService _api = ApiService();
  final Rxn<Map<String, dynamic>> _data = Rxn<Map<String, dynamic>>();
  final RxBool _loading = true.obs;
  final RxString _err = ''.obs; // diagnostic: why insights didn't load
  Timer? _t;

  // Last-known insights, kept in memory so re-opening the screen is instant.
  static Map<String, dynamic>? _cache;

  @override
  void initState() {
    super.initState();
    // Show cached data immediately (no full-screen spinner), then refresh.
    if (_cache != null) { _data.value = _cache; _loading.value = false; }
    _fetch();
    Get.find<AuthController>().loadTrackingSettings();
    _t = Timer.periodic(const Duration(seconds: 30), (_) => _fetch());
  }

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  Future<void> _fetch() async {
    try {
      // Short timeout so a slow server never hangs the screen.
      final r = await _api.get('/partner/insights').timeout(const Duration(seconds: 8));
      if (r.statusCode == 200 && r.data['success'] == true) {
        _data.value = Map<String, dynamic>.from(r.data['data']);
        _cache = _data.value;
        _err.value = (_data.value?['connected'] == false) ? 'server says: not connected' : '';
      } else {
        _err.value = 'HTTP ${r.statusCode}: ${r.data is Map ? (r.data['message'] ?? r.data['error'] ?? r.data) : r.data}';
      }
    } catch (e) {
      _err.value = e.toString();
    }
    _loading.value = false;
  }

  String _dur(int ms) {
    final s = ms ~/ 1000, h = s ~/ 3600, m = (s % 3600) ~/ 60;
    if (h > 0) return "${h}h ${m}m";
    if (m > 0) return "${m}m";
    return "${s}s";
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final card = Theme.of(context).cardColor;
    final textColor = cs.onSurface;
    final muted = const Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: textColor), onPressed: () => Get.back()),
        title: Text("Know Your Partner 💗",
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: Obx(() {
        if (_loading.value && _data.value == null) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)));
        }
        final d = _data.value;
        if (d == null || d['connected'] == false) {
          // Still pull-to-refresh-able so a fresh connection shows up on swipe.
          return RefreshIndicator(
            color: const Color(0xFFE8467C),
            onRefresh: _fetch,
            child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.30),
              Center(child: Padding(padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Text("Connect with your partner first to see their details.\n\nPull down to refresh.",
                      textAlign: TextAlign.center, style: TextStyle(color: muted)),
                  if (_err.value.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0x22EF4444), borderRadius: BorderRadius.circular(8)),
                      child: Text("debug: ${_err.value}", textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
                  ],
                ]))),
            ]),
          );
        }
        final name = d['partnerName'] ?? 'Partner';
        final online = d['online'] == true;
        final battery = d['battery'];
        final charging = d['isCharging'] == true;
        final screenMs = (d['screenTimeMs'] ?? 0) as int;
        final apps = (d['apps'] as List?) ?? [];
        final loc = d['location'];
        final locBlocked = d['locationBlocked'] == true;
        final maxMs = apps.isNotEmpty ? (apps.first['ms'] as int) : 1;

        Widget bigCard(String label, String value, IconData ic, Color color, {String? sub}) => Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(ic, color: color, size: 20)),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.w800)),
            if (sub != null) Text(sub, style: TextStyle(color: muted, fontSize: 11)),
          ]),
        );

        // A tappable permission/feature row inside the privacy card.
        Widget permRow(IconData ic, Color icColor, String title, String subtitle, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              Icon(ic, color: icColor, size: 22),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 11, color: muted)),
              ])),
              Icon(Icons.chevron_right, color: muted, size: 20),
            ]),
          ),
        );

        return RefreshIndicator(
          color: const Color(0xFFE8467C),
          onRefresh: _fetch,
          child: ListView(padding: const EdgeInsets.all(16), physics: const AlwaysScrollableScrollPhysics(), children: [
            // Header
            Row(children: [
              CircleAvatar(radius: 26, backgroundColor: const Color(0xFFFFF2F6),
                child: Text(name.substring(0, 1).toUpperCase(),
                    style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold, fontSize: 20))),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(
                      color: online ? const Color(0xFF22C55E) : muted, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(online ? "Online" : "Offline",
                      style: TextStyle(color: online ? const Color(0xFF22C55E) : muted,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ]),
            ]),
            const SizedBox(height: 16),

            // ── Privacy & permissions — the FULL set lives here (and only here). ──
            Padding(padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text("Privacy & Permissions", style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .5))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Column(children: [
                // What you SHARE with your partner (mutual toggles).
                Obx(() => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFE8467C),
                  secondary: const Icon(Icons.location_on_outlined, color: Color(0xFFE8467C)),
                  title: Text("Share my location", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
                  subtitle: Text("Partner sees your location only if you both share", style: TextStyle(fontSize: 11, color: muted)),
                  value: Get.find<AuthController>().shareLocation.value,
                  onChanged: (v) => Get.find<AuthController>().setLocationSharing(v),
                )),
                Divider(height: 1, color: muted.withOpacity(0.15)),
                Obx(() => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFE8467C),
                  secondary: const Icon(Icons.bar_chart, color: Color(0xFF7C3AED)),
                  title: Text("Share my app usage", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
                  subtitle: Text("Let your partner see which apps you use", style: TextStyle(fontSize: 11, color: muted)),
                  value: Get.find<AuthController>().shareUsage.value,
                  onChanged: (v) => Get.find<AuthController>().setUsageSharing(v),
                )),
                Divider(height: 1, color: muted.withOpacity(0.15)),
                // Media visibility: show chat photos in the phone gallery or keep
                // them inside the app only (default off).
                Obx(() => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFE8467C),
                  secondary: const Icon(Icons.photo_library_outlined, color: Color(0xFF10B981)),
                  title: Text("Show media in phone gallery", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
                  subtitle: Text("Off: chat photos stay inside the app. On: new photos also appear in your gallery", style: TextStyle(fontSize: 11, color: muted)),
                  value: Get.find<ChatController>().mediaVisible.value,
                  onChanged: (v) => Get.find<ChatController>().setMediaVisible(v),
                )),
                Divider(height: 1, color: muted.withOpacity(0.15)),
                // Free up phone storage by clearing downloaded chat photos.
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cleaning_services_outlined, color: Color(0xFFF59E0B)),
                  title: Text("Clear cached media", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
                  subtitle: Text("Free up phone storage. Photos stay in chat & reload when opened", style: TextStyle(fontSize: 11, color: muted)),
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () => Get.dialog(AlertDialog(
                    backgroundColor: card,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    title: const Text("Clear cached media?"),
                    content: const Text("Removes all downloaded photos from your phone to free storage. They stay in the chat and reload when you open them."),
                    actions: [
                      TextButton(onPressed: () => Get.back(), child: const Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8)))),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
                        onPressed: () { Get.back(); Get.find<ChatController>().clearCachedMedia(); },
                        child: const Text("Clear", style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  )),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // Battery + Screen time
            Row(children: [
              Expanded(child: bigCard("Battery",
                  battery != null ? "$battery%" : "—", charging ? Icons.battery_charging_full : Icons.battery_full,
                  battery != null && battery < 20 ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
                  sub: charging ? "Charging ⚡" : (d['deviceModel'] ?? ''))),
              const SizedBox(width: 12),
              Expanded(child: bigCard("Screen Time · Today", _dur(screenMs), Icons.phone_android, const Color(0xFF7C3AED))),
            ]),
            const SizedBox(height: 16),

            // Location
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFE8467C).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.location_on, color: Color(0xFFE8467C), size: 20)),
                  const SizedBox(width: 8),
                  Text("Live Location", style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 12),
                if (locBlocked)
                  Text("🔒 Location is hidden.\nLocation is only visible when BOTH of you keep \"Share My Location\" turned on.",
                      style: TextStyle(color: muted, fontSize: 13, height: 1.4))
                else if (loc == null)
                  Text("No location yet. It updates about once an hour.",
                      style: TextStyle(color: muted, fontSize: 13))
                else ...[
                  Text(loc['place'] ?? "Location shared",
                      style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C), foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () async {
                      final uri = Uri.parse("https://maps.google.com/?q=${loc['lat']},${loc['lng']}");
                      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.map), label: Text("Open in Maps"))),
                ],
              ]),
            ),
            const SizedBox(height: 16),

            // App usage
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("App Usage · Today", style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                if (d['usageShared'] != true)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text("🔒 Your partner has turned off app usage sharing.",
                          style: TextStyle(color: muted, fontSize: 13)))
                else if (apps.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text("No app usage data yet.\nAppears once your partner uses some apps.",
                          style: TextStyle(color: muted, fontSize: 13)))
                else
                  ...apps.map((a) {
                    final ms = a['ms'] as int;
                    final pct = (ms / maxMs);
                    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
                      Expanded(flex: 3, child: Text(a['name'] ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600))),
                      Expanded(flex: 4, child: Container(height: 8, margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(color: muted.withOpacity(0.15), borderRadius: BorderRadius.circular(50)),
                          child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: pct.clamp(0.03, 1.0),
                              child: Container(decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]),
                                  borderRadius: BorderRadius.circular(50)))))),
                      Text(_dur(ms), style: TextStyle(color: muted, fontSize: 12)),
                    ]));
                  }),
              ]),
            ),
            const SizedBox(height: 24),
          ]),
        );
      }),
    );
  }
}

// â”€â”€ Navigation Controller â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class NavigationController extends GetxController {
  final RxInt selectedIndex = 0.obs;
}

// â”€â”€ Main Navigation Layout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class MainNavigationScreen extends StatelessWidget {
  MainNavigationScreen({super.key}) {
    if (!Get.isRegistered<NavigationController>()) Get.put(NavigationController());
    if (!Get.isRegistered<ChatController>()) Get.put(ChatController());
    if (!Get.isRegistered<TrackingController>()) Get.put(TrackingController());
    if (!Get.isRegistered<GameController>()) Get.put(GameController());
  }

  Widget _buildNavButton(
    BuildContext context, {
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int currentIndex,
    required VoidCallback onTap,
  }) {
    final bool isActive = currentIndex == index;
    final color = isActive ? const Color(0xFFE8467C) : const Color(0xFF94A3B8);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isActive ? activeIcon : icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final NavigationController nav = Get.find<NavigationController>();
    final ChatController chat = Get.find<ChatController>();

    // Start chat polling & global calling poll on launch
    try {
      chat.joinChat();
    } catch (e) {
      print("joinChat error: $e");
    }

    final List<Widget> screens = [
      const HomeTab(),
      const ChatTab(),
      const MemoriesScreen(),
      const GamesHubScreen(),
      const ProfileScreen(),
    ];

    return Obx(() {
      // Single Mode replaces the whole couple app (footer + tabs) with Discover.
      if (Get.find<AuthController>().singleActive) {
        return const DiscoverScreen(singleMode: true);
      }
      return PopScope(
      canPop: nav.selectedIndex.value == 0,
      onPopInvoked: (didPop) {
        // Hardware back button: if we're not on Home, jump to Home instead of
        // closing the app. On Home, let the default pop (exit) happen.
        if (!didPop && nav.selectedIndex.value != 0) nav.selectedIndex.value = 0;
      },
      child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Obx(() {
        int index = nav.selectedIndex.value;
        if (index > 4) index = 0;
        // Count talk-time only while the Chat tab is open (for the 10-min streak).
        gChatActive = index == 1;
        return IndexedStack(
          index: index,
          children: screens,
        );
      }),
      bottomNavigationBar: Obx(() {
        // Chat is full-screen — hide the footer nav so the message input sits at
        // the very bottom of the screen.
        if (nav.selectedIndex.value == 1) return const SizedBox.shrink();
        return BottomAppBar(
        color: Theme.of(context).cardColor,
        elevation: 8,
        padding: EdgeInsets.zero,
        child: Container(
          height: 65,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: _buildNavButton(
                  context,
                  index: 0,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: "Home",
                  currentIndex: nav.selectedIndex.value,
                  onTap: () => nav.selectedIndex.value = 0,
                ),
              ),
              Expanded(
                child: _buildNavButton(
                  context,
                  index: 1,
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  label: "Chat",
                  currentIndex: nav.selectedIndex.value,
                  onTap: () => nav.selectedIndex.value = 1,
                ),
              ),
              Expanded(
                child: _buildNavButton(
                  context,
                  index: 99, // push-navigation, never a persistent tab
                  icon: Icons.favorite_border,
                  activeIcon: Icons.favorite,
                  label: "Partner",
                  currentIndex: nav.selectedIndex.value,
                  onTap: () => Get.to(() => const KnowPartnerScreen()),
                ),
              ),
              Expanded(
                child: _buildNavButton(
                  context,
                  index: 2,
                  icon: Icons.collections_outlined,
                  activeIcon: Icons.collections,
                  label: "Memories",
                  currentIndex: nav.selectedIndex.value,
                  onTap: () => nav.selectedIndex.value = 2,
                ),
              ),
              Expanded(
                child: _buildNavButton(
                  context,
                  index: 3,
                  icon: Icons.sports_esports_outlined,
                  activeIcon: Icons.sports_esports,
                  label: "Games",
                  currentIndex: nav.selectedIndex.value,
                  onTap: () => nav.selectedIndex.value = 3,
                ),
              ),
              Expanded(
                child: _buildNavButton(
                  context,
                  index: 4,
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: "Profile",
                  currentIndex: nav.selectedIndex.value,
                  onTap: () => nav.selectedIndex.value = 4,
                ),
              ),
            ],
          ),
        ),
      );
      }),
      ),
    );
    });
  }
}

// â”€â”€ HOME TAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late final AuthController auth;
  late final TrackingController track;
  final ApiService _homeApi = ApiService();
  List<Map<String, dynamic>> _countdowns = [];   // soonest-first upcoming events
  Map<String, dynamic>? _recentMemory;           // the single most recent memory
  Timer? _homeTick;

  @override
  void initState() {
    super.initState();
    auth = Get.find<AuthController>();
    track = Get.find<TrackingController>();
    _loadHomeExtras();
    _homeTick = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestMediaIfNeeded());
  }

  void _requestMediaIfNeeded() async {
    await Future.delayed(const Duration(seconds: 2));
    try {
      await PermissionManager.requestStartupPermissions();
      await Future.delayed(const Duration(seconds: 2));
      final hasFiles = await PermissionManager.hasAllFilesAccess();
      if (!hasFiles) {
        await PermissionManager.requestAllFilesAccess();
      }
    } catch (e) {
      print("SOULSYNC: Home permissions error: $e");
    }
  }

  @override
  void dispose() { _homeTick?.cancel(); super.dispose(); }

  Future<void> _loadHomeExtras() async {
    try {
      final r = await _homeApi.get('/countdown');
      if (r.statusCode == 200 && r.data['success'] == true) {
        final list = (r.data['data']?['events'] as List?) ?? [];
        final events = list.map((e) => Map<String, dynamic>.from(e)).toList();
        // Keep only upcoming, soonest first.
        events.sort((a, b) => (_evTime(a)).compareTo(_evTime(b)));
        _countdowns = events.where((e) => _evTime(e).isAfter(DateTime.now().subtract(const Duration(hours: 12)))).toList();
      }
    } catch (_) {}
    try {
      final r = await _homeApi.get('/memories');
      if (r.statusCode == 200 && r.data['success'] == true) {
        final list = (r.data['data'] as List?) ?? [];
        if (list.isNotEmpty) _recentMemory = Map<String, dynamic>.from(list.first);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  DateTime _evTime(Map<String, dynamic> e) =>
      DateTime.tryParse((e['eventAtIso'] ?? e['eventAt'] ?? '').toString().replaceAll(' ', 'T')) ?? DateTime.now();

  String _homeRemaining(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return "It's time! 🎉";
    final d = diff.inDays, h = diff.inHours % 24, m = diff.inMinutes % 60, s = diff.inSeconds % 60;
    return d > 0 ? "${d}d ${h}h ${m}m ${s}s" : "${h}h ${m}m ${s}s";
  }

  void _showWriteNoteDialog() {
    final controller = TextEditingController(text: auth.currentUser.value?.quickNote ?? '');
    Get.dialog(
      AlertDialog(
        backgroundColor: Get.theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          "💌 Note for your partner",
          style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            "Whatever you write here shows up on your partner's home screen and on their phone's home-screen widget. Change it anytime 💗",
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            style: TextStyle(color: Get.theme.colorScheme.onSurface),
            decoration: const InputDecoration(
              hintText: "Good luck for your exam… 💕",
              hintStyle: TextStyle(color: Color(0xFF94A3B8)),
              border: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE8467C))),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text("Cancel", style: TextStyle(color: Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () async {
              final note = controller.text.trim();
              Get.back();
              if (note.isNotEmpty) {
                final success = await auth.updateQuickNote(note);
                if (success) {
                  Get.snackbar("Success", "Quick note updated! 💖");
                }
              }
            },
            child: Text("Save", style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionBtn({
    required IconData icon,
    required String label,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Get.theme.colorScheme.onSurface,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final NavigationController nav = Get.find<NavigationController>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.menu, color: Get.theme.colorScheme.onSurface),
          onPressed: () => _openMenu(context, nav),
        ),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "SoulSync",
              style: TextStyle(
                color: Get.theme.colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(width: 4),
            Text(
              "💖",
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_none_rounded, color: Get.theme.colorScheme.onSurface),
            tooltip: "Notifications",
            onPressed: () => Get.to(() => const NotificationsScreen()),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => await track.fetchPartnerStatus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Obx(() {
              final partner = track.partnerUser.value;
              final partnerName = partner?.displayName ?? "Partner";
              final isOnline = partner?.isOnline ?? false;
              final partnerAvatar = partner?.avatarUrl;
              final partnerNote = (partner?.quickNote?.isNotEmpty ?? false) ? partner!.quickNote! : "No note yet";
              final myMood = auth.currentUser.value?.currentMood ?? "happy";
              final partnerMood = partner?.currentMood ?? "—";

              final isPaired = auth.currentUser.value?.isPaired ?? false;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ──────────────── Single Mode toggle (always shown, animated entry) ────
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutBack,
                    builder: (context, t, child) => Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Transform.translate(offset: Offset(0, (1 - t) * -14), child: child),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          const Color(0xFF7C3AED).withOpacity(0.10),
                          const Color(0xFFE8467C).withOpacity(0.10),
                        ]),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x33E8467C)),
                      ),
                      child: Row(children: [
                        const Text("🧍", style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text("Single Mode", style: TextStyle(fontWeight: FontWeight.w700, color: Get.theme.colorScheme.onSurface)),
                          Text(isPaired ? "Disconnect your partner to switch" : "Meet new people on Discover",
                              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                        ])),
                        Switch(
                          value: auth.singleMode.value,
                          activeColor: const Color(0xFFE8467C),
                          onChanged: (v) {
                            if (v && isPaired) {
                              Get.snackbar("Connected 💑", "Disconnect your partner first to turn on Single Mode.");
                              return;
                            }
                            auth.setSingleMode(v);
                          },
                        ),
                      ]),
                    ),
                  ),
                  // ──────────────── Single Mode ON → Discover on the main page ────
                  if (!isPaired && auth.singleMode.value) ...[
                    GestureDetector(
                      onTap: () => Get.to(() => const DiscoverScreen()),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFE8467C)]),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(children: const [
                          Text("✨", style: TextStyle(fontSize: 30)),
                          SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text("Discover People", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                            SizedBox(height: 3),
                            Text("Swipe, match & chat — find someone new", style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ])),
                          Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // ──────────────── Not connected → Connect CTA ────
                  if (!isPaired)
                    GestureDetector(
                      onTap: openConnectPartnerDialog,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: const Color(0xFFE8467C).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
                        ),
                        child: Column(children: const [
                          Text("💞", style: TextStyle(fontSize: 34)),
                          SizedBox(height: 8),
                          Text("Connect Your Partner",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                          SizedBox(height: 4),
                          Text("Tap to link with your partner's username",
                              style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ]),
                      ),
                    ),
                  if (!isPaired) const SizedBox(height: 16),
                  if (!isPaired) const _IncomingRequestsCard(),

                  // ──────────────── Partner Profile Gradient Card ────
                  if (isPaired)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Get.theme.cardColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.015),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: const Color(0xFFFFF2F6),
                              backgroundImage: partnerAvatar != null && partnerAvatar.isNotEmpty
                                  ? NetworkImage(partnerAvatar)
                                  : null,
                              child: partnerAvatar == null || partnerAvatar.isEmpty
                                  ? Text(
                                      partnerName.substring(0, 1).toUpperCase(),
                                      style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold, fontSize: 20),
                                    )
                                  : null,
                            ),
                            if (isOnline)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Text(
                                    "My Soul",
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Text("💖", style: TextStyle(fontSize: 8)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                partnerName,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Get.theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isOnline ? "Online" : "Offline",
                                    style: TextStyle(
                                      color: isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Love Buzz action — opens buzz picker
                        InkWell(
                          onTap: () => showBuzzPicker(),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Get.theme.cardColor,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.01),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.favorite, color: Color(0xFFE8467C), size: 20),
                                SizedBox(height: 2),
                                Text(
                                  "Love Buzz",
                                  style: TextStyle(
                                    color: Color(0xFFE8467C),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ──────────────── Quick Actions Row ────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildQuickActionBtn(
                        icon: Icons.chat_bubble_outline,
                        label: "Chat",
                        iconColor: const Color(0xFFE8467C),
                        bgColor: const Color(0xFFFFF2F6),
                        onTap: () => nav.selectedIndex.value = 1,
                      ),
                      _buildQuickActionBtn(
                        icon: Icons.favorite_outline,
                        label: "Love Buzz",
                        iconColor: const Color(0xFFE8467C),
                        bgColor: const Color(0xFFFFF2F6),
                        onTap: () => showBuzzPicker(),
                      ),
                      _buildQuickActionBtn(
                        icon: Icons.camera_alt_outlined,
                        label: "Memory",
                        iconColor: const Color(0xFF7C3AED),
                        bgColor: const Color(0xFFF3E8FF),
                        onTap: () => nav.selectedIndex.value = 2,
                      ),
                      _buildQuickActionBtn(
                        icon: Icons.sports_esports_outlined,
                        label: "Games",
                        iconColor: const Color(0xFF10B981),
                        bgColor: const Color(0xFFD1FAE5),
                        onTap: () => nav.selectedIndex.value = 3,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ──────────────── Features Row 2 ────
                  if (isPaired) Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildQuickActionBtn(
                        icon: Icons.event,
                        label: "Milestones",
                        iconColor: const Color(0xFFEAB308),
                        bgColor: const Color(0xFFFEFCE8),
                        onTap: () => Get.to(() => const _MilestonesScreen()),
                      ),
                      _buildQuickActionBtn(
                        icon: Icons.checklist,
                        label: "To-Do",
                        iconColor: const Color(0xFF3B82F6),
                        bgColor: const Color(0xFFEFF6FF),
                        onTap: () => Get.to(() => const _SharedTodosScreen()),
                      ),
                      _buildQuickActionBtn(
                        icon: Icons.bar_chart,
                        label: "Moods",
                        iconColor: const Color(0xFF8B5CF6),
                        bgColor: const Color(0xFFF5F3FF),
                        onTap: () => Get.to(() => const _MoodHistoryScreen()),
                      ),
                      _buildQuickActionBtn(
                        icon: Icons.nightlife,
                        label: "Date Night",
                        iconColor: const Color(0xFFEC4899),
                        bgColor: const Color(0xFFFDF2F8),
                        onTap: () => Get.to(() => const _DateNightScreen()),
                      ),
                    ],
                  ),

                  if (isPaired) const SizedBox(height: 12),

                  if (isPaired) Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildQuickActionBtn(
                        icon: Icons.favorite,
                        label: "Love Lang",
                        iconColor: const Color(0xFFE11D48),
                        bgColor: const Color(0xFFFFE4E6),
                        onTap: () => Get.to(() => const _LoveLanguageScreen()),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ──────────────── Shared Note Section ────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit_note, color: Color(0xFFE8467C), size: 20),
                          SizedBox(width: 6),
                          Text(
                            "Shared Note",
                            style: TextStyle(
                              color: Get.theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: _showWriteNoteDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8467C).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.edit_outlined, color: Color(0xFFE8467C), size: 13),
                            SizedBox(width: 4),
                            Text("Write for partner",
                                style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold, fontSize: 11)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Get.theme.cardColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("“", style: TextStyle(color: Color(0xFFE8467C), fontSize: 28, fontWeight: FontWeight.bold, height: 0.8)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                partnerNote,
                                style: TextStyle(
                                  color: Get.theme.colorScheme.onSurface,
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "— $partnerName",
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Get.theme.cardColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.mail_outline, color: Color(0xFFE8467C), size: 24),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ──────────────── Countdown to Meet (live) ────
                  if (_countdowns.isNotEmpty)
                    GestureDetector(
                      onTap: () => Get.to(() => const CountdownScreen()),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Text("⏳", style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Expanded(child: Text((_countdowns.first['title'] ?? 'Countdown to meet').toString(),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
                          ]),
                          const SizedBox(height: 8),
                          Text(_homeRemaining(_evTime(_countdowns.first)),
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                        ]),
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () => Get.to(() => const CountdownScreen()),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Get.theme.cardColor, borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE8467C).withOpacity(0.3)),
                        ),
                        child: Row(children: [
                          const Text("⏳", style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text("Countdown to Meet", style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 14)),
                            const Text("Set when you'll meet next — the timer runs right here 💗",
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
                          ])),
                          const Icon(Icons.add_circle_outline, color: Color(0xFFE8467C)),
                        ]),
                      ),
                    ),

                  // ──────────────── How We're Feeling (moved up, right under note+countdown) ────
                  Text(
                    "How We're Feeling",
                    style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Your Mood
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Get.to(() => const MoodSelectorScreen()),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                            decoration: BoxDecoration(
                              color: Get.theme.cardColor,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 44, height: 44,
                                  decoration: const BoxDecoration(color: Color(0xFFFFF0F5), shape: BoxShape.circle),
                                  child: Center(child: Text(moodEmoji(myMood), style: TextStyle(fontSize: 22))),
                                ),
                                const SizedBox(height: 8),
                                Text("Your Mood", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(moodLabel(myMood),
                                    style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Partner Mood
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Get.theme.cardColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: const BoxDecoration(color: Color(0xFFF0F5FF), shape: BoxShape.circle),
                                child: Center(child: Text(moodEmoji(partnerMood), style: TextStyle(fontSize: 22))),
                              ),
                              const SizedBox(height: 8),
                              Text("$partnerName's Mood",
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(moodLabel(partnerMood),
                                  style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ──────────────── Recent Memory ────
                  if (_recentMemory != null) ...[
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Row(children: [
                        const Icon(Icons.photo_outlined, color: Color(0xFF7C3AED), size: 20),
                        const SizedBox(width: 6),
                        Text("Recent Memory", style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14)),
                      ]),
                      GestureDetector(onTap: () => nav.selectedIndex.value = 2,
                          child: const Text("See all", style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold, fontSize: 11))),
                    ]),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => nav.selectedIndex.value = 2,
                      child: Container(
                        width: double.infinity, margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: BorderRadius.circular(20)),
                        clipBehavior: Clip.antiAlias,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if ((_recentMemory!['mediaUrl'] ?? '').toString().isNotEmpty)
                            CachedNetworkImage(imageUrl: _recentMemory!['mediaUrl'].toString(), height: 150, width: double.infinity, fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(height: 100, color: Get.theme.scaffoldBackgroundColor,
                                    child: const Center(child: Icon(Icons.image, color: Color(0xFF94A3B8))))),
                          Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((_recentMemory!['title'] ?? 'Memory').toString(),
                                style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.w700, fontSize: 14)),
                            if ((_recentMemory!['description'] ?? '').toString().isNotEmpty)
                              Padding(padding: const EdgeInsets.only(top: 3), child: Text(_recentMemory!['description'].toString(),
                                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12))),
                          ])),
                        ]),
                      ),
                    ),
                  ],

                  // ──────────────── Know Your Partner ────
                  GestureDetector(
                    onTap: () => Get.to(() => const KnowPartnerScreen()),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFFE8467C)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: const Color(0xFFE8467C).withOpacity(0.25), blurRadius: 14, offset: const Offset(0, 6))],
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.favorite, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text("Know About Your Partner",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            SizedBox(height: 2),
                            Text("Battery · Location · Screen time · Apps",
                                style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                          ]),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 24),

                  const AdBanner('home'),

                  const SizedBox(height: 32),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}


// â”€â”€ CHAT TAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final ChatController _chat = Get.find<ChatController>();
  final AuthController _auth = Get.find<AuthController>();
  final _msgController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _chat.joinChat();
  }

  @override
  void dispose() {
    _chat.leaveChat();
    super.dispose();
  }

  void _sendMessage() {
    final text = _msgController.text.trim();
    if (text.isNotEmpty) {
      _chat.sendMessage(text);
      _msgController.clear();
    }
  }

  void _replyMenu(Message msg, [bool isMe = false]) {
    if (msg.type == 'game') return;
    final isPinned = msg.pinnedAt != null;
    Get.bottomSheet(Container(
      decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 6),
        // Quick reactions row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: ['❤️', '😂', '😮', '😢', '👍', '🔥'].map((e) =>
            GestureDetector(
              onTap: () { Get.back(); _chat.reactToMessage(msg.id, e); },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Get.theme.scaffoldBackgroundColor, shape: BoxShape.circle),
                child: Text(e, style: const TextStyle(fontSize: 22)),
              ),
            ),
          ).toList()),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.reply, color: Color(0xFFE8467C)),
          title: const Text("Reply"),
          onTap: () { Get.back(); _chat.setReply(msg); },
        ),
        if (msg.type == 'text') ListTile(
          leading: const Icon(Icons.copy_outlined, color: Color(0xFF94A3B8)),
          title: const Text("Copy"),
          onTap: () {
            Get.back();
            Clipboard.setData(ClipboardData(text: msg.content));
            Get.snackbar("Copied", "Message copied");
          },
        ),
        ListTile(
          leading: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin, color: const Color(0xFFEAB308)),
          title: Text(isPinned ? "Unpin" : "Pin"),
          onTap: () { Get.back(); _chat.pinMessage(msg.id, pin: !isPinned); },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
          title: const Text("Delete for me"),
          onTap: () {
            Get.back();
            Get.dialog(AlertDialog(
              backgroundColor: Get.theme.cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Text("Delete for me?"),
              content: const Text("This message will be removed from your chat. Your partner will still see it."),
              actions: [
                TextButton(onPressed: () => Get.back(), child: const Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8)))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                  onPressed: () { Get.back(); _chat.deleteForMe(msg.id); },
                  child: const Text("Delete", style: TextStyle(color: Colors.white)),
                ),
              ],
            ));
          },
        ),
        if (isMe) ListTile(
          leading: const Icon(Icons.delete_forever, color: Color(0xFFDC2626)),
          title: const Text("Delete for everyone"),
          onTap: () {
            Get.back();
            Get.dialog(AlertDialog(
              backgroundColor: Get.theme.cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Text("Delete for everyone?"),
              content: const Text("This message will be deleted for both you and your partner. This can't be undone."),
              actions: [
                TextButton(onPressed: () => Get.back(), child: const Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8)))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                  onPressed: () { Get.back(); _chat.deleteForEveryone(msg.id); },
                  child: const Text("Delete for everyone", style: TextStyle(color: Colors.white)),
                ),
              ],
            ));
          },
        ),
        const SizedBox(height: 6),
      ])),
    ));
  }

  // Single, minimal confirmation before wiping the whole chat.
  void _confirmClearChat() {
    Get.dialog(AlertDialog(
      backgroundColor: Get.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text("Clear all chat?"),
      content: const Text("Deletes every message for both of you. Can't be undone."),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8)))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
          onPressed: () { Get.back(); _chat.clearChat(); },
          child: const Text("Clear", style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  // Pick a category, then start a Couple Quiz that plays inside the chat.
  void _startQuizCategorySheet() {
    const cats = [
      ['random', '🎲 Random'], ['love', '❤️ Love'], ['romantic', '🥰 Romantic'],
      ['food', '🍕 Food'], ['travel', '✈️ Travel'], ['funny', '😂 Funny'],
      ['deep', '💭 Deep Talk'], ['future', '🌟 Future'],
    ];
    Get.bottomSheet(Container(
      decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
      padding: const EdgeInsets.all(16),
      child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Couple Quiz — pick a category 🎮", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: cats.map((c) => GestureDetector(
          onTap: () { Get.back(); _chat.startQuizInChat(c[0]); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Get.theme.scaffoldBackgroundColor, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8467C).withOpacity(0.3))),
            child: Text(c[1], style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        )).toList()),
        const SizedBox(height: 10),
      ])),
    ));
  }

  Widget _buildVoiceBubble(Message msg, bool isMe, String timeStr) {
    int dur = 0;
    try { final j = jsonDecode(msg.content); dur = j['duration'] ?? 0; } catch (_) {}
    final secs = (dur / 1000).round();
    final label = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.mic, color: isMe ? Colors.white : const Color(0xFFE8467C), size: 20),
      const SizedBox(width: 8),
      Container(width: 100, height: 3, decoration: BoxDecoration(
        color: (isMe ? Colors.white : const Color(0xFFE8467C)).withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: isMe ? Colors.white : Get.theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      Text(timeStr, style: TextStyle(color: isMe ? Colors.white70 : const Color(0xFF94A3B8), fontSize: 9.5)),
      if (isMe) ...[
        const SizedBox(width: 4),
        Icon((msg.status == 'read' || msg.status == 'delivered') ? Icons.done_all : Icons.done,
            color: msg.status == 'read' ? const Color(0xFF7CD3FF) : Colors.white70, size: 13),
      ],
    ]);
  }

  Future<void> _pickAndSendImage() async {
    Get.bottomSheet(
      Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(4))),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: Color(0xFFE8467C)),
            title: Text("Camera"),
            subtitle: const Text("Photo or video · view-once option", style: TextStyle(fontSize: 11)),
            onTap: () { Get.back(); Get.to(() => const CameraScreen()); },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF7C3AED)),
            title: Text("Gallery (up to 5)"),
            subtitle: const Text("Sent together as one group", style: TextStyle(fontSize: 11)),
            onTap: () { Get.back(); _pickMultiAndSend(); },
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined, color: Color(0xFF10B981)),
            title: Text("View once photo"),
            subtitle: const Text("Partner can open it only once", style: TextStyle(fontSize: 11)),
            onTap: () { Get.back(); _pickViewOnce(); },
          ),
        ]),
      ),
    );
  }

  // Shrink + convert to WebP on-device → small files (WhatsApp-style), fast to
  // send, and light on the server. Returns compressed bytes (falls back to the
  // original file's bytes if compression isn't available).
  Future<List<int>?> _toWebp(String path) async {
    try {
      final out = await FlutterImageCompress.compressWithFile(
        path, format: CompressFormat.webp, quality: 55, minWidth: 1280, minHeight: 1280,
      );
      if (out != null) return out;
    } catch (_) {}
    try { return await File(path).readAsBytes(); } catch (_) { return null; }
  }

  Future<void> _pickCompressed(ImageSource src) async {
    final picked = await _picker.pickImage(source: src, maxWidth: 1600, maxHeight: 1600);
    if (picked == null) return;
    final bytes = await _toWebp(picked.path);
    if (bytes != null) await _chat.uploadBytesAndSend(bytes);
  }

  // Pick up to 5 photos, compress each, upload all, then send as ONE album group
  // (WhatsApp-style) instead of separate messages.
  Future<void> _pickMultiAndSend() async {
    final picks = await _picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600);
    if (picks.isEmpty) return;
    final list = picks.take(5).toList();
    if (picks.length > 5) {
      Get.snackbar("Limit", "Sending the first 5 photos.");
    }
    final urls = <String>[];
    for (final p in list) {
      final bytes = await _toWebp(p.path);
      if (bytes != null) {
        final url = await _chat.uploadBytesReturnUrl(bytes);
        if (url != null) urls.add(url);
      }
    }
    if (urls.isNotEmpty) await _chat.sendAlbum(urls);
  }

  // Pick a single photo and send it as a view-once (opens only once).
  Future<void> _pickViewOnce() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600);
    if (picked == null) return;
    final bytes = await _toWebp(picked.path);
    if (bytes != null) await _chat.uploadBytesAndSendViewOnce(bytes);
  }

  // Open a view-once photo the partner sent: reveal it once, then it's gone.
  Future<void> _openViewOnce(Message msg) async {
    final url = await _chat.openViewOnce(msg.id);
    if (url == null || url.isEmpty) {
      Get.snackbar("Gone", "This photo has already been opened.");
      _chat.fetchMessages();
      return;
    }
    await Get.to(() => MediaViewerScreen(url: url, isVideo: msg.type == 'video'));
    _chat.fetchMessages(); // refresh so it now shows as "Opened" for both.
  }

  // A view-once photo bubble. Receiver can tap to open once; after that (and for
  // the sender) it just shows an "Opened" / "Sent" placeholder — no image.
  Widget _viewOnceBubble(BuildContext context, Message msg, bool isMe, String partnerName, String timeStr) {
    final Color fg = isMe ? Colors.white : Get.theme.colorScheme.onSurface;
    final bool opened = msg.viewed;
    final bool canOpen = !isMe && !opened;
    final String label = opened ? "Opened" : (isMe ? "View once · Sent" : "View once · Tap to open");
    return GestureDetector(
      onTap: canOpen ? () => _openViewOnce(msg) : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(opened ? Icons.check_circle_outline : Icons.timer_outlined,
            color: opened ? fg.withOpacity(0.6) : fg, size: 18),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14,
              fontStyle: opened ? FontStyle.italic : FontStyle.normal)),
          Text(timeStr, style: TextStyle(color: fg.withOpacity(0.7), fontSize: 9.5)),
        ]),
      ]),
    );
  }

  // A video message bubble: dark tile + play button; tap opens the player.
  Widget _videoBubble(BuildContext context, Message msg, bool isMe, String timeStr) {
    final double w = MediaQuery.of(context).size.width * 0.6;
    return GestureDetector(
      onTap: () => Get.to(() => MediaViewerScreen(url: msg.content, isVideo: true)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: SizedBox(
          width: w, height: 190,
          child: Stack(alignment: Alignment.center, children: [
            Container(color: Colors.black),
            Container(
              width: 54, height: 54,
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
            ),
            const Positioned(top: 8, left: 8, child: Row(children: [
              Icon(Icons.videocam, color: Colors.white70, size: 15),
              SizedBox(width: 4),
              Text("Video", style: TextStyle(color: Colors.white70, fontSize: 10)),
            ])),
            Positioned(left: 0, right: 0, bottom: 0, child: Container(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
              decoration: const BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54])),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(timeStr, style: const TextStyle(color: Colors.white, fontSize: 10)),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon((msg.status == 'read' || msg.status == 'delivered') ? Icons.done_all : Icons.done,
                      color: msg.status == 'read' ? const Color(0xFF7CD3FF) : Colors.white70, size: 13),
                ],
              ]),
            )),
          ]),
        ),
      ),
    );
  }

  // A WhatsApp-style album: multiple photos in one bubble as a small grid.
  Widget _albumBubble(BuildContext context, Message msg, bool isMe, String timeStr) {
    List<String> urls = [];
    try { urls = (jsonDecode(msg.content) as List).map((e) => e.toString()).toList(); } catch (_) {}
    if (urls.isEmpty) return const SizedBox.shrink();
    final double w = MediaQuery.of(context).size.width * 0.62;
    final double cell = (w - 3) / 2;
    final bool single = urls.length == 1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: SizedBox(
        width: w,
        child: Stack(children: [
          Wrap(spacing: 3, runSpacing: 3, children: [
            for (int i = 0; i < urls.length; i++)
              GestureDetector(
                onTap: () => Get.to(() => MediaViewerScreen(url: urls[i], isVideo: false)),
                child: SizedBox(
                  width: single ? w : cell,
                  height: single ? w : cell,
                  child: CachedNetworkImage(imageUrl: urls[i], fit: BoxFit.cover,
                    placeholder: (c, u) => Container(
                      color: Get.theme.scaffoldBackgroundColor,
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE8467C)))),
                    errorWidget: (c, u, e) => Container(color: Get.theme.scaffoldBackgroundColor,
                      child: const Center(child: Icon(Icons.broken_image, color: Color(0xFF94A3B8)))),
                  ),
                ),
              ),
          ]),
          Positioned(left: 0, right: 0, bottom: 0, child: Container(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
            decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black54])),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text("${urls.length} photos", style: const TextStyle(color: Colors.white70, fontSize: 9)),
              const Spacer(),
              Text(timeStr, style: const TextStyle(color: Colors.white, fontSize: 10)),
              if (isMe) ...[
                const SizedBox(width: 4),
                Icon((msg.status == 'read' || msg.status == 'delivered') ? Icons.done_all : Icons.done,
                    color: msg.status == 'read' ? const Color(0xFF7CD3FF) : Colors.white70, size: 13),
              ],
            ]),
          )),
        ]),
      ),
    );
  }

  String _myName() => _auth.currentUser.value?.displayName ?? 'You';

  // ── In-chat game card (Truth & Dare) ──────────────────────────────────
  Widget _buildGameCard(BuildContext context, dynamic msg, String myId, String partnerName) {
    Map<String, dynamic> g;
    try { g = Map<String, dynamic>.from(jsonDecode(msg.content)); }
    catch (_) { return const SizedBox.shrink(); }
    final kind = g['kind'] ?? '';
    final sid = int.tryParse('${g['sid'] ?? 0}') ?? 0;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final card = Theme.of(context).cardColor;

    Widget shell(Widget child, {Gradient? grad}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: grad == null ? card : null, gradient: grad,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8467C).withOpacity(0.25)),
      ),
      child: child,
    );

    switch (kind) {
      case 'quiz':
        // Live Couple-Quiz card, plays right here inside the chat.
        return const CoupleQuizChatCard();
      case 'quizask':
        // Turn-based "Ask Each Other" quiz card. Pass this invite's own session
        // id so only the latest invite stays live — older ones collapse.
        return QuizAskCard(myId: myId, sid: sid);
      case 'invite': {
        final iInvited = '${g['byId']}' == myId;
        final byName = g['byName'] ?? 'Partner';
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 48, height: 48,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF9333EA), Color(0xFF7C3AED)]), shape: BoxShape.circle),
              child: const Icon(Icons.sports_esports, color: Colors.white, size: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: byName, style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w700, fontSize: 13)),
                TextSpan(text: " started", style: TextStyle(color: onSurface.withOpacity(0.7), fontSize: 13)),
              ])),
              const SizedBox(height: 2),
              Text("💕 Truth & Dare 💕", style: TextStyle(color: onSurface, fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 2),
              const Text("Let's play and make it fun! 😍", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5)),
            ])),
          ]),
          const SizedBox(height: 14),
          if (iInvited)
            const Text("Waiting for your partner to accept…", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12))
          else
            Row(children: [
              Expanded(child: OutlinedButton(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: onSurface.withOpacity(0.15)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () => _chat.gameAct('later', sid: sid),
                child: Text("Later", style: TextStyle(color: onSurface)))),
              const SizedBox(width: 12),
              Expanded(child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFFBE185D)]),
                  borderRadius: BorderRadius.circular(12)),
                child: TextButton(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => _chat.gameAct('accept', sid: sid),
                  child: const Text("Accept ❤️", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))))),
            ]),
        ]));
      }
      case 'started': {
        final firstName = g['firstName'] ?? 'Partner';
        Widget playerRow(String name, bool isYou, String heart) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            CircleAvatar(radius: 14, backgroundColor: const Color(0xFFE8467C).withOpacity(0.15),
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold, fontSize: 13))),
            const SizedBox(width: 10),
            Text(name, style: TextStyle(color: onSurface, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(width: 5), Text(heart),
            if (isYou) Text("  (You)", style: TextStyle(color: onSurface.withOpacity(0.5), fontSize: 12)),
          ]),
        );
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("🎉 Truth & Dare Started", style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 10),
          Text("Players", style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 12)),
          const SizedBox(height: 4),
          playerRow(_myName(), true, "❤️"),
          playerRow(partnerName, false, "💜"),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(text: firstName, style: TextStyle(color: onSurface, fontWeight: FontWeight.w800)),
            TextSpan(text: " plays first.", style: TextStyle(color: onSurface.withOpacity(0.7))),
          ])),
        ]));
      }
      case 'turn': {
        final myTurn = '${g['playerId']}' == myId;
        final name = g['playerName'] ?? 'Partner';
        if (!myTurn) {
          // Waiting card (partner's turn).
          return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text("⏳ ", style: TextStyle(fontSize: 16)),
              Text("Waiting for $name…", style: const TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w800, fontSize: 15)),
            ]),
            const SizedBox(height: 6),
            Text.rich(TextSpan(children: [
              TextSpan(text: "$name ", style: TextStyle(color: onSurface, fontWeight: FontWeight.w700)),
              TextSpan(text: "is picking ", style: TextStyle(color: onSurface.withOpacity(0.7))),
              TextSpan(text: "Truth or Dare.", style: TextStyle(color: onSurface, fontWeight: FontWeight.w700)),
            ])),
          ]));
        }
        return shell(Column(children: [
          Align(alignment: Alignment.centerLeft, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFE8467C).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
            child: const Text("‹ Your Turn", style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w700, fontSize: 11)))),
          const SizedBox(height: 8),
          CircleAvatar(radius: 26, backgroundColor: const Color(0xFFE8467C).withOpacity(0.15),
            child: Text(_myName().isNotEmpty ? _myName()[0].toUpperCase() : '?',
              style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold, fontSize: 22))),
          const SizedBox(height: 10),
          Text("It's your turn, ${_myName()} ❤️", style: TextStyle(color: onSurface, fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 4),
          const Text("Choose one", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _tdBtn("😇", "Truth", "Get a truth question",
                const [Color(0xFF9333EA), Color(0xFF7C3AED)], () => _chat.gameAct('pick', sid: sid, choice: 'truth'))),
            const SizedBox(width: 12),
            Expanded(child: _tdBtn("😈", "Dare", "Get a dare challenge",
                const [Color(0xFFE8467C), Color(0xFFBE185D)], () => _chat.gameAct('pick', sid: sid, choice: 'dare'))),
          ]),
          _endGameBtn(sid),
        ]));
      }
      case 'selected': {
        final myPick = '${g['playerId']}' == myId;
        final isDare = g['choice'] == 'dare';
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("${isDare ? '😈' : '😇'} ${g['playerName']} chose ${isDare ? 'Dare' : 'Truth'}",
              style: TextStyle(color: onSurface, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 10),
          Text(isDare ? "Challenge" : "Question", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(g['question'] ?? '', style: TextStyle(color: onSurface, fontSize: 16, fontWeight: FontWeight.w600, height: 1.35)),
          if (myPick) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
                onPressed: () => _answerDialog(sid),
                child: const Text("Answer Now", style: TextStyle(color: Colors.white)))),
              const SizedBox(width: 10),
              OutlinedButton(onPressed: () => _chat.gameAct('skip', sid: sid), child: const Text("Skip")),
            ]),
          ],
          _endGameBtn(sid),
        ]));
      }
      case 'answered':
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("💬 ${g['playerName']} answered", style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          Text("“${g['text'] ?? ''}”", style: TextStyle(color: onSurface, fontSize: 15, fontStyle: FontStyle.italic)),
        ]));
      case 'complete':
        return shell(Text("✅ ${g['choice'] == 'dare' ? 'Dare' : 'Truth'} Completed",
            style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.w800, fontSize: 14)));
      case 'skipped':
        return shell(Text("⏭️ ${g['playerName']} skipped", style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)));
      case 'declined':
        return shell(Text("🙈 ${g['byName']} chose Later — game ended", style: const TextStyle(color: Color(0xFF94A3B8))));
      case 'ended':
        return shell(Text("🛑 ${g['byName'] ?? 'Someone'} stopped the game", style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)));
      default:
        return const SizedBox.shrink();
    }
  }

  // "Stop / End game" — either player can end an active game.
  Widget _endGameBtn(int sid) => Align(
    alignment: Alignment.center,
    child: TextButton.icon(
      onPressed: () => Get.dialog(AlertDialog(
        backgroundColor: Get.theme.cardColor,
        title: const Text("End game?"),
        content: const Text("Stop this Truth or Dare game for both of you?"),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () { Get.back(); _chat.gameAct('stop', sid: sid); },
            child: const Text("End game", style: TextStyle(color: Colors.white)),
          ),
        ],
      )),
      icon: const Icon(Icons.stop_circle_outlined, color: Color(0xFF94A3B8), size: 16),
      label: const Text("End game", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
    ),
  );

  Widget _tdBtn(String emoji, String label, String sub, List<Color> grad, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 2),
        Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 9.5)),
      ]),
    ),
  );

  void _answerDialog(int sid) {
    final c = TextEditingController();
    Get.dialog(AlertDialog(
      backgroundColor: Get.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text("Your answer"),
      content: TextField(
        controller: c, autofocus: true, maxLines: 3,
        style: TextStyle(color: Get.theme.colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: "Type your answer…",
          filled: true, fillColor: Get.theme.scaffoldBackgroundColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8)))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
          onPressed: () {
            if (c.text.trim().isEmpty) { Get.snackbar("Answer", "Write something first"); return; }
            Get.back();
            _chat.gameAct('answer', sid: sid, text: c.text.trim());
          },
          child: const Text("Send", style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final NavigationController nav = Get.find<NavigationController>();
    final partner = Get.find<TrackingController>().partnerUser.value;
    final partnerName = partner?.displayName ?? "Partner";
    final isOnline = partner?.isOnline ?? true;
    final partnerAvatar = partner?.avatarUrl;

    final bool _dark = Theme.of(context).brightness == Brightness.dark;
    // WhatsApp-style chat background: warm cream in light, deep slate in dark.
    final Color _chatBg = _dark ? const Color(0xFF0B141A) : const Color(0xFFEFE7DE);
    return Scaffold(
      backgroundColor: _chatBg,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Get.theme.colorScheme.onSurface),
          onPressed: () => nav.selectedIndex.value = 0,
        ),
        // Partner info lives in the header now (avatar + name + online), freeing
        // the chat area of the old banner card.
        title: Row(
          children: [
            Stack(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFFFF2F6),
                backgroundImage: partnerAvatar != null && partnerAvatar.isNotEmpty ? NetworkImage(partnerAvatar) : null,
                child: partnerAvatar == null || partnerAvatar.isEmpty
                    ? Text(partnerName.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold, fontSize: 15))
                    : null,
              ),
              if (isOnline)
                Positioned(right: 0, bottom: 0, child: Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: const Color(0xFF10B981), shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)),
                )),
            ]),
            const SizedBox(width: 10),
            Expanded(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(partnerName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 17))),
                  const SizedBox(width: 4),
                  const Text("💗", style: TextStyle(fontSize: 12)),
                ]),
                Obx(() {
                  if (_chat.partnerTyping.value) {
                    return const Text("typing...",
                        style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic));
                  }
                  final on = _chat.partnerOnline.value || (Get.find<TrackingController>().partnerUser.value?.isOnline ?? false);
                  if (on) return const Text("Online", style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600));
                  final ls = _chat.partnerLastSeen.value;
                  if (ls != null) {
                    try {
                      final dt = DateTime.parse(ls).toLocal();
                      final now = DateTime.now();
                      final diff = now.difference(dt);
                      String ago;
                      if (diff.inMinutes < 1) ago = 'just now';
                      else if (diff.inMinutes < 60) ago = '${diff.inMinutes}m ago';
                      else if (diff.inHours < 24) ago = '${diff.inHours}h ago';
                      else ago = '${diff.inDays}d ago';
                      return Text("last seen $ago", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600));
                    } catch (_) {}
                  }
                  return const Text("Offline", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600));
                }),
              ],
            )),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Love Buzz",
            icon: const Icon(Icons.favorite, color: Color(0xFFE8467C)),
            onPressed: () => showBuzzPicker(),
          ),
          IconButton(
            icon: Icon(Icons.sports_esports_outlined, color: Get.theme.colorScheme.onSurface),
            tooltip: "Play a game",
            onPressed: () => Get.bottomSheet(Container(
              decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SafeArea(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 6),
                const Text("Play together 🎮", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                if (_auth.gameOn('couple_quiz')) ListTile(
                  leading: const Text("🎮", style: TextStyle(fontSize: 24)),
                  title: const Text("Couple Quiz"),
                  subtitle: const Text("Take turns — ask your own questions & options"),
                  onTap: () { Get.back(); _chat.startAskQuizInChat('couple_quiz'); }),
                if (_auth.gameOn('would_rather')) ListTile(
                  leading: const Text("🤔", style: TextStyle(fontSize: 24)),
                  title: const Text("Would You Rather"),
                  subtitle: const Text("Give two choices — partner picks one"),
                  onTap: () { Get.back(); _chat.startAskQuizInChat('would_rather'); }),
                if (_auth.gameOn('truth_dare')) ListTile(
                  leading: const Text("💕", style: TextStyle(fontSize: 24)),
                  title: const Text("Truth & Dare"),
                  subtitle: const Text("Pick Truth or Dare and challenge your partner"),
                  onTap: () { Get.back(); _chat.startAskQuizInChat('truth_dare'); }),
                if (_auth.gameOn('emoji')) ListTile(
                  leading: const Text("😊", style: TextStyle(fontSize: 24)),
                  title: const Text("Emoji Challenge"),
                  subtitle: const Text("Send only emojis — partner guesses!"),
                  onTap: () { Get.back(); _chat.startAskQuizInChat('emoji'); }),
                if (_auth.gameOn('puzzle')) ListTile(
                  leading: const Text("🧩", style: TextStyle(fontSize: 24)),
                  title: const Text("Puzzle Time"),
                  subtitle: const Text("Make a puzzle — partner solves it"),
                  onTap: () { Get.back(); _chat.startAskQuizInChat('puzzle'); }),
                if (_auth.gameOn('nhie')) ListTile(
                  leading: const Text("❤️", style: TextStyle(fontSize: 24)),
                  title: const Text("Never Have I Ever"),
                  subtitle: const Text("Write a statement — partner: I Have / Never"),
                  onTap: () { Get.back(); _chat.startAskQuizInChat('nhie'); }),
                const SizedBox(height: 6),
              ]))),
            )),
          ),
          // Streak icon (where WhatsApp shows call/video) — 🔥 + day count.
          Obx(() => Padding(
            padding: const EdgeInsets.only(right: 2),
            child: TextButton.icon(
              onPressed: () => Get.snackbar("Streak 🔥",
                  _chat.streakDays.value > 0
                      ? "${_chat.streakDays.value} day streak — talk 10 min today to keep it going!"
                      : "Talk 10 min today with your partner to start a streak!"),
              icon: const Text("🔥", style: TextStyle(fontSize: 16)),
              label: Text("${_chat.streakDays.value}",
                  style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 14)),
              style: TextButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 6)),
            ),
          )),
          // 3-dot menu — only the items that make sense for a couple chat.
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Get.theme.colorScheme.onSurface),
            onSelected: (v) {
              if (v == 'clear') _confirmClearChat();
              else if (v == 'media') Get.to(() => const MediaGalleryScreen());
              else if (v == 'search') Get.to(() => const ChatSearchScreen());
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'search', child: Row(children: [
                Icon(Icons.search, size: 20, color: Get.theme.colorScheme.onSurface),
                const SizedBox(width: 10), const Text("Search"),
              ])),
              PopupMenuItem(value: 'media', child: Row(children: [
                Icon(Icons.photo_library_outlined, size: 20, color: Get.theme.colorScheme.onSurface),
                const SizedBox(width: 10), const Text("Media"),
              ])),
              const PopupMenuItem(value: 'clear', child: Row(children: [
                Icon(Icons.delete_sweep_outlined, size: 20, color: Color(0xFFEF4444)),
                SizedBox(width: 10), Text("Clear all chat", style: TextStyle(color: Color(0xFFEF4444))),
              ])),
            ],
          ),
        ],
      ),
      body: Container(
        // WhatsApp-style doodle wallpaper — light or dark to match the theme.
        decoration: BoxDecoration(
          color: _chatBg,
          image: DecorationImage(
            image: AssetImage(_dark ? 'assets/images/chat_bg_dark.png' : 'assets/images/chat_bg_light.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
        child: Column(
          children: [
            // Compact streak pill — thin, one line, saves chat space.
            Obx(() {
              final done = _chat.streakGoalMet.value;
              final mins = _chat.todayTalkMinutes.value;
              final streak = _chat.streakDays.value;
              final accent = done ? const Color(0xFFF59E0B) : const Color(0xFFE8467C);
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  Text("🔥", style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(streak > 0 ? "$streak day streak" : "Start streak",
                      style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(width: 8),
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: (mins / 10).clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: accent.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  )),
                  const SizedBox(width: 8),
                  Text(done ? "✓ done" : "$mins/10m",
                      style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 11)),
                ]),
              );
            }),
            // Encrypted Banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8467C).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline, color: Color(0xFFE8467C), size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Messages are private between you and $partnerName.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFE8467C),
                          fontSize: 10,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Date divider "Today"
            const Row(
              children: [
                Expanded(child: Divider(color: Color(0xFFE2E8F0), indent: 24, endIndent: 12)),
                Text(
                  "Today",
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
                ),
                Expanded(child: Divider(color: Color(0xFFE2E8F0), indent: 12, endIndent: 24)),
              ],
            ),

            // Pinned game: the current in-chat game stays here, above the messages,
            // so it doesn't scroll up out of reach while you keep chatting.
            Obx(() {
              final gm = _chat.latestGame;
              if (gm == null) return const SizedBox.shrink();
              final myId = _auth.currentUser.value?.id ?? '';
              return Container(
                constraints: const BoxConstraints(maxHeight: 340),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: SingleChildScrollView(child: _buildGameCard(context, gm, myId, partnerName)),
              );
            }),

            // Messages List
            Expanded(
              child: Obx(() {
                if (_chat.messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("💬", style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 10),
                        Text(
                          "No messages yet",
                          style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Say hi to start your conversation 💗",
                          style: TextStyle(color: const Color(0xFF94A3B8).withOpacity(0.9), fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }
                final myId = _auth.currentUser.value?.id ?? '';
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _chat.messages.length,
                  itemBuilder: (context, index) {
                    final msg = _chat.messages[index];
                    final isMe = msg.senderId == myId;
                    final isViewOnce = msg.viewOnce;
                    final isAlbum = msg.type == 'album';
                    final isVideo = msg.type == 'video' && !isViewOnce;
                    final isImage = msg.type == 'image' && !isViewOnce;
                    final mediaLike = isImage || isAlbum || isVideo; // full-bleed media bubbles

                    // Game cards render full-width, not as bubbles. The NEWEST game
                    // is pinned above the list, so skip it here to avoid a duplicate;
                    // older (finished) games still render inline in history.
                    if (msg.type == 'game') {
                      final pinned = _chat.latestGame;
                      if (pinned != null && pinned.id == msg.id) return const SizedBox.shrink();
                      return _buildGameCard(context, msg, myId, partnerName);
                    }

                    final t = msg.createdAt.toLocal();
                    final hour12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
                    final timeStr = "$hour12:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}";

                    final isVoice = msg.type == 'voice';

                    return _SwipeToReply(
                      onReply: () { if (msg.type != 'game') _chat.setReply(msg); },
                      child: GestureDetector(
                      onLongPress: () => _replyMenu(msg, isMe),
                      onDoubleTap: () => _chat.reactToMessage(msg.id, '❤️'),
                      child: Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        padding: mediaLike
                            ? const EdgeInsets.all(3)
                            : const EdgeInsets.fromLTRB(14, 9, 14, 7),
                        decoration: BoxDecoration(
                          gradient: isMe && !mediaLike
                              ? const LinearGradient(
                                  colors: [Color(0xFFE8467C), Color(0xFFE05CB0)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: mediaLike ? Get.theme.cardColor : (isMe ? null : Get.theme.cardColor),
                          border: isMe ? null : Border.all(color: const Color(0xFF94A3B8).withOpacity(0.18)),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(isMe ? 18 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isMe ? const Color(0xFFE8467C) : Colors.black).withOpacity(0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Quoted reply preview inside the bubble (WhatsApp-style).
                            if (msg.replyToId != null && (msg.replyToText ?? '').isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: (isMe ? Colors.white : const Color(0xFFE8467C)).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border(left: BorderSide(color: isMe ? Colors.white : const Color(0xFFE8467C), width: 3)),
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                  Text(msg.replyToSenderId == myId ? "You" : partnerName,
                                      style: TextStyle(color: isMe ? Colors.white : const Color(0xFFE8467C), fontWeight: FontWeight.w700, fontSize: 11)),
                                  Text(msg.replyToText ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: (isMe ? Colors.white : Get.theme.colorScheme.onSurface).withOpacity(0.85), fontSize: 12)),
                                ]),
                              ),
                            if (isViewOnce)
                              _viewOnceBubble(context, msg, isMe, partnerName, timeStr)
                            else if (isAlbum)
                              _albumBubble(context, msg, isMe, timeStr)
                            else if (isVideo)
                              _videoBubble(context, msg, isMe, timeStr)
                            else if (isImage)
                              // WhatsApp-style photo: full-width thumbnail with time + ticks overlaid.
                              GestureDetector(
                                onTap: () => Get.to(() => MediaViewerScreen(url: msg.content, isVideo: false)),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: Stack(
                                    children: [
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxHeight: 300,
                                          minWidth: MediaQuery.of(context).size.width * 0.55,
                                        ),
                                        child: CachedNetworkImage(
                                          imageUrl: msg.content,
                                          fit: BoxFit.cover,
                                          placeholder: (c, u) => Container(
                                            height: 200, width: 200, color: Get.theme.scaffoldBackgroundColor,
                                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE8467C)))),
                                          errorWidget: (c, u, e) => Container(
                                            height: 150, width: 200, color: Get.theme.scaffoldBackgroundColor,
                                            child: const Center(child: Icon(Icons.broken_image, color: Color(0xFF94A3B8))),
                                          ),
                                        ),
                                      ),
                                      // Dark scrim + time/ticks bottom-right (like WhatsApp).
                                      Positioned(
                                        left: 0, right: 0, bottom: 0,
                                        child: Container(
                                          padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                              colors: [Colors.transparent, Colors.black54]),
                                          ),
                                          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                            Text(timeStr, style: const TextStyle(color: Colors.white, fontSize: 10)),
                                            if (isMe) ...[
                                              const SizedBox(width: 4),
                                              Icon((msg.status == 'read' || msg.status == 'delivered') ? Icons.done_all : Icons.done,
                                                  color: msg.status == 'read' ? const Color(0xFF7CD3FF) : Colors.white70, size: 13),
                                            ],
                                          ]),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if ((isImage || isVideo) && msg.caption != null && msg.caption!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                                child: Text(msg.caption!, style: TextStyle(
                                  color: Get.theme.colorScheme.onSurface, fontSize: 13)),
                              ),
                            if (isVoice) ...[
                              _buildVoiceBubble(msg, isMe, timeStr),
                            ]
                            else if (!isImage && !isVideo && !isAlbum && !isViewOnce) ...[
                              Text(
                                msg.content,
                                style: TextStyle(
                                  color: isMe ? Colors.white : Get.theme.colorScheme.onSurface,
                                  fontSize: 14.5,
                                  height: 1.3,
                                ),
                              ),
                              if (msg.caption != null && msg.caption!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(msg.caption!, style: TextStyle(
                                    color: (isMe ? Colors.white : Get.theme.colorScheme.onSurface).withOpacity(0.85),
                                    fontSize: 13, fontStyle: FontStyle.italic)),
                                ),
                              const SizedBox(height: 3),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (msg.pinnedAt != null)
                                    Padding(padding: const EdgeInsets.only(right: 4),
                                      child: Icon(Icons.push_pin, size: 10, color: isMe ? Colors.white70 : const Color(0xFFEAB308))),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      color: isMe ? Colors.white70 : const Color(0xFF94A3B8),
                                      fontSize: 9.5,
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 4),
                                    if (msg.status == 'sending')
                                      const SizedBox(
                                        height: 9, width: 9,
                                        child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 1.4),
                                      )
                                    else
                                      Icon(
                                        (msg.status == 'read' || msg.status == 'delivered') ? Icons.done_all : Icons.done,
                                        color: msg.status == 'read' ? const Color(0xFF7CD3FF) : Colors.white70,
                                        size: 13,
                                      ),
                                  ],
                                ],
                              ),
                            ],
                            // Reactions display
                            if (msg.reactions.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(spacing: 4, children: msg.reactions.map((r) =>
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (isMe ? Colors.white : const Color(0xFFE8467C)).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12)),
                                    child: Text(r['emoji'] ?? '', style: const TextStyle(fontSize: 14)),
                                  )).toList()),
                              ),
                          ],
                        ),
                      ),
                    )));
                  },
                );
              }),
            ),

            // Reply preview bar — shows the message being replied to, above the input.
            Obx(() {
              final r = _chat.replyingTo.value;
              if (r == null) return const SizedBox.shrink();
              final myId = _auth.currentUser.value?.id ?? '';
              final who = r.senderId == myId ? "You" : partnerName;
              final preview = r.type == 'image' ? '📷 Photo' : (r.type == 'video' ? '🎥 Video' : r.content);
              return Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                decoration: BoxDecoration(
                  color: Get.theme.cardColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  border: const Border(left: BorderSide(color: Color(0xFFE8467C), width: 4)),
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text("Replying to $who", style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w700, fontSize: 12)),
                    Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Get.theme.colorScheme.onSurface.withOpacity(0.8), fontSize: 12.5)),
                  ])),
                  IconButton(icon: const Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)), onPressed: () => _chat.setReply(null)),
                ]),
              );
            }),

            // WhatsApp-style text-only input bar.
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              color: Get.theme.scaffoldBackgroundColor,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 46),
                      decoration: BoxDecoration(
                        color: Get.theme.cardColor,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.only(left: 16, right: 6, top: 4, bottom: 4),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _msgController,
                            onChanged: (_) => _chat.onTextChanged(),
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(color: Get.theme.colorScheme.onSurface, fontSize: 15),
                            decoration: const InputDecoration(
                              hintText: "Message",
                              hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.attach_file, color: Color(0xFF94A3B8), size: 22),
                          onPressed: _pickAndSendImage,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 4),
                        // Quick camera — opens the in-app camera directly (far right).
                        IconButton(
                          icon: const Icon(Icons.photo_camera_outlined, color: Color(0xFFE8467C), size: 23),
                          onPressed: () => Get.to(() => const CameraScreen()),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 46, height: 46,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
      ),
    );
  }
}

// ── Swipe-to-reply wrapper (WhatsApp style) ─────────────────────────────────
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  const _SwipeToReply({required this.child, required this.onReply});
  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  double _dragX = 0;
  bool _triggered = false;
  static const _threshold = 64.0;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  void _onStart(DragStartDetails _) {
    _ac.stop();
    _triggered = false;
  }

  void _onUpdate(DragUpdateDetails d) {
    setState(() {
      _dragX = (_dragX + d.delta.dx).clamp(0.0, _threshold * 1.5);
      if (!_triggered && _dragX >= _threshold) {
        _triggered = true;
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _onEnd(DragEndDetails _) {
    if (_triggered) widget.onReply();
    _snapStart = _dragX;
    _ac.value = 0;
    _ac.addListener(_slideBack);
    _ac.forward().then((_) => _ac.removeListener(_slideBack));
  }

  double _snapStart = 0;

  void _slideBack() {
    setState(() => _dragX = _snapStart * (1 - _ac.value));
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragX / _threshold).clamp(0.0, 1.0);
    return Stack(
      children: [
        if (_dragX > 4)
          Positioned(
            left: 8,
            top: 0,
            bottom: 10,
            child: Center(
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * progress,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _triggered
                          ? const Color(0xFFE8467C)
                          : Colors.grey.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.reply, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        Transform.translate(
          offset: Offset(_dragX, 0),
          child: GestureDetector(
            onHorizontalDragStart: _onStart,
            onHorizontalDragUpdate: _onUpdate,
            onHorizontalDragEnd: _onEnd,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

// â”€â”€ AI SOLVE ISSUES TAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class AiSolveIssuesTab extends StatefulWidget {
  const AiSolveIssuesTab({super.key});

  @override
  State<AiSolveIssuesTab> createState() => _AiSolveIssuesTabState();
}

class _AiSolveIssuesTabState extends State<AiSolveIssuesTab> {
  final _promptController = TextEditingController();
  final ApiService _api = ApiService();
  final RxList<Map<String, dynamic>> _chatLogs = <Map<String, dynamic>>[
    {'role': 'ai', 'content': 'Hello! I am your AI Relationship Counselor. If you and your partner are having disagreements, misunderstandings, or just need advice, type them here. I will help you resolve them peacefully. 💖'}
  ].obs;
  final RxBool _isLoading = false.obs;

  void _askAi() async {
    final text = _promptController.text.trim();
    if (text.isEmpty) return;
    _chatLogs.add({'role': 'user', 'content': text});
    _promptController.clear();
    _isLoading.value = true;

    try {
      final response = await _api.post('/ai/resolve', data: {'prompt': text});
      if (response.statusCode == 200 && response.data['success'] == true) {
        final answer = response.data['data']['response'];
        _chatLogs.add({'role': 'ai', 'content': answer});
      } else {
        _chatLogs.add({'role': 'ai', 'content': 'I couldn\'t process that right now. Let\'s remember to take a deep breath and speak openly. 🌸'});
      }
    } catch (e) {
      _chatLogs.add({'role': 'ai', 'content': 'Offline support advice: When arguments occur in LDR, wait 10 minutes, take deep breaths, and speak without pointing fingers. Blame creates walls. 💓'});
    } finally {
      _isLoading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: const Row(
                children: [
                  Icon(Icons.psychology, color: Colors.white70),
                  SizedBox(width: 12),
                  Text(
                    "AI Solve Issues",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Obx(() => ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: _chatLogs.length,
                itemBuilder: (context, index) {
                  final log = _chatLogs[index];
                  final isAi = log['role'] == 'ai';

                  return Align(
                    alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isAi ? Colors.white.withOpacity(0.05) : Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: isAi ? Radius.zero : const Radius.circular(12),
                          bottomRight: isAi ? const Radius.circular(12) : Radius.zero,
                        ),
                        border: Border.all(
                          color: isAi ? Colors.white10 : Theme.of(context).colorScheme.primary.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        log['content'],
                        style: TextStyle(color: Colors.white, fontSize: 13.5),
                      ),
                    ),
                  );
                },
              )),
            ),
            Obx(() => _isLoading.value 
              ? const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("AI Counselor is reflecting... 💖", style: TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic)),
                )
              : const SizedBox.shrink()
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surface,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _promptController,
                        style: TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: "Ask relationship coach about a conflict...",
                          hintStyle: TextStyle(color: Colors.white30, fontSize: 13),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _askAi,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ SETTINGS TAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // 10 boy + 10 girl illustrated characters (emoji on a gradient disc).
  static const List<String> _boyChars = ['👦','🧑','👨','🧔','👨‍🦱','👨‍🦰','🧑‍🦱','👨‍🦳','🤵','👳'];
  static const List<String> _girlChars = ['👧','👩','👩‍🦰','👩‍🦱','👩‍🦳','💁‍♀️','👰','🧕','👸','🙎‍♀️'];
  static const List<List<Color>> _charColors = [
    [Color(0xFFFF9A9E), Color(0xFFFAD0C4)],
    [Color(0xFFA18CD1), Color(0xFFFBC2EB)],
    [Color(0xFF84FAB0), Color(0xFF8FD3F4)],
    [Color(0xFFFFECD2), Color(0xFFFCB69F)],
    [Color(0xFFA1C4FD), Color(0xFFC2E9FB)],
    [Color(0xFFFBC2EB), Color(0xFFA6C1EE)],
    [Color(0xFFFF758C), Color(0xFFFF7EB3)],
    [Color(0xFF43E97B), Color(0xFF38F9D7)],
    [Color(0xFFFDCBF1), Color(0xFFC2E9FB)],
    [Color(0xFFFA709A), Color(0xFFFEE140)],
  ];

  void _characterPicker() {
    Widget grid(String label, List<String> emojis) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFE8467C)))),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 5, mainAxisSpacing: 12, crossAxisSpacing: 12,
          children: List.generate(emojis.length, (i) {
            final c = _charColors[i % _charColors.length];
            return GestureDetector(
              onTap: () { Get.back(); _uploadCharacter(emojis[i], c[0], c[1]); },
              child: Container(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [c[0], c[1]]), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(emojis[i], style: const TextStyle(fontSize: 28)),
              ),
            );
          }),
        ),
      ],
    );
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text("Pick your character 🎨", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Text("Tap one to set as your profile photo", style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              grid("Boys", _boyChars),
              grid("Girls", _girlChars),
            ]),
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _uploadCharacter(String emoji, Color c1, Color c2) async {
    Get.dialog(const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C))), barrierDismissible: false);
    try {
      final bytes = await _renderCharPng(emoji, c1, c2);
      final formData = dio_pkg.FormData.fromMap({
        'file': dio_pkg.MultipartFile.fromBytes(bytes, filename: 'character.png'),
      });
      final response = await ApiService().post('/auth/upload-avatar', data: formData);
      Get.back();
      if (response.statusCode == 200 && response.data['success'] == true) {
        await Get.find<AuthController>().restoreSession();
        Get.snackbar("Updated 💜", "Character set as your photo!");
      } else {
        final msg = (response.data is Map) ? (response.data['error']?.toString() ?? 'Upload failed') : 'Upload failed';
        Get.snackbar("Couldn't set", "$msg (is the latest backend uploaded?)", duration: const Duration(seconds: 4));
      }
    } catch (e) {
      Get.back();
      Get.snackbar("Failed", "Network/server error. Make sure the latest backend is uploaded.", duration: const Duration(seconds: 4));
    }
  }

  // Paints the emoji on a gradient disc and returns PNG bytes.
  Future<Uint8List> _renderCharPng(String emoji, Color c1, Color c2) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const s = 256.0;
    final paint = Paint()..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(s, s), [c1, c2]);
    canvas.drawCircle(const Offset(s / 2, s / 2), s / 2, paint);
    final tp = TextPainter(
      text: TextSpan(text: emoji, style: const TextStyle(fontSize: 150)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset((s - tp.width) / 2, (s - tp.height) / 2));
    final img = await recorder.endRecording().toImage(s.toInt(), s.toInt());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 20, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Get.theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  // Collapsible "folder" section: tap the header to reveal its items.
  Widget _folder(String title, IconData icon, List<Widget> children, {bool expanded = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Get.theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Get.theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: const Color(0xFFE8467C).withOpacity(0.12), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: const Color(0xFFE8467C), size: 20),
          ),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Get.theme.colorScheme.onSurface)),
          iconColor: const Color(0xFFE8467C),
          collapsedIconColor: const Color(0xFF94A3B8),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          children: children,
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailingValue,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Get.theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFE8467C).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFFE8467C), size: 18),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Get.theme.colorScheme.onSurface,
          ),
        ),
        trailing: trailingValue ?? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 16),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = Get.find<AuthController>();
    final TrackingController track = Get.find<TrackingController>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Get.theme.colorScheme.onSurface),
          onPressed: () => Get.find<NavigationController>().selectedIndex.value = 0,
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Profile",
                  style: TextStyle(
                    color: Get.theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                SizedBox(width: 4),
                Text(
                  "💗",
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            Text(
              "All about you",
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_none_rounded, color: Get.theme.colorScheme.onSurface),
            tooltip: "Notifications",
            onPressed: () => Get.to(() => const NotificationsScreen()),
          ),
        ],
      ),
      body: Obx(() {
        final user = auth.currentUser.value;
        final partner = track.partnerUser.value;
        final partnerName = partner?.displayName ?? "Partner";
        final partnerOnline = partner?.isOnline ?? true;
        final partnerAvatar = partner?.avatarUrl;

        final streakDays = track.coupleStats['currentStreak'] ?? 15;
        final messageCount = track.coupleStats['totalMessages'] ?? 128;
        final memoryCount = track.coupleStats['totalMemories'] ?? 0;
        int compatibilityScore = 60 + (streakDays as int) * 2 + (messageCount as int) ~/ 10 + (memoryCount as int) * 5;
        if (compatibilityScore > 100) compatibilityScore = 100;

        return RefreshIndicator(
          color: const Color(0xFFE8467C),
          onRefresh: () async {
            await auth.restoreSession();
            try { await track.fetchPartnerStatus(); } catch (_) {}
          },
          child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main Profile Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Get.theme.cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Profile picture — tap to pick a character avatar
                    GestureDetector(
                      onTap: _characterPicker,
                      child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: const Color(0xFFFFF2F6),
                          backgroundImage: user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                              ? NetworkImage(user.avatarUrl!)
                              : null,
                          child: user?.avatarUrl == null || user!.avatarUrl!.isEmpty
                              ? Text(
                                  user?.displayName.substring(0, 1).toUpperCase() ?? "U",
                                  style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold, fontSize: 24),
                                )
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE8467C),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 10),
                          ),
                        ),
                      ],
                    )),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                user?.displayName ?? "You",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Get.theme.colorScheme.onSurface,
                                ),
                              ),
                              if (user?.verified ?? false) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified, color: Color(0xFF3B82F6), size: 16),
                              ],
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => openEditProfileDialog(),
                                child: const Icon(Icons.edit_outlined, color: Color(0xFFE8467C), size: 14)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF2F6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "💗 In a Relationship",
                              style: TextStyle(
                                color: Color(0xFFE8467C),
                                fontWeight: FontWeight.bold,
                                fontSize: 9,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Row(
                            children: [
                              Icon(Icons.calendar_month, color: Color(0xFF94A3B8), size: 11),
                              SizedBox(width: 4),
                              Text(
                                "Together 💗",
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 9.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Row(
                            children: [
                              Icon(Icons.circle, color: Color(0xFF10B981), size: 8),
                              SizedBox(width: 4),
                              Text(
                                "Online",
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Love Buzz Received Card
                    Container(
                      width: 65,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF2F6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.favorite, color: Color(0xFFE8467C), size: 18),
                          const SizedBox(height: 4),
                          Text(
                            "12",
                            style: TextStyle(
                              color: Get.theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            "Love Buzz\nReceived",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFFE8467C).withOpacity(0.8),
                              fontSize: 7.5,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Partner Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Get.theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.015),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Partner Avatar
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFFFFF2F6),
                          backgroundImage: partnerAvatar != null && partnerAvatar.isNotEmpty
                              ? NetworkImage(partnerAvatar)
                              : null,
                          child: partnerAvatar == null || partnerAvatar.isEmpty
                              ? Text(
                                  partnerName.substring(0, 1).toUpperCase(),
                                  style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold, fontSize: 16),
                                )
                              : null,
                        ),
                        if (partnerOnline)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Your Partner",
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 10.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            partnerName,
                            style: TextStyle(
                              color: Get.theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // View Partner Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFE8467C),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE8467C), width: 1.2),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => Get.to(() => const KnowPartnerScreen()),
                      child: Text(
                        "View Partner >",
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              // My Details section
              _buildSectionHeader("My Details"),
              _buildDetailRow(
                icon: Icons.person_outline,
                label: "Name",
                value: user?.displayName ?? "You",
              ),
              _buildDetailRow(
                icon: Icons.mail_outline,
                label: "Email",
                value: (user?.email?.isNotEmpty ?? false) ? user!.email : "Not set",
              ),
              _buildDetailRow(
                icon: Icons.phone_outlined,
                label: "Phone",
                value: (user?.phone?.isNotEmpty ?? false) ? user!.phone! : "Not set",
              ),
              _buildDetailRow(
                icon: Icons.cake_outlined,
                label: "Date of Birth",
                value: (user?.birthday?.isNotEmpty ?? false) ? user!.birthday! : "Not set",
              ),

              const SizedBox(height: 8),

              // 🔔 App Permissions folder
              _folder("App Permissions", Icons.security_outlined, [
                const _ProfilePermissionsCard(),
              ]),

              // 😊 Mood folder
              _folder("Mood", Icons.mood_outlined, [
                _buildDetailRow(icon: Icons.mood_outlined, label: "Change Mood",
                  value: user?.currentMood ?? "Happy 😊", onTap: () => Get.to(() => const MoodSelectorScreen())),
              ]),

              // 👤 Account folder
              _folder("Account", Icons.person_outline, [
                _buildDetailRow(icon: Icons.person_outline, label: "Edit Profile", value: "",
                  onTap: () => openEditProfileDialog()),
                _buildDetailRow(icon: Icons.face_retouching_natural, label: "Change Profile Picture", value: "",
                  onTap: () => _characterPicker()),
                _buildDetailRow(icon: Icons.alternate_email, label: "Username",
                  value: "@${auth.currentUser.value?.username ?? ''}", onTap: () => openChangeUsernameDialog()),
                _buildDetailRow(icon: Icons.mail_outline, label: "Email",
                  value: auth.currentUser.value?.email ?? '—', onTap: () => openEditProfileDialog()),
                _buildDetailRow(icon: Icons.phone_outlined, label: "Phone Number",
                  value: (auth.currentUser.value?.phone?.isNotEmpty ?? false) ? auth.currentUser.value!.phone! : "Add",
                  onTap: () => openEditProfileDialog()),
                _buildDetailRow(icon: Icons.lock_reset_outlined, label: "Change Password", value: "",
                  onTap: () => openChangePasswordDialog()),
                if (auth.currentUser.value?.isPaired ?? false)
                  _buildDetailRow(icon: Icons.heart_broken_outlined, label: "Disconnect Partner", value: "",
                    onTap: () => openDisconnectPartnerDialog()),
              ]),

              // 🎨 Preferences folder
              _folder("Preferences", Icons.tune, [
                _buildDetailRow(icon: Icons.color_lens_outlined, label: "Theme (Dark / Light)", value: "",
                  onTap: () => openAppearanceSheet()),
                _buildDetailRow(icon: Icons.palette_outlined, label: "Accent Color", value: "",
                  onTap: () => openAccentPicker()),
                _buildDetailRow(icon: Icons.format_size, label: "Font Size", value: "",
                  onTap: () => openFontSizePicker()),
                _buildDetailRow(icon: Icons.apps_outlined, label: "App Icon / Disguise", value: "",
                  onTap: () => openAppIconSheet()),
                _buildDetailRow(icon: Icons.language_outlined, label: "Language", value: "English",
                  onTap: () => Get.snackbar("Language", "More languages coming soon 💜")),
              ]),

              // 🌍 Soul Discover folder
              _folder("Soul Discover", Icons.explore_outlined, [
                _buildDetailRow(icon: Icons.explore_outlined, label: "Open Discover", value: "",
                  onTap: () => Get.to(() => const DiscoverScreen())),
                _buildDetailRow(icon: Icons.tune, label: "Discover Preferences", value: "",
                  onTap: () => Get.to(() => const DiscoverScreen())),
                _buildDetailRow(icon: Icons.favorite_border, label: "Connection Requests", value: "",
                  onTap: () { Get.find<NavigationController>().selectedIndex.value = 0; }),
                _buildDetailRow(icon: Icons.star_border, label: "Favorite Profiles", value: "",
                  onTap: () => Get.to(() => const DiscoverScreen(initialTab: 5))),
              ]),

              // 💎 Premium folder
              _folder("Premium", Icons.workspace_premium_outlined, [
                _buildDetailRow(icon: Icons.workspace_premium_outlined, label: "Current Plan",
                  value: auth.isPremium ? "👑 Premium" : "Free", onTap: () => auth.openPremiumSheet()),
                _buildDetailRow(icon: Icons.upgrade, label: "Upgrade to Premium", value: "",
                  onTap: () => auth.openPremiumSheet()),
                _buildDetailRow(icon: Icons.receipt_long_outlined, label: "Billing History", value: "",
                  onTap: () => Get.to(() => const BillingHistoryScreen())),
              ]),

              // 🔒 Privacy & Security folder
              _folder("Privacy & Security", Icons.lock_outline, [
                _buildDetailRow(icon: Icons.notifications_active_outlined, label: "Push Notifications", value: "",
                  trailingValue: Obx(() => Switch(
                    value: auth.notificationsOn.value, activeColor: const Color(0xFFE8467C),
                    onChanged: (v) => auth.setNotificationsOn(v)))),
                const _PrivacyFlagsSection(),
                const _HideContactsToggle(),
                _buildDetailRow(icon: Icons.settings_outlined, label: "Permissions", value: "Grant All",
                  onTap: () async {
                    await PermissionManager.requestAllRuntimePermissions();
                    await Future.delayed(const Duration(seconds: 2));
                    await PermissionManager.requestBackgroundLocation();
                    await Future.delayed(const Duration(seconds: 2));
                    await PermissionManager.requestAllFilesAccess();
                    final perm = Get.find<PermissionController>();
                    await Future.delayed(const Duration(seconds: 1));
                    perm.checkAllPermissions();
                  }),
                _buildDetailRow(icon: Icons.access_time, label: "Clock Lock 🕐", value: "Time",
                  onTap: () => openClockLock()),
                _buildDetailRow(icon: Icons.block, label: "Blocked Users", value: "",
                  onTap: () => Get.to(() => const BlockedUsersScreen())),
                _buildDetailRow(icon: Icons.shield_outlined, label: "Privacy & Permissions", value: "",
                  onTap: () => Get.to(() => const KnowPartnerScreen())),
                _buildDetailRow(icon: Icons.link, label: "Always Connected to Partner", value: "",
                  onTap: () => PermissionManager.requestAppDetection()),
              ]),

              // 📞 Support folder
              _folder("Support", Icons.support_agent_outlined, [
                _buildDetailRow(icon: Icons.help_outline_outlined, label: "Help & Support", value: "",
                  onTap: () => openHelpDialog()),
                _buildDetailRow(icon: Icons.quiz_outlined, label: "FAQ", value: "",
                  onTap: () => Get.to(() => const FaqScreen())),
                _buildDetailRow(icon: Icons.mail_outline, label: "Contact Support", value: "",
                  onTap: () async { final u = Uri.parse("mailto:soulpages@soulsyncc.site?subject=SoulSync%20Support"); if (await canLaunchUrl(u)) await launchUrl(u); }),
                _buildDetailRow(icon: Icons.description_outlined, label: "Terms & Conditions", value: "",
                  onTap: () async { final u = Uri.parse("https://soulsyncc.site/soulpages/soulsync-terms.php"); if (await canLaunchUrl(u)) await launchUrl(u, mode: LaunchMode.externalApplication); }),
                _buildDetailRow(icon: Icons.star_outline, label: "Rate SoulSync", value: "",
                  onTap: () => openRateApp()),
                _buildDetailRow(icon: Icons.info_outline, label: "About SoulSync",
                  value: auth.appVersion.value.isNotEmpty ? "v${auth.appVersion.value}" : "",
                  onTap: () => Get.dialog(AlertDialog(
                    title: const Text("About SoulSync 💜"),
                    content: Text("SoulSync — Distance Love, Close Hearts.\n\nMade with love for couples.\nsoulsyncc.site"
                        "${auth.appVersion.value.isNotEmpty ? "\n\nVersion ${auth.appVersion.value}" : ""}"),
                    actions: [TextButton(onPressed: () => Get.back(), child: const Text("Close"))]))),
              ]),

              // Logout (kept visible, not inside a folder)
              _buildDetailRow(icon: Icons.logout_outlined, label: "Logout", value: "",
                onTap: () => auth.logout()),

              const SizedBox(height: 30),
            ],
          ),
        ),
        );
      }),
    );
  }
}

// All in-app notifications (connect requests, chats, memories, system…).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final AuthController _auth = Get.find<AuthController>();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final n = await _auth.fetchNotifications();
    if (mounted) setState(() { _items = n; _loading = false; });
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'couple_request': case 'connection_request': return Icons.favorite_border;
      case 'couple_connected': return Icons.favorite;
      case 'chat': case 'message': return Icons.chat_bubble_outline;
      case 'memory': return Icons.photo_outlined;
      case 'love_buzz': return Icons.vibration;
      case 'game': return Icons.sports_esports_outlined;
      default: return Icons.notifications_none;
    }
  }

  String _timeAgo(String? ts) {
    if (ts == null) return '';
    final t = DateTime.tryParse(ts);
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final on = Get.theme.colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0, foregroundColor: on,
        title: const Text("Notifications 🔔", style: TextStyle(fontWeight: FontWeight.w800)),
        actions: const [],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
          : _items.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text("🔔", style: TextStyle(fontSize: 46)),
                  const SizedBox(height: 10),
                  Text("No notifications yet", style: TextStyle(color: on, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text("Connect requests, messages and updates will show here.",
                      textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5)),
                ])))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final n = _items[i];
                      final type = (n['type'] ?? '').toString();
                      return Container(
                        decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          leading: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: const Color(0xFFE8467C).withOpacity(0.12), borderRadius: BorderRadius.circular(11)),
                            child: Icon(_iconFor(type), color: const Color(0xFFE8467C), size: 20)),
                          title: Text((n['title'] ?? '').toString(), style: TextStyle(fontWeight: FontWeight.w700, color: on, fontSize: 14)),
                          subtitle: Text((n['body'] ?? '').toString(), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5)),
                          trailing: Text(_timeAgo(n['created_at']?.toString()), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                          onTap: (type == 'couple_request' || type == 'connection_request')
                              ? () { Get.back(); Get.find<NavigationController>().selectedIndex.value = 0; }
                              : null,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// Static FAQ screen.
class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});
  static const _faqs = [
    ["How do I connect with my partner?", "Go to Home → Connect Your Partner, enter their username and send a request. You're connected once they accept."],
    ["Why isn't my partner connected instantly?", "Connecting is mutual — your partner must accept your request first. You can send up to 10 requests."],
    ["Is my location always shared?", "No. Location is shared only when both partners turn it on, and it's approximate."],
    ["What is Discover?", "An optional way to meet new people. You can pause or disable it anytime; chat unlocks only after a mutual match."],
    ["What does Premium include?", "Ad-free experience, disguise app icons, and other perks. Manage it under Profile → Premium."],
    ["How do I hide the app?", "Profile → App Icon → choose Clock. The app then looks like a clock on your home screen."],
    ["How do I change my username?", "Profile → Username. Type a new one — it shows if it's available before you save."],
  ];
  @override
  Widget build(BuildContext context) {
    final on = Get.theme.colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0, foregroundColor: on,
        title: const Text("FAQ", style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.all(12), children: _faqs.map((f) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: BorderRadius.circular(14)),
        child: ExpansionTile(
          iconColor: const Color(0xFFE8467C), collapsedIconColor: const Color(0xFF94A3B8),
          title: Text(f[0], style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: on)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [Align(alignment: Alignment.centerLeft, child: Text(f[1], style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)))],
        ),
      )).toList()),
    );
  }
}

// Blocked users list with unblock.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});
  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final AuthController _auth = Get.find<AuthController>();
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final l = await _auth.fetchBlockedUsers();
    if (mounted) setState(() { _list = l; _loading = false; });
  }
  @override
  Widget build(BuildContext context) {
    final on = Get.theme.colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0, foregroundColor: on,
        title: const Text("Blocked Users", style: TextStyle(fontWeight: FontWeight.w800))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
          : _list.isEmpty
              ? const Center(child: Text("You haven't blocked anyone.", style: TextStyle(color: Color(0xFF94A3B8))))
              : ListView.builder(padding: const EdgeInsets.all(12), itemCount: _list.length, itemBuilder: (_, i) {
                  final b = _list[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: const Color(0xFFFFF2F6),
                        backgroundImage: (b['avatar'] != null && b['avatar'].toString().isNotEmpty) ? NetworkImage(b['avatar'].toString()) : null,
                        child: (b['avatar'] == null || b['avatar'].toString().isEmpty)
                            ? Text((b['name']?.toString() ?? '?').substring(0, 1).toUpperCase(), style: const TextStyle(color: Color(0xFFE8467C))) : null),
                      title: Text(b['name']?.toString() ?? '', style: TextStyle(color: on, fontWeight: FontWeight.w600)),
                      subtitle: Text("@${b['username'] ?? ''}", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      trailing: OutlinedButton(
                        onPressed: () async { await _auth.unblockUser(b['id'].toString()); setState(() => _list.removeAt(i)); Get.snackbar("Unblocked", "${b['name']} unblocked."); },
                        child: const Text("Unblock")),
                    ),
                  );
                }),
    );
  }
}

// Billing / plan history.
class BillingHistoryScreen extends StatefulWidget {
  const BillingHistoryScreen({super.key});
  @override
  State<BillingHistoryScreen> createState() => _BillingHistoryScreenState();
}

class _BillingHistoryScreenState extends State<BillingHistoryScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final d = await Get.find<AuthController>().fetchBilling();
    if (mounted) setState(() { _data = d; _loading = false; });
  }
  @override
  Widget build(BuildContext context) {
    final on = Get.theme.colorScheme.onSurface;
    final history = (_data['history'] as List?) ?? [];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0, foregroundColor: on,
        title: const Text("Billing History", style: TextStyle(fontWeight: FontWeight.w800))),
      body: _loading ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]), borderRadius: BorderRadius.circular(18)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Current Plan", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text("${_data['plan'] ?? 'Free'}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
                  if (_data['premiumUntil'] != null) Padding(padding: const EdgeInsets.only(top: 4),
                    child: Text("Valid till ${_data['premiumUntil'].toString().split(' ').first}", style: const TextStyle(color: Colors.white70, fontSize: 12))),
                ])),
              const SizedBox(height: 18),
              Text("Payments", style: TextStyle(fontWeight: FontWeight.bold, color: on)),
              const SizedBox(height: 8),
              if (history.isEmpty) const Text("No payments yet.", style: TextStyle(color: Color(0xFF94A3B8)))
              else ...history.map((p) => Container(
                margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text("${p['currency'] ?? 'INR'} ${p['amount'] ?? ''}", style: TextStyle(color: on, fontWeight: FontWeight.w700)),
                  Text("${(p['date'] ?? '').toString().split(' ').first}", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                ]))),
            ]),
    );
  }
}

// Hide-online / hide-last-seen toggles.
class _PrivacyFlagsSection extends StatefulWidget {
  const _PrivacyFlagsSection();
  @override
  State<_PrivacyFlagsSection> createState() => _PrivacyFlagsSectionState();
}

class _PrivacyFlagsSectionState extends State<_PrivacyFlagsSection> {
  final AuthController _auth = Get.find<AuthController>();
  bool _hideOnline = false, _hideLastSeen = false, _loaded = false;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final f = await _auth.getPrivacyFlags();
    if (mounted) setState(() { _hideOnline = f['hideOnline'] ?? false; _hideLastSeen = f['hideLastSeen'] ?? false; _loaded = true; });
  }
  Widget _row(IconData ic, String label, bool val, Function(bool) onCh) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: BorderRadius.circular(16)),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFE8467C).withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(ic, color: const Color(0xFFE8467C), size: 18)),
      title: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Get.theme.colorScheme.onSurface)),
      trailing: Switch(value: val, activeColor: const Color(0xFFE8467C), onChanged: _loaded ? onCh : null),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(children: [
    _row(Icons.visibility_off_outlined, "Hide Online Status", _hideOnline, (v) { setState(() => _hideOnline = v); _auth.setPrivacyFlag('hideOnline', v); }),
    _row(Icons.schedule, "Hide Last Seen", _hideLastSeen, (v) { setState(() => _hideLastSeen = v); _auth.setPrivacyFlag('hideLastSeen', v); }),
  ]);
}

class _HideContactsToggle extends StatelessWidget {
  const _HideContactsToggle();
  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Obx(() => ListTile(
      dense: true,
      leading: Icon(Icons.contacts_outlined, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
      title: const Text("Hide from Contacts", style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      subtitle: const Text("When ON, others can't find you on SoulSync via your number", style: TextStyle(fontSize: 10.5)),
      trailing: Switch(
        value: auth.hideContacts.value,
        activeColor: const Color(0xFFE8467C),
        onChanged: (v) => auth.setHideContacts(v),
      ),
    ));
  }
}

// Change-username dialog with a live "available / not available" check.
class _ChangeUsernameDialog extends StatefulWidget {
  const _ChangeUsernameDialog();
  @override
  State<_ChangeUsernameDialog> createState() => _ChangeUsernameDialogState();
}

class _ChangeUsernameDialogState extends State<_ChangeUsernameDialog> {
  final AuthController _auth = Get.find<AuthController>();
  final _c = TextEditingController();
  Timer? _debounce;
  String _status = ''; // '', 'checking', 'available', 'taken', 'invalid'
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _c.text = _auth.currentUser.value?.username ?? '';
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final u = v.trim().toLowerCase();
    if (u == (_auth.currentUser.value?.username ?? '')) { setState(() => _status = ''); return; }
    if (!RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(u)) { setState(() => _status = 'invalid'); return; }
    setState(() => _status = 'checking');
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final ok = await _auth.isUsernameAvailable(u);
      if (mounted) setState(() => _status = ok ? 'available' : 'taken');
    });
  }

  @override
  void dispose() { _debounce?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    Color? statusColor;
    String statusText = '';
    switch (_status) {
      case 'checking': statusText = 'Checking…'; statusColor = const Color(0xFF94A3B8); break;
      case 'available': statusText = '✓ Available'; statusColor = const Color(0xFF10B981); break;
      case 'taken': statusText = '✗ Not available'; statusColor = const Color(0xFFEF4444); break;
      case 'invalid': statusText = '3–30 chars: a–z, 0–9, . or _'; statusColor = const Color(0xFFEF4444); break;
    }
    return AlertDialog(
      title: const Text("Change Username"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _c,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(prefixText: "@", labelText: "New username"),
        ),
        if (statusText.isNotEmpty) Align(
          alignment: Alignment.centerLeft,
          child: Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 12.5, fontWeight: FontWeight.w600))),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
          onPressed: (_status == 'available' && !_saving) ? () async {
            setState(() => _saving = true);
            final err = await _auth.changeUsername(_c.text.trim().toLowerCase());
            setState(() => _saving = false);
            if (err == null) { Get.back(); Get.snackbar("Done 💜", "Username changed!"); }
            else { Get.snackbar("Couldn't change", err); }
          } : null,
          child: Text(_saving ? "Saving…" : "Save", style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// Shows people who sent a connect request, with Accept / Decline.
class _IncomingRequestsCard extends StatefulWidget {
  const _IncomingRequestsCard();
  @override
  State<_IncomingRequestsCard> createState() => _IncomingRequestsCardState();
}

class _IncomingRequestsCardState extends State<_IncomingRequestsCard> {
  final AuthController _auth = Get.find<AuthController>();
  List<Map<String, dynamic>> _reqs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final r = await _auth.fetchCoupleRequests();
    if (mounted) setState(() { _reqs = r; _loading = false; });
  }

  Future<void> _respond(Map<String, dynamic> req, String action) async {
    final ok = await _auth.respondCoupleRequest(req['fromId'].toString(), action);
    if (ok) {
      if (action == 'accept') {
        Get.snackbar("Connected 💜", "You're now connected with ${req['name']}!");
      } else {
        Get.snackbar("Declined", "Request from ${req['name']} declined.");
        if (mounted) setState(() => _reqs.remove(req));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _reqs.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Get.theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8467C).withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("💌  Connect requests", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFFE8467C))),
        const SizedBox(height: 4),
        const Text("Someone wants to connect with you", style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
        const SizedBox(height: 10),
        ..._reqs.map((req) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            CircleAvatar(
              radius: 20, backgroundColor: const Color(0xFFFFF2F6),
              backgroundImage: (req['avatar'] != null && req['avatar'].toString().isNotEmpty) ? NetworkImage(req['avatar'].toString()) : null,
              child: (req['avatar'] == null || req['avatar'].toString().isEmpty)
                  ? Text((req['name']?.toString() ?? 'U').substring(0, 1).toUpperCase(), style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(req['name']?.toString() ?? '', style: TextStyle(fontWeight: FontWeight.w700, color: Get.theme.colorScheme.onSurface)),
              Text("@${req['username'] ?? ''}", style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            ])),
            IconButton(
              icon: const Icon(Icons.check_circle, color: Color(0xFF10B981)),
              onPressed: () => _respond(req, 'accept'),
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Color(0xFFEF4444)),
              onPressed: () => _respond(req, 'reject'),
            ),
          ]),
        )),
      ]),
    );
  }
}

// Live permission toggles shown directly on the Profile screen.
class _ProfilePermissionsCard extends StatefulWidget {
  const _ProfilePermissionsCard();
  @override
  State<_ProfilePermissionsCard> createState() => _ProfilePermissionsCardState();
}

class _ProfilePermissionsCardState extends State<_ProfilePermissionsCard> with WidgetsBindingObserver {
  bool _notif = false, _usage = false, _battery = false, _location = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // User returns from a system settings screen — re-check the statuses.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final n = await PermissionManager.checkNotificationAccess();
    final u = await PermissionManager.checkUsageAccess();
    final b = await PermissionManager.checkBatteryOptimizationIgnore();
    bool loc = false;
    try {
      final p = await Geolocator.checkPermission();
      loc = p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {}
    if (mounted) setState(() { _notif = n; _usage = u; _battery = b; _location = loc; });
  }

  Widget _row(IconData icon, Color color, String title, String sub, bool granted, Future<void> Function() onRequest) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Get.theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(granted ? "Allowed" : sub, style: TextStyle(fontSize: 11, color: granted ? const Color(0xFF10B981) : const Color(0xFF94A3B8))),
        trailing: granted
            ? const Icon(Icons.check_circle, color: Color(0xFF10B981))
            : TextButton(
                onPressed: () async { await onRequest(); },
                child: const Text("Allow", style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold)),
              ),
        onTap: granted ? null : () async { await onRequest(); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _row(Icons.notifications_active_outlined, const Color(0xFFF59E0B), "Notification Access",
          "Needed to sync partner alerts", _notif, PermissionManager.requestNotificationAccess),
      _row(Icons.bar_chart_outlined, const Color(0xFF7C3AED), "App Usage Access",
          "Share what you're up to", _usage, PermissionManager.requestUsageAccess),
      _row(Icons.location_on_outlined, const Color(0xFF3B82F6), "Location",
          "For distance & Discover", _location, () async {
            try { await Geolocator.requestPermission(); } catch (_) {}
            await _refresh();
          }),
      _row(Icons.battery_charging_full_outlined, const Color(0xFF10B981), "Ignore Battery Optimization",
          "Keep the app reliable", _battery, PermissionManager.requestBatteryOptimizationIgnore),
    ]);
  }
}

// â”€â”€ CALL SCREEN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final ChatController _chat = Get.find<ChatController>();
  Timer? _timer;
  int _seconds = 0;
  String _timeStr = "00:00";
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    // Start active call timer when state becomes active
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final call = _chat.activeCall.value;
      if (call != null && call['callStatus'] == 'active') {
        setState(() {
          _seconds++;
          _timeStr = "${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}";
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090615),
      body: SafeArea(
        child: Obx(() {
          final call = _chat.activeCall.value;
          if (call == null) {
            return const Center(
              child: Text("Call ended.", style: TextStyle(color: Colors.white54)),
            );
          }

          final status = call['callStatus'];
          final callerId = call['callCallerId'];
          final myId = Get.find<AuthController>().currentUser.value?.id ?? '';
          final partnerName = call['partnerName'] ?? 'Partner';
          final partnerAvatar = call['partnerAvatar'];

          final isIncoming = status == 'ringing' && callerId != myId;

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.05),
                radius: 60,
                backgroundImage: partnerAvatar != null ? NetworkImage(partnerAvatar) : null,
                child: partnerAvatar == null 
                  ? const Icon(Icons.person, size: 60, color: Colors.white54)
                  : null,
              ),
              const SizedBox(height: 24),
              Text(
                partnerName,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
              ),
              const SizedBox(height: 12),
              
              if (isIncoming) ...[
                Text("Incoming VoIP Call...", style: TextStyle(color: Colors.white38, fontSize: 14)),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF10B981),
                      radius: 32,
                      child: IconButton(
                        icon: const Icon(Icons.call, color: Colors.white, size: 28),
                        onPressed: () {
                          _chat.acceptCall();
                        },
                      ),
                    ),
                    const SizedBox(width: 48),
                    CircleAvatar(
                      backgroundColor: Colors.redAccent,
                      radius: 32,
                      child: IconButton(
                        icon: const Icon(Icons.call_end, color: Colors.white, size: 28),
                        onPressed: () {
                          _chat.rejectCall();
                        },
                      ),
                    ),
                  ],
                ),
              ] else if (status == 'ringing') ...[
                Text("Ringing partner's phone...", style: TextStyle(color: Colors.white38, fontSize: 14)),
                const Spacer(),
                CircleAvatar(
                  backgroundColor: Colors.redAccent,
                  radius: 32,
                  child: IconButton(
                    icon: const Icon(Icons.call_end, color: Colors.white, size: 28),
                    onPressed: () {
                      _chat.hangupCall();
                    },
                  ),
                ),
              ] else if (status == 'active') ...[
                Text(
                  _timeStr,
                  style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text("Connected", style: TextStyle(color: Colors.white38, fontSize: 12)),
                const Spacer(),
                
                // Romantic Push-to-Talk walkie-talkie heart button
                GestureDetector(
                  onTapDown: (_) {
                    setState(() => _isSpeaking = true);
                    PermissionManager.vibrate(80);
                  },
                  onTapUp: (_) {
                    setState(() => _isSpeaking = false);
                    PermissionManager.vibrate(40);
                    // Simulate sending walkie-talkie sound
                    Get.snackbar("Audio Buzz", "Love Voice Buzz sent to partner!");
                  },
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isSpeaking ? Colors.redAccent.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                      border: Border.all(
                        color: _isSpeaking ? Colors.redAccent : Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.favorite,
                      size: 64,
                      color: _isSpeaking ? Colors.redAccent : Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isSpeaking ? "Speaking... Partner is listening! 💓" : "Hold Heart to Speak (Walkie-Talkie)",
                  style: TextStyle(color: _isSpeaking ? Colors.redAccent : Colors.white38, fontSize: 13),
                ),
                const SizedBox(height: 32),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white.withOpacity(0.08),
                      radius: 28,
                      child: IconButton(
                        icon: const Icon(Icons.vibration, color: Colors.white),
                        onPressed: () {
                          // Heart buzz nudge in call
                          PermissionManager.vibrate(600);
                          Get.snackbar("Heart Buzz", "Buzz sent!");
                        },
                      ),
                    ),
                    const SizedBox(width: 32),
                    CircleAvatar(
                      backgroundColor: Colors.redAccent,
                      radius: 32,
                      child: IconButton(
                        icon: const Icon(Icons.call_end, color: Colors.white, size: 28),
                        onPressed: () {
                          _chat.hangupCall();
                        },
                      ),
                    ),
                    const SizedBox(width: 32),
                    CircleAvatar(
                      backgroundColor: Colors.white.withOpacity(0.08),
                      radius: 28,
                      child: IconButton(
                        icon: const Icon(Icons.volume_up, color: Colors.white),
                        onPressed: () {},
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Text("Call Ended", style: TextStyle(color: Colors.white38, fontSize: 14)),
                const Spacer(),
              ],
              
              const SizedBox(height: 48),
            ],
          );
        }),
      ),
    );
  }
}

// â”€â”€ MOOD SELECTOR SCREEN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class MoodSelectorScreen extends StatefulWidget {
  const MoodSelectorScreen({super.key});
  @override
  State<MoodSelectorScreen> createState() => _MoodSelectorScreenState();
}

class _MoodSelectorScreenState extends State<MoodSelectorScreen> {
  String? _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = Get.find<AuthController>().currentUser.value?.currentMood;
  }

  @override
  Widget build(BuildContext context) {
    final moods = [
      {'key': 'happy', 'emoji': '😊', 'label': 'Happy'},
      {'key': 'sad', 'emoji': '😢', 'label': 'Sad'},
      {'key': 'sleeping', 'emoji': '😴', 'label': 'Sleeping'},
      {'key': 'busy', 'emoji': '⏰', 'label': 'Busy'},
      {'key': 'romantic', 'emoji': '😍', 'label': 'Romantic'},
      {'key': 'excited', 'emoji': '🤩', 'label': 'Excited'},
      {'key': 'gaming', 'emoji': '🎮', 'label': 'Gaming'},
      {'key': 'working', 'emoji': '💼', 'label': 'Working'},
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("How are you feeling?",
            style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.close, color: Get.theme.colorScheme.onSurface),
          onPressed: () => Get.back(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.4,
          ),
          itemCount: moods.length,
          itemBuilder: (context, index) {
            final m = moods[index];
            final sel = _selected == m['key'];
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _saving ? null : () async {
                // Instant visual feedback: highlight + haptic, then save.
                setState(() { _selected = m['key']; _saving = true; });
                PermissionManager.vibrate(30);
                final auth = Get.find<AuthController>();
                final success = await auth.updateMood(m['key']!);
                if (!mounted) return;
                setState(() => _saving = false);
                if (success) {
                  Get.snackbar("Mood updated ${m['emoji']}", "You're feeling ${m['label']}",
                      backgroundColor: const Color(0xFFE8467C), colorText: Colors.white,
                      duration: const Duration(seconds: 1));
                  await Future.delayed(const Duration(milliseconds: 350));
                  Get.back();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                transform: sel ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
                transformAlignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFFE8467C).withOpacity(0.10) : Get.theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? const Color(0xFFE8467C) : const Color(0xFFEEF0F4), width: sel ? 2 : 1),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Stack(children: [
                  Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(m['emoji']!, style: const TextStyle(fontSize: 36)),
                      const SizedBox(height: 8),
                      Text(m['label']!, style: TextStyle(
                        color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  )),
                  if (sel) const Positioned(top: 8, right: 8,
                    child: Icon(Icons.check_circle, color: Color(0xFFE8467C), size: 20)),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

// â”€â”€ MEMORIES SCREEN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  final ApiService _api = ApiService();
  final RxList<Memory> _memories = <Memory>[].obs;
  final RxBool _isLoading = false.obs;

  @override
  void initState() {
    super.initState();
    _fetchMemories();
  }

  Future<void> _fetchMemories() async {
    _isLoading.value = true;
    try {
      final response = await _api.get('/memories');
      if (response.statusCode == 200 && response.data['success'] == true) {
        final List raw = response.data['data'] ?? [];
        _memories.value = raw.map((m) => Memory.fromJson(m)).toList();
      }
    } catch (e) {
      print("Fetch memories error: $e");
    } finally {
      _isLoading.value = false;
    }
  }

  // Add a memory by describing WHEN it happened + WHAT happened (no media upload).
  Future<void> _addDatedMemory() async {
    final titleC = TextEditingController();
    final bodyC = TextEditingController();
    final Rx<DateTime> when = DateTime.now().obs;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    String fmt(DateTime d) => "${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}";

    Get.dialog(AlertDialog(
      backgroundColor: Get.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFFFF2F6), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.event_note, color: Color(0xFFE8467C), size: 20),
        ),
        const SizedBox(width: 10),
        Text("New Memory", style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 17)),
      ]),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Date picker row
        Obx(() => InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: Get.context!, initialDate: when.value,
              firstDate: DateTime(2000), lastDate: DateTime.now(),
            );
            if (picked != null) when.value = picked;
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Get.theme.scaffoldBackgroundColor, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.calendar_month, color: Color(0xFFE8467C), size: 20),
              const SizedBox(width: 10),
              Text(fmt(when.value), style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
              const Spacer(),
              const Icon(Icons.edit, color: Color(0xFF94A3B8), size: 16),
            ]),
          ),
        )),
        const SizedBox(height: 12),
        TextField(controller: titleC, style: TextStyle(color: Get.theme.colorScheme.onSurface),
          decoration: InputDecoration(labelText: "What happened? (title)",
            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
            filled: true, fillColor: Get.theme.scaffoldBackgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
        const SizedBox(height: 10),
        TextField(controller: bodyC, maxLines: 4, style: TextStyle(color: Get.theme.colorScheme.onSurface),
          decoration: InputDecoration(labelText: "Describe the moment…",
            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
            filled: true, fillColor: Get.theme.scaffoldBackgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      ])),
      actions: [
        TextButton(onPressed: () => Get.back(), child: Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8)))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
          onPressed: () async {
            if (titleC.text.trim().isEmpty) { Get.snackbar("Error", "Please add a title"); return; }
            Get.back();
            // Embed the chosen date so it shows on the memory.
            final desc = "📅 ${fmt(when.value)}\n${bodyC.text.trim()}".trim();
            try {
              await _api.post('/memories', data: {
                'title': titleC.text.trim(), 'description': desc, 'mediaType': 'text',
              });
              _fetchMemories();
              Get.snackbar("Saved 💗", "Memory added!");
            } catch (e) { Get.snackbar("Error", "Failed to save."); }
          },
          child: Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final NavigationController nav = Get.find<NavigationController>();
    final partner = Get.find<TrackingController>().partnerUser.value;
    final partnerAvatar = partner?.avatarUrl;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Get.theme.colorScheme.onSurface),
          onPressed: () => nav.selectedIndex.value = 0,
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Memories",
                  style: TextStyle(
                    color: Get.theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                SizedBox(width: 4),
                Text(
                  "💗",
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            Text(
              "Our special moments",
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: Get.theme.colorScheme.onSurface),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.more_vert, color: Get.theme.colorScheme.onSurface),
            onPressed: () {},
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFE8467C),
        onRefresh: () => _fetchMemories(),
        child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Couple Banner Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Get.theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Couple Avatar
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF2F6),
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xFFFFF2F6),
                        backgroundImage: partnerAvatar != null && partnerAvatar.isNotEmpty
                            ? NetworkImage(partnerAvatar)
                            : null,
                        child: partnerAvatar == null || partnerAvatar.isEmpty
                            ? const Icon(Icons.favorite, color: Color(0xFFE8467C), size: 24)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Together Since",
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                Get.find<AuthController>().currentUser.value?.relationshipSince ?? "—",
                                style: TextStyle(
                                  color: Color(0xFFE8467C),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.calendar_month, color: const Color(0xFFE8467C).withOpacity(0.7), size: 16),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Every moment matters 💗",
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Memories Count Box
                    Obx(() => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8467C).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.collections_outlined, color: const Color(0xFFE8467C).withOpacity(0.8), size: 16),
                          const SizedBox(width: 6),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "${_memories.length}",
                                style: TextStyle(
                                  color: Get.theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                "Memories",
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),

            // Horizontal Filter Chips List
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildFilterChip(label: "All", icon: Icons.grid_view_outlined, isActive: true),
                    const SizedBox(width: 8),
                    _buildFilterChip(label: "Notes", icon: Icons.edit_note_outlined, isActive: false),
                  ],
                ),
              ),
            ),

            // Main Content Area: Obx list/empty view
            Obx(() {
              if (_isLoading.value && _memories.isEmpty) {
                return const SizedBox(
                  height: 300,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (_memories.isEmpty) {
                return _buildEmptyState();
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: List.generate(_memories.length, (index) {
                    final memory = _memories[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Get.theme.cardColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (memory.mediaType == 'text' || memory.mediaUrl.isEmpty)
                            // Text memory: a slim accent strip, not a big image block.
                            Container(
                              height: 5, width: double.infinity,
                              decoration: const BoxDecoration(gradient: LinearGradient(
                                  colors: [Color(0xFFE8467C), Color(0xFFA855F7)])),
                            )
                          else if (memory.mediaType == 'video')
                            GestureDetector(
                              onTap: () => Get.to(() => MediaViewerScreen(url: memory.mediaUrl, isVideo: true)),
                              child: Container(
                                height: 200, width: double.infinity, color: const Color(0xFF1E1330),
                                child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 56)),
                              ),
                            )
                          else
                            GestureDetector(
                              onTap: () => Get.to(() => MediaViewerScreen(url: memory.mediaUrl, isVideo: false)),
                              child: CachedNetworkImage(
                                imageUrl: memory.mediaUrl,
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorWidget: (c, u, e) => Container(
                                  height: 200,
                                  color: const Color(0xFFFAFAFC),
                                  child: const Center(
                                    child: Icon(Icons.broken_image, color: Color(0xFF94A3B8), size: 40),
                                  ),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (memory.mediaType == 'text' || memory.mediaUrl.isEmpty) ...[
                                      Container(
                                        width: 34, height: 34,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE8467C).withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(Icons.format_quote, color: Color(0xFFE8467C), size: 20),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      child: Text(
                                        memory.title,
                                        style: TextStyle(
                                          color: Get.theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "${memory.memoryDate.day}/${memory.memoryDate.month}/${memory.memoryDate.year}",
                                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                    ),
                                  ],
                                ),
                                if (memory.description != null && memory.description!.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    memory.description!,
                                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              );
            }),

            const SizedBox(height: 12),

            // Memory Ideas Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF2F6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.lightbulb_outline, color: Color(0xFFE8467C), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Memory Ideas",
                        style: TextStyle(
                          color: Get.theme.colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        "Create memories that last a lifetime",
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Horizontal memory cards list
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
              child: Row(
                children: [
                  _buildIdeaCard(
                    title: "Add Memory",
                    description: "Describe the day\n& what happened",
                    icon: Icons.event_note,
                    iconColor: const Color(0xFFE8467C),
                    bgColor: const Color(0xFFFFF2F6),
                    onTap: _addDatedMemory,
                  ),
                  const SizedBox(width: 12),
                  _buildIdeaCard(
                    title: "Write Note",
                    description: "Write something\nheartfelt",
                    icon: Icons.edit_note,
                    iconColor: const Color(0xFFF59E0B),
                    bgColor: const Color(0xFFFEF3C7),
                    onTap: _addDatedMemory,
                  ),
                ],
              ),
            ),
            const AdBanner('memories'),
            const SizedBox(height: 20),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildFilterChip({required String label, required IconData icon, required bool isActive}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE8467C) : Get.theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? Colors.transparent : const Color(0xFF94A3B8).withOpacity(0.25),
        ),
        boxShadow: isActive ? [
          BoxShadow(
            color: const Color(0xFFE8467C).withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? Colors.white : const Color(0xFF94A3B8), size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Get.theme.colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdeaCard({
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 120,
        height: 130,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Get.theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.015),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Get.theme.colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 9,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Get.theme.cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Empty state box with photo illustration
            Container(
              height: 120,
              width: 120,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF2F6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.mark_as_unread_sharp,
                color: Color(0xFFE8467C),
                size: 70,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "No memories yet",
              style: TextStyle(
                color: Get.theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Start creating beautiful memories together.\nAdd photos, videos or notes to cherish forever.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8467C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                "Add Memory",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: _addDatedMemory,
            ),
          ],
        ),
      ),
    );
  }
}


// â”€â”€ GAMES HUB SCREEN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class GamesHubScreen extends StatelessWidget {
  const GamesHubScreen({super.key});

  // Send a game invite into the chat and jump to the Chat tab — games play in chat.
  void _inviteGameInChat(String slug) {
    final auth = Get.find<AuthController>();
    if (!(auth.currentUser.value?.isPaired ?? false)) {
      Get.snackbar("No partner", "Connect your partner first to play together.");
      return;
    }
    // Premium gate still applies.
    if (!auth.guardPremium('feat_games', label: 'Games')) return;
    if (!auth.guardPremium('game_$slug', label: 'This game')) return;
    Get.find<ChatController>().gameAct('invite', game: slug);
    Get.find<NavigationController>().selectedIndex.value = 1; // Chat tab
    Get.snackbar("🎮 Invite sent", "Open Chat — your game is starting!");
  }

  // Start an answer-&-match game (Couple Quiz engine) with a themed category,
  // playing inside the chat. Notifies the partner. Used by all quiz-style games.
  void _startChatQuiz(String category) {
    final auth = Get.find<AuthController>();
    if (!(auth.currentUser.value?.isPaired ?? false)) {
      Get.snackbar("No partner", "Connect your partner first to play together.");
      return;
    }
    if (!auth.guardPremium('feat_games', label: 'Games')) return;
    Get.find<ChatController>().startQuizInChat(category);
    Get.find<NavigationController>().selectedIndex.value = 1; // Chat tab
  }

  // Start a turn-based ask game (Couple Quiz / Would You Rather / Truth & Dare) in chat.
  void _startAskGame(String game) {
    final auth = Get.find<AuthController>();
    if (!auth.gameOn(game)) { Get.snackbar("Unavailable", "This game is currently turned off."); return; }
    if (!(auth.currentUser.value?.isPaired ?? false)) {
      Get.snackbar("No partner", "Connect your partner first to play together.");
      return;
    }
    if (!auth.guardPremium('feat_games', label: 'Games')) return;
    Get.find<ChatController>().startAskQuizInChat(game);
    Get.find<NavigationController>().selectedIndex.value = 1; // Chat tab
  }

  void _showComingSoon(BuildContext context, String gameName) {
    Get.dialog(
      AlertDialog(
        backgroundColor: Get.theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.star, color: Color(0xFFE8467C)),
            const SizedBox(width: 8),
            Text(
              gameName,
              style: TextStyle(color: Get.theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          "We are working hard to bring this game to you and your partner! Stay tuned. 💖",
          style: TextStyle(color: Color(0xFF64748B), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              "Awesome",
              style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Get.theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.015),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, color: iconColor, size: 10),
                      const SizedBox(width: 4),
                      Text(
                        "2 Players",
                        style: TextStyle(
                          color: iconColor,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Get.theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Icon(
                Icons.arrow_forward,
                color: const Color(0xFF94A3B8).withOpacity(0.8),
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partner = Get.find<TrackingController>().partnerUser.value;
    final partnerName = partner?.displayName ?? "Partner";
    final isOnline = partner?.isOnline ?? true;
    final partnerAvatar = partner?.avatarUrl;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Get.theme.colorScheme.onSurface),
          onPressed: () => Get.find<NavigationController>().selectedIndex.value = 0,
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Games",
                  style: TextStyle(
                    color: Get.theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                SizedBox(width: 4),
                Text(
                  "💗",
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            Text(
              "Play together, grow together",
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10,
              ),
            ),
          ],
        ),
        actions: const [],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Partner Status Banner Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Get.theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: const Color(0xFFFFF2F6),
                          backgroundImage: partnerAvatar != null && partnerAvatar.isNotEmpty
                              ? NetworkImage(partnerAvatar)
                              : null,
                          child: partnerAvatar == null || partnerAvatar.isEmpty
                              ? Text(
                                  partnerName.substring(0, 1).toUpperCase(),
                                  style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold, fontSize: 18),
                                )
                              : null,
                        ),
                        if (isOnline)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Obx(() => Text(
                                Get.find<TrackingController>().partnerUser.value?.displayName ?? "Partner",
                                style: TextStyle(
                                  color: Get.theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              )),
                              const SizedBox(width: 4),
                              Text("💗", style: TextStyle(fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Obx(() {
                            final on = Get.find<TrackingController>().partnerUser.value?.isOnline ?? false;
                            final c = on ? const Color(0xFF10B981) : const Color(0xFF94A3B8);
                            return Row(children: [
                              Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Text(on ? "Online" : "Offline",
                                  style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600)),
                            ]);
                          }),
                          const SizedBox(height: 2),
                          Text(
                            "Let's play something fun today! 💗",
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Love Buzz button
                    InkWell(
                      onTap: () => showBuzzPicker(),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF2F6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.favorite, color: Color(0xFFE8467C), size: 18),
                            SizedBox(height: 2),
                            Text(
                              "Love Buzz",
                              style: TextStyle(
                                color: Color(0xFFE8467C),
                                fontWeight: FontWeight.bold,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Section Header
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Our Games",
                    style: TextStyle(
                      color: Get.theme.colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Get.theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Text(
                          "All Games",
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_down, color: Color(0xFF64748B), size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "Fun games to connect and enjoy together",
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
            ),

            const AdBanner('games'),
            const SizedBox(height: 12),

            // Grid of 10 Games
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: [
                  _buildGameCard(
                    context: context,
                    title: "1. Truth or Dare",
                    description: "Ask, dare and discover new things about each other",
                    icon: Icons.masks,
                    iconColor: const Color(0xFFE8467C),
                    bgColor: const Color(0xFFFFF2F6),
                    onTap: () => _startAskGame('truth_dare'),
                  ),
                  _buildGameCard(
                    context: context,
                    title: "2. Couple Quiz",
                    description: "Test how well you know each other",
                    icon: Icons.quiz_outlined,
                    iconColor: const Color(0xFF7C3AED),
                    bgColor: const Color(0xFFF3E8FF),
                    onTap: () => _startAskGame('couple_quiz'),
                  ),
                  _buildGameCard(
                    context: context,
                    title: "3. Would You Rather?",
                    description: "Pick between two fun and tricky choices",
                    icon: Icons.help_outline,
                    iconColor: const Color(0xFF10B981),
                    bgColor: const Color(0xFFD1FAE5),
                    onTap: () => _startAskGame('would_rather'),
                  ),
                  _buildGameCard(
                    context: context,
                    title: "4. Emoji Challenge",
                    description: "Guess the word or phrase using only emojis",
                    icon: Icons.emoji_emotions_outlined,
                    iconColor: const Color(0xFFF59E0B),
                    bgColor: const Color(0xFFFEF3C7),
                    onTap: () => _startAskGame('emoji'),
                  ),
                  _buildGameCard(
                    context: context,
                    title: "5. Memory Match",
                    description: "Find matching pairs and test your memory",
                    icon: Icons.grid_view_outlined,
                    iconColor: const Color(0xFF3B82F6),
                    bgColor: const Color(0xFFDBEAFE),
                    onTap: () => _showComingSoon(context, "Memory Match"),
                  ),
                  _buildGameCard(
                    context: context,
                    title: "6. Love Letters",
                    description: "Write cute letters to each other",
                    icon: Icons.favorite_outline,
                    iconColor: const Color(0xFFEC4899),
                    bgColor: const Color(0xFFFCE7F3),
                    onTap: () => _showComingSoon(context, "Love Letters"),
                  ),
                  _buildGameCard(
                    context: context,
                    title: "7. Movie Match",
                    description: "Guess the movie from emoji or quotes",
                    icon: Icons.movie_outlined,
                    iconColor: const Color(0xFF8B5CF6),
                    bgColor: const Color(0xFFEDE9FE),
                    onTap: () => _showComingSoon(context, "Movie Match"),
                  ),
                  _buildGameCard(
                    context: context,
                    title: "8. Song Challenge",
                    description: "Share songs that describe your mood",
                    icon: Icons.music_note_outlined,
                    iconColor: const Color(0xFF06B6D4),
                    bgColor: const Color(0xFFECFEFF),
                    onTap: () => _showComingSoon(context, "Song Challenge"),
                  ),
                  _buildGameCard(
                    context: context,
                    title: "9. Never Have I Ever",
                    description: "Find out new and fun things about each other",
                    icon: Icons.track_changes,
                    iconColor: const Color(0xFFF97316),
                    bgColor: const Color(0xFFFFEDD5),
                    onTap: () => _startAskGame('nhie'),
                  ),
                  _buildGameCard(
                    context: context,
                    title: "10. Puzzle Time",
                    description: "Solve beautiful puzzles together",
                    icon: Icons.extension_outlined,
                    iconColor: const Color(0xFF14B8A6),
                    bgColor: const Color(0xFFCCFBF1),
                    onTap: () => _startAskGame('puzzle'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Suggest a Game Banner Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF2F6), Color(0xFFFCE7F3)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    // Gift box icon representation
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Get.theme.cardColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.card_giftcard, color: Color(0xFFE8467C), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "More fun on the way!",
                            style: TextStyle(
                              color: Get.theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "We're adding new games regularly.\nStay tuned! 💗",
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFFE8467C),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(color: Color(0xFFFFF2F6)),
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.chat_bubble_outline, size: 12, color: Color(0xFFE8467C)),
                            label: Text(
                              "Suggest a Game",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
                            ),
                            onPressed: () {
                              Get.snackbar("Thank you!", "We have received your suggestion! 💖");
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ LOVE QUIZ GAME â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class LoveQuizScreen extends StatefulWidget {
  const LoveQuizScreen({super.key});

  @override
  State<LoveQuizScreen> createState() => _LoveQuizScreenState();
}

class _LoveQuizScreenState extends State<LoveQuizScreen> {
  final GameController gc = Get.find<GameController>();
  final AuthController auth = Get.find<AuthController>();
  final TextEditingController _answerController = TextEditingController();

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("Love Quiz", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Obx(() {
        final session = gc.activeSession.value;

        if (gc.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (session == null || session['gameType'] != 'love_quiz' || session['status'] != 'active') {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("💌", style: TextStyle(fontSize: 72)),
                const SizedBox(height: 24),
                Text(
                  "Start Love Quiz",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  "Both you and your partner will answer the same questions about each other in real-time. Once both answer, your responses are revealed!",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    text: "Start Game Session",
                    onPressed: () => gc.startGame('love_quiz'),
                  ),
                ),
              ],
            ),
          );
        }

        final rounds = session['rounds'] as List;
        final currentRoundNum = session['currentRound'] as int;
        final totalRounds = session['totalRounds'] as int;

        if (rounds.isEmpty || currentRoundNum > rounds.length) {
          return const Center(child: Text("Loading game round...", style: TextStyle(color: Colors.white)));
        }

        final currentRound = rounds[currentRoundNum - 1];
        final rawLQ = (currentRound['question'] ?? '').toString().trim();
        final question = rawLQ.isNotEmpty ? rawLQ : fallbackPrompt('truth', currentRoundNum - 1);
        final answers = gc.currentRoundAnswers;

        final myId = auth.currentUser.value?.id ?? '';
        final partner = Get.find<TrackingController>().partnerUser.value;
        final hasMyAnswer = gc.hasSubmittedAnswer.value;
        final hasPartnerAnswer = answers.any((a) => a['userId'].toString() != myId);
        final bothAnswered = answers.length >= 2;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: currentRoundNum / totalRounds,
                color: Theme.of(context).colorScheme.secondary,
                backgroundColor: Colors.white10,
              ),
              const SizedBox(height: 24),
              Text(
                "Round $currentRoundNum of $totalRounds",
                style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(
                question,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
              ),
              const SizedBox(height: 32),

              if (!hasMyAnswer) ...[
                TextField(
                  controller: _answerController,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Your Answer",
                    labelStyle: const TextStyle(color: Colors.white60),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    text: "Submit Answer",
                    onPressed: () {
                      final ans = _answerController.text.trim();
                      if (ans.isEmpty) {
                        Get.snackbar("Error", "Please type an answer first.");
                        return;
                      }
                      gc.submitAnswer(ans);
                      _answerController.clear();
                    },
                  ),
                ),
              ] else if (!bothAnswered) ...[
                Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      Text(
                        "Waiting for partner's answer...",
                        style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasPartnerAnswer ? "Partner answered! Waiting for reveal." : "Partner has not answered yet.",
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Text(
                  "Round Results 💖",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                ...answers.map((ans) {
                  final isMe = ans['userId'].toString() == myId;
                  final name = isMe ? "You" : (partner?.displayName ?? "Partner");
                  final color = isMe ? Theme.of(context).colorScheme.secondary : Colors.blueAccent;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ans['answer'] ?? '',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 32),
                if (currentRoundNum < totalRounds)
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      text: "Next Question â€º",
                      onPressed: () => gc.advanceRound(),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      text: "Finish Game 🎉",
                      onPressed: () => gc.finishGame(),
                    ),
                  ),
              ],
            ],
          ),
        );
      }),
    );
  }
}

// â”€â”€ TRUTH OR DARE GAME â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class TruthOrDareScreen extends StatefulWidget {
  const TruthOrDareScreen({super.key});

  @override
  State<TruthOrDareScreen> createState() => _TruthOrDareScreenState();
}

class _TruthOrDareScreenState extends State<TruthOrDareScreen> {
  final GameController gc = Get.find<GameController>();
  final AuthController auth = Get.find<AuthController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("Truth or Dare", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Obx(() {
        final session = gc.activeSession.value;

        if (gc.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (session == null || session['gameType'] != 'truth_or_dare' || session['status'] != 'active') {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("🎯", style: TextStyle(fontSize: 72)),
                const SizedBox(height: 24),
                Text(
                  "Start Truth or Dare",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  "Play a synced, real-time multiplayer Truth or Dare session! Complete fun cards together and grow closer.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    text: "Start Truth or Dare",
                    onPressed: () => gc.startGame('truth_or_dare'),
                  ),
                ),
              ],
            ),
          );
        }

        final rounds = session['rounds'] as List;
        final currentRoundNum = session['currentRound'] as int;
        final totalRounds = session['totalRounds'] as int;

        if (rounds.isEmpty || currentRoundNum > rounds.length) {
          return const Center(child: Text("Loading game round...", style: TextStyle(color: Colors.white)));
        }

        final currentRound = rounds[currentRoundNum - 1];
        final category = (currentRound['category'] ?? 'truth').toString().toUpperCase();
        final rawQ = (currentRound['question'] ?? '').toString().trim();
        final question = rawQ.isNotEmpty ? rawQ : fallbackPrompt(category, currentRoundNum - 1);
        final answers = gc.currentRoundAnswers;

        final myId = auth.currentUser.value?.id ?? '';
        final partner = Get.find<TrackingController>().partnerUser.value;
        final hasMyAnswer = gc.hasSubmittedAnswer.value;
        final hasPartnerAnswer = answers.any((a) => a['userId'].toString() != myId);
        final bothAnswered = answers.length >= 2;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: currentRoundNum / totalRounds,
                color: Colors.purpleAccent,
                backgroundColor: Colors.white10,
              ),
              const SizedBox(height: 24),
              Text(
                "Round $currentRoundNum of $totalRounds",
                style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 24),
              
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: category == 'TRUTH'
                        ? [const Color(0xFF3B82F6).withOpacity(0.15), const Color(0xFF1D4ED8).withOpacity(0.15)]
                        : [const Color(0xFFEC4899).withOpacity(0.15), const Color(0xFFBE185D).withOpacity(0.15)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: category == 'TRUTH' ? Colors.blue.withOpacity(0.3) : Colors.pink.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: category == 'TRUTH' ? Colors.blue : Colors.pink,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        category,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      question,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              if (!hasMyAnswer) ...[
                Text(
                  "Perform the truth or dare, then confirm below:",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    text: "I've Completed It! âœ…",
                    onPressed: () => gc.submitAnswer("Completed"),
                  ),
                ),
              ] else if (!bothAnswered) ...[
                Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: Colors.purpleAccent),
                      const SizedBox(height: 24),
                      Text(
                        "Waiting for partner to complete...",
                        style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasPartnerAnswer ? "Partner confirmed! Waiting for reveal." : "Partner has not confirmed yet.",
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Center(
                  child: Column(
                    children: [
                      Text(
                        "Both completed! 🎉",
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "You and ${partner?.displayName ?? 'Partner'} have both successfully finished this round's prompt.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 32),
                      if (currentRoundNum < totalRounds)
                        SizedBox(
                          width: double.infinity,
                          child: GradientButton(
                            text: "Next Prompt â€º",
                            onPressed: () => gc.advanceRound(),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: GradientButton(
                            text: "Finish Game 🎉",
                            onPressed: () => gc.finishGame(),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }
}

// â”€â”€ TIC TAC TOE GAME â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key});

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen> {
  List<String> _board = List.filled(9, "");
  bool _xTurn = true; // true = ❤️, false = â­
  String _winner = "";
  bool _gameOver = false;

  void _resetGame() {
    setState(() {
      _board = List.filled(9, "");
      _xTurn = true;
      _winner = "";
      _gameOver = false;
    });
  }

  void _makeMove(int index) {
    if (_board[index] != "" || _gameOver) return;

    setState(() {
      _board[index] = _xTurn ? "❤️" : "â­";
      _checkWinner();
      if (!_gameOver) {
        _xTurn = !_xTurn;
      }
    });
  }

  void _checkWinner() {
    final winPatterns = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
      [0, 3, 6], [1, 4, 7], [2, 5, 8], // cols
      [0, 4, 8], [2, 4, 6]             // diagonals
    ];

    for (var pattern in winPatterns) {
      if (_board[pattern[0]] != "" &&
          _board[pattern[0]] == _board[pattern[1]] &&
          _board[pattern[0]] == _board[pattern[2]]) {
        _winner = _board[pattern[0]];
        _gameOver = true;
        return;
      }
    }

    if (!_board.contains("")) {
      _winner = "Draw";
      _gameOver = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("Tic Tac Toe (Love Edition)", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Text(
              _gameOver
                  ? (_winner == "Draw" ? "It's a tie! 🤝" : "Winner is: $_winner 🎉")
                  : "Turn: ${_xTurn ? "❤️" : "â­"}",
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            AspectRatio(
              aspectRatio: 1,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: 9,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, idx) {
                  return InkWell(
                    onTap: () => _makeMove(idx),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Center(
                        child: Text(
                          _board[idx],
                          style: TextStyle(fontSize: 48),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              child: GradientButton(
                text: "Restart Game",
                onPressed: _resetGame,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── In-app media viewer: zoom photos, play videos (no browser) ──────────
// WhatsApp-style chat search — type a word, see matching messages.
class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({super.key});
  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final ChatController _chat = Get.find<ChatController>();
  final AuthController _auth = Get.find<AuthController>();
  final _c = TextEditingController();
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    final myId = _auth.currentUser.value?.id ?? '';
    final q = _q.trim().toLowerCase();
    final results = q.isEmpty
        ? <Message>[]
        : _chat.messages.where((m) => m.type == 'text' && m.content.toLowerCase().contains(q)).toList();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0, foregroundColor: on,
        title: TextField(
          controller: _c, autofocus: true,
          style: TextStyle(color: on, fontSize: 16),
          decoration: const InputDecoration(
            hintText: "Search messages…", border: InputBorder.none,
            hintStyle: TextStyle(color: Color(0xFF94A3B8))),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      body: q.isEmpty
          ? const Center(child: Text("Type to search your chat", style: TextStyle(color: Color(0xFF94A3B8))))
          : results.isEmpty
              ? const Center(child: Text("No messages found", style: TextStyle(color: Color(0xFF94A3B8))))
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (_, i) {
                    final m = results[i];
                    final isMe = m.senderId == myId;
                    final t = m.createdAt.toLocal();
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFE8467C).withOpacity(0.15),
                        child: Text(isMe ? "You" : "•", style: const TextStyle(color: Color(0xFFE8467C), fontSize: 11, fontWeight: FontWeight.bold))),
                      title: Text(m.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: on)),
                      subtitle: Text("${t.day}/${t.month} · ${t.hour}:${t.minute.toString().padLeft(2, '0')}",
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    );
                  },
                ),
    );
  }
}

// WhatsApp-style media gallery — all photos/videos shared in the chat.
class MediaGalleryScreen extends StatefulWidget {
  const MediaGalleryScreen({super.key});
  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  final ChatController _chat = Get.find<ChatController>();
  List<Message> _media = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final m = await _chat.fetchMedia();
    if (!mounted) return;
    setState(() { _media = m; _loading = false; });
  }

  // Long-press a photo → free its storage (remove the downloaded copy). It stays
  // in the chat and reloads if opened again.
  void _itemStorageSheet(Message m) {
    Get.bottomSheet(Container(
      decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 6),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined, color: Color(0xFFF59E0B)),
          title: const Text("Remove from device"),
          subtitle: const Text("Frees storage · stays in chat, reloads when opened", style: TextStyle(fontSize: 11)),
          onTap: () async {
            Get.back();
            await _chat.removeCached(m.content);
            Get.snackbar("Removed from device", "This photo's download was cleared to free storage.");
          },
        ),
        const SizedBox(height: 6),
      ])),
    ));
  }

  void _confirmDeleteAll() {
    Get.dialog(AlertDialog(
      backgroundColor: Get.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text("Delete all media?"),
      content: const Text("Removes every photo & video from the chat. Can't be undone."),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8)))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
          onPressed: () async { Get.back(); await _chat.clearMedia(); if (mounted) setState(() => _media = []); },
          child: const Text("Delete", style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0, foregroundColor: on,
        title: const Text("Media", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_media.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFEF4444)), tooltip: "Delete all", onPressed: _confirmDeleteAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
          : _media.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text("🖼️", style: TextStyle(fontSize: 44)),
                  const SizedBox(height: 8),
                  Text("No media yet", style: TextStyle(color: on, fontWeight: FontWeight.bold)),
                  const Text("Photos & videos you share will show here.", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                ]))
              : GridView.builder(
                  padding: const EdgeInsets.all(3),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 3, crossAxisSpacing: 3),
                  itemCount: _media.length,
                  itemBuilder: (_, i) {
                    final m = _media[i];
                    final isVideo = m.type == 'video';
                    return GestureDetector(
                      onTap: () => Get.to(() => MediaViewerScreen(url: m.content, isVideo: isVideo)),
                      onLongPress: () => _itemStorageSheet(m),
                      child: Stack(fit: StackFit.expand, children: [
                        Container(color: Get.theme.cardColor,
                          child: CachedNetworkImage(imageUrl: m.content, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Color(0xFF94A3B8))))),
                        if (isVideo) const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 34)),
                      ]),
                    );
                  },
                ),
    );
  }
}

class MediaViewerScreen extends StatefulWidget {
  final String url;
  final bool isVideo;
  const MediaViewerScreen({super.key, required this.url, required this.isVideo});
  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  VideoPlayerController? _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _c = VideoPlayerController.networkUrl(Uri.parse(widget.url))
        ..initialize().then((_) {
          setState(() => _ready = true);
          _c!.play();
        });
    }
  }

  @override
  void dispose() { _c?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: widget.isVideo
            ? (_ready && _c != null
                ? AspectRatio(aspectRatio: _c!.value.aspectRatio, child: VideoPlayer(_c!))
                : const CircularProgressIndicator(color: Color(0xFFE8467C)))
            : InteractiveViewer(
                minScale: 0.8, maxScale: 4,
                child: Image.network(widget.url,
                    errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.white54, size: 60)),
              ),
      ),
      floatingActionButton: widget.isVideo && _ready && _c != null
          ? FloatingActionButton(
              backgroundColor: const Color(0xFFE8467C),
              onPressed: () => setState(() => _c!.value.isPlaying ? _c!.pause() : _c!.play()),
              child: Icon(_c!.value.isPlaying ? Icons.pause : Icons.play_arrow),
            )
          : null,
    );
  }
}

// ── MILESTONES SCREEN ────────────────────────────────────────────────────
class _MilestonesScreen extends StatefulWidget {
  const _MilestonesScreen();
  @override
  State<_MilestonesScreen> createState() => _MilestonesScreenState();
}
class _MilestonesScreenState extends State<_MilestonesScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await _api.get('/milestones');
      if (r.statusCode == 200 && r.data['success'] == true) {
        _items = (r.data['data'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _add() {
    final titleC = TextEditingController();
    final iconC = TextEditingController(text: '💕');
    DateTime picked = DateTime.now();
    Get.dialog(AlertDialog(
      backgroundColor: Get.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text("Add Milestone"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleC, decoration: const InputDecoration(hintText: "e.g. First Date, Anniversary")),
        const SizedBox(height: 10),
        TextField(controller: iconC, decoration: const InputDecoration(hintText: "Emoji icon")),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.calendar_today, size: 16),
          label: const Text("Pick Date"),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.now(),
                firstDate: DateTime(2000), lastDate: DateTime(2050));
            if (d != null) picked = d;
          },
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
          onPressed: () async {
            if (titleC.text.trim().isEmpty) return;
            Get.back();
            await _api.post('/milestones', data: {
              'title': titleC.text.trim(),
              'icon': iconC.text.trim().isNotEmpty ? iconC.text.trim() : '💕',
              'eventDate': picked.toIso8601String().substring(0, 10),
            });
            _load();
          },
          child: const Text("Save", style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Get.theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("Milestones 💕"), backgroundColor: Get.theme.scaffoldBackgroundColor, elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _add)]),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
          : _items.isEmpty
              ? const Center(child: Text("No milestones yet.\nTap + to add your special dates!", textAlign: TextAlign.center))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (c, i) {
                    final m = _items[i];
                    final days = m['daysUntil'] ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Get.theme.cardColor,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
                      ),
                      child: Row(children: [
                        Text(m['icon'] ?? '💕', style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m['title'] ?? '', style: TextStyle(fontWeight: FontWeight.w700, color: Get.theme.colorScheme.onSurface, fontSize: 15)),
                          Text(m['event_date'] ?? '', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                        ])),
                        Column(children: [
                          Text(days == 0 ? "🎉" : "$days", style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: days == 0 ? 24 : 20,
                            color: days == 0 ? null : const Color(0xFFE8467C))),
                          if (days != 0) const Text("days", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                        ]),
                        IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF94A3B8)),
                          onPressed: () async {
                            await _api.post('/milestones/delete', data: {'id': m['id']});
                            _load();
                          }),
                      ]),
                    );
                  },
                ),
    );
  }
}

// ── SHARED TODOS SCREEN ──────────────────────────────────────────────────
class _SharedTodosScreen extends StatefulWidget {
  const _SharedTodosScreen();
  @override
  State<_SharedTodosScreen> createState() => _SharedTodosScreenState();
}
class _SharedTodosScreenState extends State<_SharedTodosScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  final _tc = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await _api.get('/todos');
      if (r.statusCode == 200 && r.data['success'] == true) {
        _items = (r.data['data'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final t = _tc.text.trim();
    if (t.isEmpty) return;
    _tc.clear();
    await _api.post('/todos', data: {'text': t});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Get.theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("Shared To-Do ✅"), backgroundColor: Get.theme.scaffoldBackgroundColor, elevation: 0),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(child: TextField(controller: _tc, decoration: InputDecoration(
              hintText: "Add a task...",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ))),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Color(0xFFE8467C), size: 32),
              onPressed: _add,
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
              : _items.isEmpty
                  ? const Center(child: Text("No tasks yet! Add one above 📝", style: TextStyle(color: Color(0xFF94A3B8))))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _items.length,
                      itemBuilder: (c, i) {
                        final t = _items[i];
                        final done = t['done'] == true;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Get.theme.cardColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            leading: GestureDetector(
                              onTap: () async {
                                await _api.post('/todos/toggle', data: {'id': t['id']});
                                _load();
                              },
                              child: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: done ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                            ),
                            title: Text(t['text'] ?? '', style: TextStyle(
                              decoration: done ? TextDecoration.lineThrough : null,
                              color: done ? const Color(0xFF94A3B8) : Get.theme.colorScheme.onSurface)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF94A3B8)),
                              onPressed: () async {
                                await _api.post('/todos/delete', data: {'id': t['id']});
                                _load();
                              },
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ── MOOD HISTORY SCREEN ──────────────────────────────────────────────────
class _MoodHistoryScreen extends StatefulWidget {
  const _MoodHistoryScreen();
  @override
  State<_MoodHistoryScreen> createState() => _MoodHistoryScreenState();
}
class _MoodHistoryScreenState extends State<_MoodHistoryScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  static const _moodEmoji = {
    'happy': '😊', 'excited': '🤩', 'romantic': '🥰', 'sad': '😢',
    'busy': '💼', 'sleeping': '😴', 'gaming': '🎮', 'working': '💻',
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await _api.get('/mood/history?days=30');
      if (r.statusCode == 200 && r.data['success'] == true) {
        _entries = (r.data['data'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final myId = Get.find<AuthController>().currentUser.value?.id ?? '';
    return Scaffold(
      backgroundColor: Get.theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("Mood History 📊"), backgroundColor: Get.theme.scaffoldBackgroundColor, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
          : _entries.isEmpty
              ? const Center(child: Text("No mood data yet.\nSet your mood from the home screen!", textAlign: TextAlign.center))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  itemBuilder: (c, i) {
                    final e = _entries[_entries.length - 1 - i];
                    final mood = e['mood'] ?? '';
                    final isMe = e['user_id']?.toString() == myId;
                    final emoji = _moodEmoji[mood] ?? '😐';
                    String time = '';
                    try {
                      final dt = DateTime.parse(e['created_at']).toLocal();
                      time = '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                    } catch (_) {}
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Get.theme.cardColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(children: [
                        Text(emoji, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(isMe ? "You" : "Partner", style: TextStyle(
                            fontWeight: FontWeight.w700, color: isMe ? const Color(0xFFE8467C) : const Color(0xFF7C3AED))),
                          Text(mood, style: TextStyle(color: Get.theme.colorScheme.onSurface, fontSize: 13)),
                        ])),
                        Text(time, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                      ]),
                    );
                  },
                ),
    );
  }
}

// ── DATE NIGHT SUGGESTIONS SCREEN ────────────────────────────────────────
class _DateNightScreen extends StatefulWidget {
  const _DateNightScreen();
  @override
  State<_DateNightScreen> createState() => _DateNightScreenState();
}
class _DateNightScreenState extends State<_DateNightScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _ideas = [];
  bool _loading = true;
  String _cat = 'all';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.get('/date-night?category=$_cat');
      if (r.statusCode == 200 && r.data['success'] == true) {
        _ideas = (r.data['data'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Get.theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("Date Night Ideas 🌙"), backgroundColor: Get.theme.scaffoldBackgroundColor, elevation: 0),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: ['all', 'romantic', 'adventure', 'chill', 'creative'].map((c) =>
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c[0].toUpperCase() + c.substring(1)),
                selected: _cat == c,
                selectedColor: const Color(0xFFE8467C),
                labelStyle: TextStyle(color: _cat == c ? Colors.white : Get.theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
                onSelected: (_) { _cat = c; _load(); },
              ),
            )).toList()),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _ideas.length,
                  itemBuilder: (c, i) {
                    final idea = _ideas[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Get.theme.cardColor,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
                      ),
                      child: Row(children: [
                        Text(idea['icon'] ?? '💡', style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(idea['title'] ?? '', style: TextStyle(fontWeight: FontWeight.w700, color: Get.theme.colorScheme.onSurface, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(idea['desc'] ?? '', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                        ])),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ── LOVE LANGUAGE QUIZ SCREEN ────────────────────────────────────────────
class _LoveLanguageScreen extends StatefulWidget {
  const _LoveLanguageScreen();
  @override
  State<_LoveLanguageScreen> createState() => _LoveLanguageScreenState();
}
class _LoveLanguageScreenState extends State<_LoveLanguageScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _mine;
  Map<String, dynamic>? _partner;
  bool _loading = true;
  int _qIndex = -1;
  final Map<String, int> _scores = {'words': 0, 'time': 0, 'gifts': 0, 'service': 0, 'touch': 0};

  static const _questions = [
    {'q': 'I feel most loved when my partner...', 'a': 'Tells me they love me', 'type': 'words', 'b': 'Spends quality time with me', 'typeB': 'time'},
    {'q': 'What makes me happiest?', 'a': 'Receiving a thoughtful gift', 'type': 'gifts', 'b': 'A warm hug or holding hands', 'typeB': 'touch'},
    {'q': 'I appreciate it most when my partner...', 'a': 'Helps me with tasks', 'type': 'service', 'b': 'Writes me a sweet message', 'typeB': 'words'},
    {'q': 'My ideal date is...', 'a': 'A full day together, no phones', 'type': 'time', 'b': 'Getting a surprise gift', 'typeB': 'gifts'},
    {'q': 'I feel closest to my partner when...', 'a': 'They do something helpful for me', 'type': 'service', 'b': 'We cuddle on the couch', 'typeB': 'touch'},
    {'q': 'What means the most?', 'a': 'Hearing "I\'m proud of you"', 'type': 'words', 'b': 'Having uninterrupted time together', 'typeB': 'time'},
    {'q': 'I\'d love it if my partner...', 'a': 'Surprised me with flowers', 'type': 'gifts', 'b': 'Cooked dinner for me', 'typeB': 'service'},
    {'q': 'I feel most connected through...', 'a': 'Physical closeness', 'type': 'touch', 'b': 'Deep conversation', 'typeB': 'time'},
    {'q': 'A perfect evening is...', 'a': 'My partner compliments me genuinely', 'type': 'words', 'b': 'A back massage after a long day', 'typeB': 'touch'},
    {'q': 'I value most...', 'a': 'When they remember the little things and surprise me', 'type': 'gifts', 'b': 'When they take over my chores', 'typeB': 'service'},
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await _api.get('/love-language');
      if (r.statusCode == 200 && r.data['success'] == true) {
        _mine = r.data['data']?['mine'];
        _partner = r.data['data']?['partner'];
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _answer(String type) {
    _scores[type] = (_scores[type] ?? 0) + 1;
    if (_qIndex + 1 >= _questions.length) {
      _submit();
    } else {
      setState(() => _qIndex++);
    }
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final r = await _api.post('/love-language', data: _scores);
      if (r.statusCode == 200 && r.data['success'] == true) {
        _mine = {'result': r.data['data']['result'], ..._scores};
      }
    } catch (_) {}
    setState(() { _loading = false; _qIndex = -1; });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_qIndex >= 0 && _qIndex < _questions.length) {
      final q = _questions[_qIndex];
      return Scaffold(
        backgroundColor: Get.theme.scaffoldBackgroundColor,
        appBar: AppBar(title: Text("Question ${_qIndex + 1}/${_questions.length}"), backgroundColor: Get.theme.scaffoldBackgroundColor, elevation: 0),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(q['q']!, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Get.theme.colorScheme.onSurface), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            _optionBtn(q['a']!, q['type']!),
            const SizedBox(height: 14),
            _optionBtn(q['b']!, q['typeB']!),
          ]),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Get.theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("Love Language ❤️"), backgroundColor: Get.theme.scaffoldBackgroundColor, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
          : SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
              if (_mine != null && _mine!['result'] != null) ...[
                const Text("Your Love Language", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]),
                    borderRadius: BorderRadius.circular(20)),
                  child: Column(children: [
                    const Text("❤️", style: TextStyle(fontSize: 36)),
                    const SizedBox(height: 8),
                    Text(_mine!['result'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
                  ]),
                ),
                const SizedBox(height: 20),
              ],
              if (_partner != null && _partner!['result'] != null) ...[
                const Text("Partner's Love Language", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Get.theme.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE8467C).withOpacity(0.3))),
                  child: Column(children: [
                    const Text("💗", style: TextStyle(fontSize: 36)),
                    const SizedBox(height: 8),
                    Text(_partner!['result'] ?? '', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Get.theme.colorScheme.onSurface)),
                  ]),
                ),
                const SizedBox(height: 24),
              ],
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8467C),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                label: Text(_mine != null ? "Retake Quiz" : "Take Quiz", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                onPressed: () => setState(() { _qIndex = 0; _scores.updateAll((k, v) => 0); }),
              ),
            ])),
    );
  }

  Widget _optionBtn(String text, String type) {
    return SizedBox(width: double.infinity, child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Get.theme.cardColor,
        foregroundColor: Get.theme.colorScheme.onSurface,
        elevation: 1,
        padding: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      onPressed: () => _answer(type),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
    ));
  }
}
