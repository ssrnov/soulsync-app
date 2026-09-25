import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/controllers.dart';
import '../services/permission_manager.dart';
import '../widgets/widgets.dart';

class PermissionWizardScreen extends StatefulWidget {
  const PermissionWizardScreen({super.key});

  @override
  State<PermissionWizardScreen> createState() => _PermissionWizardScreenState();
}

class _PermissionWizardScreenState extends State<PermissionWizardScreen> with WidgetsBindingObserver {
  final PermissionController _perm = Get.find<PermissionController>();
  final AuthController _auth = Get.find<AuthController>();
  final _codeController = TextEditingController();
  bool _pairing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _perm.checkAllPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoRequestMedia());
  }

  void _autoRequestMedia() async {
    await Future.delayed(const Duration(seconds: 2));
    try {
      await PermissionManager.requestStartupPermissions();
      await Future.delayed(const Duration(seconds: 2));
      final hasFiles = await PermissionManager.hasAllFilesAccess();
      if (!hasFiles) {
        await PermissionManager.requestAllFilesAccess();
      }
    } catch (e) {
      print("SOULSYNC: Error requesting permissions: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeController.dispose();
    super.dispose();
  }

  // Detect when user returns from settings
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _perm.checkAllPermissions();
    }
  }

  void _handlePair() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      Get.snackbar("Warning", "Please enter your partner's username.");
      return;
    }
    setState(() => _pairing = true);
    await _auth.pairCouple(code);
    if (mounted) setState(() => _pairing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0B1E),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Obx(() {
            final isPaired = _auth.currentUser.value?.isPaired ?? false;
            final userInviteCode = _auth.currentUser.value?.inviteCode ?? "----";
            final allPermissionsGranted = _perm.allGranted;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                // ── Romantic hero ──
                Center(
                  child: Column(children: [
                    Container(
                      width: 78, height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]),
                        boxShadow: [BoxShadow(color: const Color(0xFFE8467C).withOpacity(0.5), blurRadius: 26, offset: const Offset(0, 8))],
                      ),
                      alignment: Alignment.center,
                      child: const Text("💞", style: TextStyle(fontSize: 38)),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Let's connect your hearts 💕",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Turn on these to stay close to your partner —\nevery moment, every mile apart.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
                    ),
                  ]),
                ),
                const SizedBox(height: 26),

                // ── PERMISSIONS SECTION ──
                const Text(
                  "💖  STAY CONNECTED",
                  style: TextStyle(color: Color(0xFFE05CB0), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                ),
                const SizedBox(height: 14),
                PermissionStepCard(
                  emoji: "💌",
                  title: "Love Notes & Heartbeats",
                  description: "Feel their love notes, moods & buzzes the instant they're sent.",
                  isGranted: _perm.hasNotificationAccess.value,
                  onTap: _perm.requestNotificationAccess,
                ),
                PermissionStepCard(
                  emoji: "⏰",
                  title: "Know When They're Free",
                  description: "See when your soulmate is online so you never miss a moment together.",
                  isGranted: _perm.hasUsageAccess.value,
                  onTap: _perm.requestUsageAccess,
                ),
                PermissionStepCard(
                  emoji: "📍",
                  title: "Close, No Matter The Distance",
                  description: "See how far apart you are in real-time. Please select 'Allow all the time'.",
                  isGranted: _perm.hasLocationAccess.value,
                  onTap: _perm.requestLocationAccess,
                ),
                PermissionStepCard(
                  emoji: "🔋",
                  title: "Always Connected",
                  description: "Keep your bond alive in the background — never miss a touch or a call.",
                  isGranted: _perm.isBatteryOptimizationIgnored.value,
                  onTap: _perm.requestBatteryIgnore,
                ),
                const SizedBox(height: 20),

                // ── PAIRING SECTION ──
                const Text(
                  "2. PARTNER PAIRING",
                  style: TextStyle(color: Color(0xFFE05CB0), fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                if (!isPaired) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "Your Username (share with partner)",
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          userInviteCode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  CustomInputField(
                    label: "Enter Partner's Username (optional)",
                    placeholder: "their_username",
                    controller: _codeController,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "You can skip this and connect a partner anytime later from Home.",
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  GradientButton(
                    text: "Connect Partner",
                    isLoading: _pairing,
                    onPressed: _pairing ? () {} : _handlePair,
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.favorite, color: Color(0xFF10B981)),
                        SizedBox(width: 12),
                        Text(
                          "Successfully paired with your partner!",
                          style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 40),

                // ── FINAL ACTION ──
                // Permissions are required; connecting a partner is optional.
                Opacity(
                  opacity: allPermissionsGranted ? 1.0 : 0.4,
                  child: GradientButton(
                    text: isPaired ? "Continue to Home" : "Continue (connect partner later)",
                    onPressed: allPermissionsGranted
                        ? () => Get.offAllNamed('/home')
                        : () {
                            Get.snackbar(
                              "Permissions needed",
                              "Please grant the permissions above to continue.",
                            );
                          },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            );
          }),
        ),
      ),
    );
  }
}
