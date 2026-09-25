import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/api_service.dart';
import '../services/controllers.dart';
import '../widgets/widgets.dart';
import '../utils/avatar_util.dart';

String soulSyncTermsUrl() {
  var b = dotenv.env['API_BASE_URL'] ?? 'https://soulsyncc.site/soulpages/app/';
  b = b.replaceAll(RegExp(r'app/?$'), '');
  if (!b.endsWith('/')) b += '/';
  return '${b}soulsync-terms.php';
}

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});
  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  late final WebViewController _c;
  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final url = req.url;
          if (url.startsWith('mailto:') || url.startsWith('tel:')) {
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(soulSyncTermsUrl()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Terms & Conditions"),
        backgroundColor: const Color(0xFF0F0B1E),
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Get.back()),
      ),
      body: WebViewWidget(controller: _c),
    );
  }
}

class TermsAgreeRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const TermsAgreeRow({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 26, height: 26,
          child: Checkbox(
            value: value,
            activeColor: const Color(0xFFE05CB0),
            onChanged: (v) => onChanged(v ?? false),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text("I agree to the ", style: TextStyle(color: Colors.white70, fontSize: 13)),
              GestureDetector(
                onTap: () => Get.to(() => const TermsScreen()),
                child: const Text("Terms & Conditions",
                    style: TextStyle(color: Color(0xFFE05CB0), fontSize: 13, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Splash Screen ────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthController _auth = Get.find<AuthController>();
  final PermissionController _perm = Get.find<PermissionController>();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await Future.wait([
        _auth.checkAppConfig().timeout(const Duration(seconds: 6), onTimeout: () {}),
        Future.delayed(const Duration(seconds: 2)),
      ]);
    } catch (_) {}

    // Wait for restoreSession to finish (max 8 more seconds)
    // restoreSession runs from onInit — it might still be in flight
    for (int i = 0; i < 16; i++) {
      if (!_auth.isRestoring.value) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;
    _redirect();
  }

  void _redirect() {
    try {
      if (_auth.isMaintenanceMode.value) {
        Get.offAll(() => const MaintenanceScreen());
        return;
      }
      if (_auth.isUpdateRequired.value) {
        Get.offAll(() => const UpdateRequiredScreen());
        return;
      }
      if (_auth.isLoggedIn.value) {
        Get.offAllNamed(_perm.allGranted ? '/home' : '/wizard');
      } else {
        Get.offAllNamed('/welcome');
      }
    } catch (e) {
      Get.offAllNamed('/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F0B1E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image(image: AssetImage('assets/images/logo.png'), height: 140, width: 140),
            SizedBox(height: 20),
            Text("SoulSync", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28, letterSpacing: 1.5)),
            SizedBox(height: 8),
            Text("Distance Love, Close Hearts.", style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ── Welcome Screen ───────────────────────────────────────────────────────────
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0B1E),
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            const Image(image: AssetImage('assets/images/logo.png'), height: 160, width: 160),
            const SizedBox(height: 30),
            const Text("Sync Your Hearts", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
            const SizedBox(height: 10),
            const Text(
              "Stay connected in real-time, track location, log moods, share memories, and interact with your partner.",
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
            ),
            const Spacer(),
            GradientButton(text: "Get Started", onPressed: () => Get.toNamed('/login')),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Get.toNamed('/signup'),
              child: const Text("Create an Account", style: TextStyle(color: Color(0xFFE05CB0), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── Login Screen ─────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _auth = Get.find<AuthController>();
  bool _agreed = false;
  bool _busy = false;
  String _status = '';

  void _setStatus(String s) { if (mounted) setState(() => _status = s); }

  void _login() async {
    final email = _emailCtl.text.trim();
    final pass = _passCtl.text;
    if (email.isEmpty || pass.isEmpty) { Get.snackbar("Warning", "Please fill in all fields."); return; }
    if (!_agreed) { Get.snackbar("Please agree", "Tick 'I agree to the Terms & Conditions' to continue."); return; }

    setState(() { _busy = true; _status = 'Connecting...'; });
    try {
      final success = await _auth.login(email, pass);
      if (!mounted) return;
      if (success) {
        setState(() => _status = 'Login successful!');
        _navigateHome();
      } else {
        setState(() { _busy = false; _status = ''; });
      }
    } catch (e) {
      if (mounted) setState(() { _busy = false; _status = ''; });
    }
  }

  void _googleLogin() async {
    setState(() { _busy = true; _status = 'Opening Google...'; });
    try {
      final success = await _auth.googleSignIn();
      if (!mounted) return;
      if (success) {
        setState(() => _status = 'Login successful!');
        _navigateHome();
      } else {
        setState(() { _busy = false; _status = ''; });
      }
    } catch (e) {
      if (mounted) setState(() { _busy = false; _status = ''; });
    }
  }

  void _navigateHome() {
    try {
      final perm = Get.find<PermissionController>();
      perm.checkAllPermissions().then((_) {
        Get.offAllNamed(perm.allGranted ? '/home' : '/wizard');
      }).catchError((_) {
        Get.offAllNamed('/wizard');
      });
    } catch (_) {
      Get.offAllNamed('/wizard');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0B1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Get.back()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text("Welcome Back", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 26)),
            const SizedBox(height: 8),
            const Text("Sign in to reconnect with your partner.", style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 40),
            CustomInputField(label: "Email Address", placeholder: "partner@gmail.com", controller: _emailCtl, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 20),
            CustomInputField(label: "Password", placeholder: "••••••••", controller: _passCtl, isPassword: true),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: GestureDetector(
                  onTap: () => Get.toNamed('/forgot-password'),
                  child: const Text("Forgot Password?", style: TextStyle(color: Color(0xFFE05CB0), fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TermsAgreeRow(value: _agreed, onChanged: (v) => setState(() => _agreed = v)),
            const SizedBox(height: 18),
            GradientButton(text: "Sign In", isLoading: _busy, onPressed: _busy ? () {} : _login),
            const SizedBox(height: 16),

            // Google sign-in
            Row(children: [
              Expanded(child: Divider(color: Colors.white24, thickness: 0.5)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text("or", style: TextStyle(color: Colors.white38, fontSize: 13))),
              Expanded(child: Divider(color: Colors.white24, thickness: 0.5)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 52,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _googleLogin,
                icon: _busy && _status.contains('Google')
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
                    : const Text("G", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'sans-serif')),
                label: Text(_status.isNotEmpty ? _status : "Continue with Google",
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  backgroundColor: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Signup Screen ────────────────────────────────────────────────────────────
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameCtl = TextEditingController();
  final _usernameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _auth = Get.find<AuthController>();
  bool _agreed = false;
  bool _busy = false;
  String _gender = 'female';
  int _charIndex = 0;

  List<String> get _chars => _gender == 'male' ? kBoyChars : kGirlChars;

  void _signup() async {
    final name = _nameCtl.text.trim();
    final username = _usernameCtl.text.trim();
    final email = _emailCtl.text.trim();
    final pass = _passCtl.text;

    if (name.isEmpty || username.isEmpty || email.isEmpty || pass.isEmpty) { Get.snackbar("Warning", "Please fill in all fields."); return; }
    if (!_agreed) { Get.snackbar("Please agree", "Tick 'I agree to the Terms & Conditions' to continue."); return; }

    setState(() => _busy = true);
    try {
      final success = await _auth.register(username, email, pass, name: name, gender: _gender).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (success) {
        final c = kCharColors[_charIndex % kCharColors.length];
        await uploadCharacterAvatar(_chars[_charIndex], c[0], c[1]);
        Get.offAllNamed('/wizard');
      } else {
        setState(() => _busy = false);
      }
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      Get.snackbar("Error", "Signup failed. Try again.", backgroundColor: Colors.red.withOpacity(0.8), colorText: Colors.white);
    }
  }

  void _googleSignup() async {
    setState(() => _busy = true);
    try {
      final success = await _auth.googleSignIn().timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (success) {
        Get.offAllNamed('/wizard');
      } else {
        setState(() => _busy = false);
      }
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      Get.snackbar("Error", "Google sign-in failed.", backgroundColor: Colors.red.withOpacity(0.8), colorText: Colors.white);
    }
  }

  Widget _genderChip(String value, String label, String emoji) {
    final active = _gender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _gender = value; _charIndex = 0; }),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: active ? const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]) : null,
            color: active ? null : Colors.white10,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? Colors.transparent : Colors.white24),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: active ? Colors.white : Colors.white70, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }

  Widget _characterStrip() {
    return SizedBox(
      height: 74,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _chars.length,
        itemBuilder: (_, i) {
          final c = kCharColors[i % kCharColors.length];
          final active = i == _charIndex;
          return GestureDetector(
            onTap: () => setState(() => _charIndex = i),
            child: Container(
              width: 60, height: 60,
              margin: const EdgeInsets.only(right: 10, top: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c[0], c[1]]),
                shape: BoxShape.circle,
                border: Border.all(color: active ? Colors.white : Colors.transparent, width: 3),
                boxShadow: active ? [BoxShadow(color: c[0].withOpacity(0.6), blurRadius: 10)] : null,
              ),
              alignment: Alignment.center,
              child: Text(_chars[i], style: const TextStyle(fontSize: 28)),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0B1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Get.back()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text("Create Account", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 26)),
            const SizedBox(height: 8),
            const Text("Start your joint sync journey today.", style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 40),
            CustomInputField(label: "Your Name", placeholder: "Sneha", controller: _nameCtl),
            const SizedBox(height: 20),
            CustomInputField(label: "Username", placeholder: "sneha_raj", controller: _usernameCtl),
            const SizedBox(height: 20),
            CustomInputField(label: "Email Address", placeholder: "sneha@gmail.com", controller: _emailCtl, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 20),
            CustomInputField(label: "Password", placeholder: "••••••••", controller: _passCtl, isPassword: true),
            const SizedBox(height: 24),
            const Text("I am a", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [_genderChip('female', "Woman", "👩"), _genderChip('male', "Man", "👨")]),
            const SizedBox(height: 16),
            const Text("Choose your character", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            _characterStrip(),
            const SizedBox(height: 22),
            TermsAgreeRow(value: _agreed, onChanged: (v) => setState(() => _agreed = v)),
            const SizedBox(height: 18),
            GradientButton(text: "Sign Up", isLoading: _busy, onPressed: _busy ? () {} : _signup),
            const SizedBox(height: 16),
            // Google
            Row(children: [
              Expanded(child: Divider(color: Colors.white24, thickness: 0.5)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text("or", style: TextStyle(color: Colors.white38, fontSize: 13))),
              Expanded(child: Divider(color: Colors.white24, thickness: 0.5)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 52,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _googleSignup,
                icon: const Text("G", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'sans-serif')),
                label: const Text("Continue with Google", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  backgroundColor: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Forgot Password Screen ───────────────────────────────────────────────────
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _passCtl = TextEditingController();
  final _confirmCtl = TextEditingController();
  final _auth = Get.find<AuthController>();
  bool _verified = false;
  bool _busy = false;

  void _setPassword() async {
    final pass = _passCtl.text;
    final confirm = _confirmCtl.text;
    if (pass.length < 6) { Get.snackbar("Warning", "Password must be at least 6 characters."); return; }
    if (pass != confirm) { Get.snackbar("Warning", "Passwords do not match."); return; }

    setState(() => _busy = true);
    try {
      final success = await _auth.setPasswordViaGoogle(pass).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (success) {
        Get.offAllNamed('/login');
        Get.snackbar("Success", "Password changed! Login with your new password.");
      } else {
        setState(() => _busy = false);
      }
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      Get.snackbar("Error", "Failed to set password.", backgroundColor: Colors.red.withOpacity(0.8), colorText: Colors.white);
    }
  }

  void _verifyGoogle() async {
    setState(() => _busy = true);
    try {
      final success = await _auth.googleSignIn().timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (success) {
        setState(() { _verified = true; _busy = false; });
      } else {
        setState(() => _busy = false);
      }
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      Get.snackbar("Error", "Google verification failed.", backgroundColor: Colors.red.withOpacity(0.8), colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0B1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Get.back()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFE8467C)]),
                boxShadow: [BoxShadow(color: const Color(0xFFE8467C).withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 46),
            ),
            const SizedBox(height: 26),
            const Text("Forgot Password?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 26)),
            const SizedBox(height: 10),
            Text(
              _verified ? "Identity verified! Set your new password below."
                        : "Sign in with Google to verify your identity,\nthen set a new password.",
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 34),
            if (!_verified) ...[
              // Google verify button
              Row(children: [
                Expanded(child: Divider(color: Colors.white24, thickness: 0.5)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text("or", style: TextStyle(color: Colors.white38, fontSize: 13))),
                Expanded(child: Divider(color: Colors.white24, thickness: 0.5)),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity, height: 52,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _verifyGoogle,
                  icon: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
                      : const Text("G", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'sans-serif')),
                  label: Text(_busy ? "Verifying..." : "Continue with Google",
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    backgroundColor: Colors.white.withOpacity(0.06),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (_verified)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.25)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 18),
                        const SizedBox(width: 8),
                        Text("Verified as ${_auth.currentUser.value?.email ?? ''}", style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 12)),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    CustomInputField(label: "New Password", placeholder: "Min 6 characters", controller: _passCtl, isPassword: true),
                    const SizedBox(height: 16),
                    CustomInputField(label: "Confirm Password", placeholder: "Re-enter password", controller: _confirmCtl, isPassword: true),
                    const SizedBox(height: 22),
                    GradientButton(text: "Set New Password", isLoading: _busy, onPressed: _busy ? () {} : _setPassword),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Get.back(),
              child: const Text("← Back to Login", style: TextStyle(color: Color(0xFFE05CB0), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class ResetPasswordScreen extends StatelessWidget {
  const ResetPasswordScreen({super.key});
  @override
  Widget build(BuildContext context) => const ForgotPasswordScreen();
}

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F0B1E),
      body: Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("🛠️", style: TextStyle(fontSize: 64)),
              SizedBox(height: 24),
              Text("Under Maintenance", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 1.2)),
              SizedBox(height: 12),
              Text(
                "SoulSync is currently undergoing scheduled maintenance to improve your experience. We will be back online shortly. Thank you for your patience! 💖",
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0B1E),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("🚀", style: TextStyle(fontSize: 64)),
              const SizedBox(height: 24),
              const Text("Update Required", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 1.2)),
              const SizedBox(height: 12),
              Obx(() {
                final auth = Get.find<AuthController>();
                final msg = auth.updateMessage.value.isNotEmpty
                    ? auth.updateMessage.value
                    : "A new version of SoulSync is available. Please update to continue syncing with your partner! 💖";
                return Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.5));
              }),
              const SizedBox(height: 32),
              GradientButton(
                text: "Update Now",
                onPressed: () async {
                  final auth = Get.find<AuthController>();
                  final url = auth.updateApkUrl.value;
                  if (url.isEmpty) { Get.snackbar("Update", "Update link not available yet."); return; }
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  else Get.snackbar("Error", "Could not open the download link.");
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
