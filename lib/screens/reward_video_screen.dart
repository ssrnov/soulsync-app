import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

// Plays a self-hosted reward video (uploaded in admin → My Ads → Reward Video).
// The reward unlocks after the user watches ~10 seconds (or the whole clip if
// it's shorter). Returns `true` if the watch requirement was met.
class RewardVideoScreen extends StatefulWidget {
  final String url;
  final int rewardAfterSeconds;
  const RewardVideoScreen({super.key, required this.url, this.rewardAfterSeconds = 10});

  @override
  State<RewardVideoScreen> createState() => _RewardVideoScreenState();
}

class _RewardVideoScreenState extends State<RewardVideoScreen> {
  VideoPlayerController? _c;
  Timer? _timer;
  int _watched = 0;
  bool _ready = false;
  bool _earned = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _c!.initialize();
      await _c!.setLooping(false);
      await _c!.play();
      if (mounted) setState(() => _ready = true);
      // Count only while the video is actually playing.
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_c != null && _c!.value.isPlaying) {
          _watched++;
          final target = widget.rewardAfterSeconds;
          final dur = _c!.value.duration.inSeconds;
          if (!_earned && (_watched >= target || (dur > 0 && _watched >= dur))) {
            setState(() => _earned = true);
          }
          if (mounted) setState(() {});
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (widget.rewardAfterSeconds - _watched).clamp(0, widget.rewardAfterSeconds);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: _error
                ? const Text("Couldn't load the video.", style: TextStyle(color: Colors.white70))
                : _ready && _c != null
                    ? AspectRatio(aspectRatio: _c!.value.aspectRatio, child: VideoPlayer(_c!))
                    : const CircularProgressIndicator(color: Color(0xFFE8467C)),
          ),
          // Top-right: countdown or close-with-reward.
          Positioned(
            top: 12, right: 12,
            child: _earned || _error
                ? ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
                    onPressed: () => Get.back(result: _earned),
                    icon: const Icon(Icons.check, color: Colors.white, size: 18),
                    label: Text(_earned ? "Claim reward" : "Close", style: const TextStyle(color: Colors.white)),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    child: Text("Reward in ${remaining}s", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
          ),
          if (_earned)
            const Positioned(bottom: 24, left: 0, right: 0,
              child: Text("🎁 Reward unlocked! Tap Claim.", textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }
}
