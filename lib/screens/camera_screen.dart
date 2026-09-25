import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../services/controllers.dart';

// ── In-app camera ────────────────────────────────────────────────────────────
// Tap the shutter for a photo, hold it to record a video. After capture the user
// reviews it and chooses Send, Send as view-once, or Retake.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _camIndex = 0;
  FlashMode _flash = FlashMode.off;
  bool _recording = false;
  bool _busy = false;
  Timer? _recTimer;
  int _recSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  Future<void> _setup() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      // Prefer the back camera to start.
      _camIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_camIndex < 0) _camIndex = 0;
      await _start(_camIndex);
    } catch (e) {
      Get.snackbar("Camera", "Couldn't open the camera.");
    }
  }

  Future<void> _start(int i) async {
    // Dispose the old controller FIRST (a device can't hold two open cameras),
    // then open the new one — this is what makes front/back switch reliably.
    final old = _controller;
    _controller = null;
    if (mounted) setState(() {}); // show loader while switching
    try { await old?.dispose(); } catch (_) {}
    final c = CameraController(_cameras[i], ResolutionPreset.high, enableAudio: true);
    try {
      await c.initialize();
      try { await c.setFlashMode(_flash); } catch (_) {}
    } catch (_) {}
    _controller = c;
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _start(_camIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null) return;
    _flash = _flash == FlashMode.off
        ? FlashMode.auto
        : _flash == FlashMode.auto
            ? FlashMode.always
            : FlashMode.off;
    try { await c.setFlashMode(_flash); } catch (_) {}
    setState(() {});
  }

  IconData get _flashIcon => _flash == FlashMode.off
      ? Icons.flash_off
      : _flash == FlashMode.auto
          ? Icons.flash_auto
          : Icons.flash_on;

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _recording) return;
    // Toggle to the OPPOSITE lens (front ↔ back), not just the next index — some
    // phones list several back cameras, so index-cycling could stay on the back.
    final current = _cameras[_camIndex].lensDirection;
    final target = current == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    int idx = _cameras.indexWhere((c) => c.lensDirection == target);
    if (idx < 0) idx = (_camIndex + 1) % _cameras.length;
    _camIndex = idx;
    await _start(_camIndex);
  }

  Future<void> _takePhoto() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy || _recording) return;
    setState(() => _busy = true);
    try {
      final XFile f = await c.takePicture();
      if (mounted) {
        await Get.to(() => CameraReviewScreen(path: f.path, isVideo: false));
      }
    } catch (_) {
      Get.snackbar("Camera", "Couldn't take the photo.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startRecording() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _recording) return;
    try {
      await c.startVideoRecording();
      _recSeconds = 0;
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _recSeconds++));
      setState(() => _recording = true);
    } catch (_) {}
  }

  Future<void> _stopRecording() async {
    final c = _controller;
    if (c == null || !_recording) return;
    _recTimer?.cancel();
    try {
      final XFile f = await c.stopVideoRecording();
      setState(() => _recording = false);
      if (mounted) {
        await Get.to(() => CameraReviewScreen(path: f.path, isVideo: true));
      }
    } catch (_) {
      setState(() => _recording = false);
    }
  }

  String get _recLabel {
    final m = (_recSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_recSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Live preview (fills the screen).
          if (ready)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.previewSize?.height ?? 1,
                  height: c.value.previewSize?.width ?? 1,
                  child: CameraPreview(c),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Top bar: close + flash + recording timer.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Get.back(),
                  ),
                  const Spacer(),
                  if (_recording)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                      child: Row(children: [
                        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(_recLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(_flashIcon, color: Colors.white, size: 26),
                    onPressed: _recording ? null : _toggleFlash,
                  ),
                ],
              ),
            ),
          ),

          // Bottom controls: shutter (tap=photo, hold=video) + switch camera.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _recording ? "Release to stop" : "Tap for photo • Hold for video",
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        const SizedBox(width: 56),
                        // Shutter button.
                        GestureDetector(
                          onTap: _takePhoto,
                          onLongPressStart: (_) => _startRecording(),
                          onLongPressEnd: (_) => _stopRecording(),
                          child: Container(
                            width: 78, height: 78,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _recording ? Colors.red : Colors.white, width: 5),
                            ),
                            child: Center(
                              child: Container(
                                width: _recording ? 30 : 60,
                                height: _recording ? 30 : 60,
                                decoration: BoxDecoration(
                                  color: _recording ? Colors.red : Colors.white,
                                  borderRadius: BorderRadius.circular(_recording ? 8 : 40),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Switch camera.
                        SizedBox(
                          width: 56,
                          child: IconButton(
                            icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white, size: 30),
                            onPressed: _switchCamera,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Review + send ────────────────────────────────────────────────────────────
class CameraReviewScreen extends StatefulWidget {
  final String path;
  final bool isVideo;
  const CameraReviewScreen({super.key, required this.path, required this.isVideo});
  @override
  State<CameraReviewScreen> createState() => _CameraReviewScreenState();
}

class _CameraReviewScreenState extends State<CameraReviewScreen> {
  final ChatController _chat = Get.find<ChatController>();
  VideoPlayerController? _video;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _video = VideoPlayerController.file(File(widget.path))
        ..initialize().then((_) {
          _video?..setLooping(true)..play();
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<List<int>?> _toWebp(String path) async {
    try {
      final out = await FlutterImageCompress.compressWithFile(
        path, format: CompressFormat.webp, quality: 55, minWidth: 1280, minHeight: 1280,
      );
      if (out != null) return out;
    } catch (_) {}
    try { return await File(path).readAsBytes(); } catch (_) { return null; }
  }

  Future<void> _send({required bool viewOnce}) async {
    if (_sending) return;
    setState(() => _sending = true);
    bool ok = false;
    if (widget.isVideo) {
      ok = await _chat.uploadVideoAndSend(widget.path, viewOnce: viewOnce);
    } else {
      final bytes = await _toWebp(widget.path);
      if (bytes != null) {
        ok = viewOnce
            ? await _chat.uploadBytesAndSendViewOnce(bytes)
            : await _chat.uploadBytesAndSend(bytes);
      }
    }
    if (!ok) {
      Get.snackbar("Send failed", "Couldn't send. Check your connection.");
      if (mounted) setState(() => _sending = false);
      return;
    }
    // Pop review + camera → back to the chat.
    Get.back();
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Preview.
          Positioned.fill(
            child: widget.isVideo
                ? (_video != null && _video!.value.isInitialized
                    ? Center(child: AspectRatio(aspectRatio: _video!.value.aspectRatio, child: VideoPlayer(_video!)))
                    : const Center(child: CircularProgressIndicator(color: Colors.white)))
                : Center(child: Image.file(File(widget.path), fit: BoxFit.contain)),
          ),

          // Close / retake.
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                onPressed: _sending ? null : () => Get.back(), // back to camera
              ),
            ),
          ),

          // Bottom action bar: Send + View once.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Row(
                  children: [
                    // View once.
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _sending ? null : () => _send(viewOnce: true),
                        icon: const Icon(Icons.timer_outlined, color: Colors.white),
                        label: const Text("View once", style: TextStyle(color: Colors.white)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Normal send.
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _sending ? null : () => _send(viewOnce: false),
                        icon: const Icon(Icons.send_rounded, color: Colors.white),
                        label: const Text("Send", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8467C),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_sending)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C))),
            ),
        ],
      ),
    );
  }
}
