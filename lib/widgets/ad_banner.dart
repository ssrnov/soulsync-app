import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/controllers.dart';

// In-app ad banner. Shows the admin-chosen ad for this placement:
//   'image' → your uploaded "My Ad" image
//   'html'  → an Adsterra/Monetag WebView banner
// (Start.io was removed.) Shows only when: master ads on + placement on + not premium.
class AdBanner extends StatefulWidget {
  final String placement; // home | games | memories
  final double height;
  const AdBanner(this.placement, {super.key, this.height = 64});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  WebViewController? _web;
  bool _webBuilt = false;
  final RxBool _webFailed = false.obs;

  String get _adUrl {
    var base = (dotenv.env['API_BASE_URL'] ?? '').trim();
    if (base.isEmpty) base = 'https://soulsyncc.site/soulpages/app/';
    if (!base.endsWith('/')) base += '/';
    return '${base}ad.php?p=${widget.placement}';
  }

  void _ensureWeb() {
    if (_webBuilt) return;
    _webBuilt = true;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) => _webFailed.value = true,
        onHttpError: (e) => _webFailed.value = true,
      ))
      ..loadRequest(Uri.parse(_adUrl));
  }

  Widget _shell(Widget child) => Container(
        height: widget.height,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Get.theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF94A3B8).withOpacity(0.15)),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
      );

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();

    // Clean "My Ad" card (uploaded house image). Returns null when none exists.
    Widget? houseCard() {
      final myAd = auth.houseAd(widget.placement);
      final myImg = (myAd?['image'] ?? '').toString();
      if (myImg.isEmpty) return null;
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Get.theme.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF94A3B8).withOpacity(0.15)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
              child: Text("Ad", style: TextStyle(color: const Color(0xFF94A3B8).withOpacity(0.7), fontSize: 9.5, fontWeight: FontWeight.w600)),
            ),
            GestureDetector(
              onTap: () async {
                final link = (myAd?['link'] ?? '').toString();
                if (link.isNotEmpty) {
                  try {
                    final uri = Uri.parse(link);
                    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (_) {}
                }
              },
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                child: Image.network(myImg, fit: BoxFit.fitWidth, width: double.infinity,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ),
          ],
        ),
      );
    }

    return Obx(() {
      if (auth.isPremium) return const SizedBox.shrink();
      final provider = auth.adProvider(widget.placement); // 'image' | 'html' | (other)

      // Admin picked "My Ad (image)" → show the uploaded image.
      if (provider == 'image') {
        if (!auth.showAppAd(widget.placement)) return const SizedBox.shrink();
        return houseCard() ?? const SizedBox.shrink();
      }

      // Network ads respect the master + placement toggle.
      if (!auth.showAppAd(widget.placement)) return const SizedBox.shrink();

      // HTML code (Adsterra/Monetag) → WebView banner.
      if (provider == 'html') {
        if (auth.showAd(widget.placement) && !_webFailed.value) {
          _ensureWeb();
          if (_web != null) return _shell(WebViewWidget(controller: _web!));
        }
        return const SizedBox.shrink();
      }

      // Any other provider: fall back to a My-Ad image if one exists, else nothing.
      return houseCard() ?? const SizedBox.shrink();
    });
  }
}
