import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// A fully-working-looking Clock app that doubles as the app's disguise/lock
// screen. Setting an "alarm" to the secret time (HHMM) opens the real app.
// Alarm / World Clock / Stopwatch / Timer all function like a real clock.
class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key});
  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen> {
  final _storage = const FlutterSecureStorage();
  Timer? _tick;
  DateTime _now = DateTime.now();
  int _tab = 0;
  final List<String> _alarms = []; // "HH:MM" fake alarms the user sets

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _now = DateTime.now()); });
  }

  @override
  void dispose() { _tick?.cancel(); super.dispose(); }

  static String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _openAlarmEntry() async {
    final c = TextEditingController();
    Get.dialog(AlertDialog(
      backgroundColor: const Color(0xFF1B1E27),
      title: const Text("Add alarm", style: TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Enter time (24h, HHMM)", style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 10),
        TextField(
          controller: c, keyboardType: TextInputType.number, maxLength: 4, autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 4),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(counterText: "", hintText: "0730", hintStyle: TextStyle(color: Colors.white24)),
          onChanged: (v) async {
            if (v.length == 4) {
              final pin = await _storage.read(key: 'disguise_pin');
              if (pin != null && v == pin) { Get.offAllNamed('/'); }
            }
          },
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4DA3FF)),
          onPressed: () async {
            final v = c.text.trim();
            final pin = await _storage.read(key: 'disguise_pin');
            if (pin != null && v == pin) { Get.offAllNamed('/'); return; }
            Get.back();
            if (v.length == 4) {
              final t = "${v.substring(0, 2)}:${v.substring(2)}";
              setState(() => _alarms.add(t));
              Get.snackbar("Alarm set", "Alarm for $t",
                  backgroundColor: const Color(0xFF2A2E3A), colorText: Colors.white);
            }
          },
          child: const Text("Save")),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14), elevation: 0,
        title: const Text("Clock", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        centerTitle: false,
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: Icon(Icons.more_vert, color: Colors.white54))],
      ),
      body: IndexedStack(index: _tab, children: [
        _alarmTab(),
        _worldTab(),
        const _StopwatchTab(),
        const _TimerTab(),
      ]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) { HapticFeedback.selectionClick(); setState(() => _tab = i); },
        backgroundColor: const Color(0xFF11141C),
        selectedItemColor: const Color(0xFF4DA3FF),
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.alarm), label: 'Alarm'),
          BottomNavigationBarItem(icon: Icon(Icons.public), label: 'Clock'),
          BottomNavigationBarItem(icon: Icon(Icons.timer_outlined), label: 'Stopwatch'),
          BottomNavigationBarItem(icon: Icon(Icons.hourglass_empty), label: 'Timer'),
        ],
      ),
      floatingActionButton: _tab == 0 ? FloatingActionButton(
        backgroundColor: const Color(0xFF4DA3FF),
        onPressed: () { HapticFeedback.selectionClick(); _openAlarmEntry(); },
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }

  Widget _alarmTab() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = "${days[_now.weekday - 1]}, ${_now.day} ${months[_now.month - 1]}";
    return Column(children: [
      const SizedBox(height: 30),
      Text("${_two(_now.hour)}:${_two(_now.minute)}",
          style: const TextStyle(color: Colors.white, fontSize: 80, fontWeight: FontWeight.w300, letterSpacing: 2)),
      Text(":${_two(_now.second)}", style: const TextStyle(color: Color(0xFF4DA3FF), fontSize: 20, fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      Text(dateStr, style: const TextStyle(color: Colors.white54, fontSize: 15)),
      const SizedBox(height: 24),
      const Align(alignment: Alignment.centerLeft, child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 0, 8),
        child: Text("Alarms", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)))),
      Expanded(child: _alarms.isEmpty
          ? const Center(child: Text("No alarms yet", style: TextStyle(color: Colors.white30)))
          : ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: _alarms.map((a) => Container(
              margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF161A24), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Text(a, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w400)),
                const Spacer(),
                Switch(value: true, activeColor: const Color(0xFF4DA3FF), onChanged: (_) {}),
              ]))).toList())),
    ]);
  }

  Widget _worldTab() {
    // City name → fixed UTC offset (hours). Not DST-precise, just looks real.
    const cities = [
      ['Los Angeles', -7.0], ['New York', -4.0], ['London', 1.0],
      ['Dubai', 4.0], ['India', 5.5], ['Tokyo', 9.0], ['Sydney', 10.0],
    ];
    final utc = _now.toUtc();
    return ListView(padding: const EdgeInsets.all(16), children: cities.map((ci) {
      final off = ci[1] as double;
      final t = utc.add(Duration(minutes: (off * 60).round()));
      final diff = off - (_now.timeZoneOffset.inMinutes / 60.0);
      final diffStr = diff == 0 ? 'Same as local' : '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(diff % 1 == 0 ? 0 : 1)}h';
      return Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF161A24), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ci[0] as String, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
            Text(diffStr, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
          const Spacer(),
          Text("${_two(t.hour)}:${_two(t.minute)}", style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w300)),
        ]),
      );
    }).toList());
  }
}

// ── Working Stopwatch ──────────────────────────────────────────────────────
class _StopwatchTab extends StatefulWidget {
  const _StopwatchTab();
  @override
  State<_StopwatchTab> createState() => _StopwatchTabState();
}

class _StopwatchTabState extends State<_StopwatchTab> {
  final Stopwatch _sw = Stopwatch();
  Timer? _t;
  final List<Duration> _laps = [];

  void _refresh() { _t?.cancel(); _t = Timer.periodic(const Duration(milliseconds: 33), (_) { if (mounted) setState(() {}); }); }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  static String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final cs = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return "$mm:$ss.$cs";
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 60),
      Text(_fmt(_sw.elapsed), style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w200, letterSpacing: 2)),
      const SizedBox(height: 40),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _cbtn(_sw.isRunning ? "Lap" : "Reset", const Color(0xFF2A2E3A), () {
          setState(() { if (_sw.isRunning) { _laps.insert(0, _sw.elapsed); } else { _sw.reset(); _laps.clear(); } });
        }),
        _cbtn(_sw.isRunning ? "Stop" : "Start", _sw.isRunning ? const Color(0xFFEF4444) : const Color(0xFF10B981), () {
          setState(() { if (_sw.isRunning) { _sw.stop(); _t?.cancel(); } else { _sw.start(); _refresh(); } });
        }),
      ]),
      const SizedBox(height: 20),
      Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 24), children: [
        for (int i = 0; i < _laps.length; i++) Padding(padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Text("Lap ${_laps.length - i}", style: const TextStyle(color: Colors.white54)),
            const Spacer(),
            Text(_fmt(_laps[i]), style: const TextStyle(color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
          ])),
      ])),
    ]);
  }

  Widget _cbtn(String t, Color c, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(
    width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: c),
    alignment: Alignment.center, child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))));
}

// ── Working Timer (countdown) ──────────────────────────────────────────────
class _TimerTab extends StatefulWidget {
  const _TimerTab();
  @override
  State<_TimerTab> createState() => _TimerTabState();
}

class _TimerTabState extends State<_TimerTab> {
  int _totalSec = 300; // default 5 min
  int _remaining = 300;
  Timer? _t;
  bool _running = false;

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  void _start() {
    _t?.cancel();
    setState(() => _running = true);
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 0) { _t?.cancel(); setState(() { _running = false; }); return; }
      setState(() => _remaining--);
    });
  }

  static String _fmt(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return h > 0 ? "${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}"
                 : "${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 70),
      Text(_fmt(_remaining), style: const TextStyle(color: Colors.white, fontSize: 66, fontWeight: FontWeight.w200, letterSpacing: 2)),
      const SizedBox(height: 30),
      if (!_running) Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final m in [1, 5, 10, 30]) Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: () => setState(() { _totalSec = m * 60; _remaining = m * 60; }),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF161A24), borderRadius: BorderRadius.circular(20)),
              child: Text("${m}m", style: const TextStyle(color: Colors.white70))))),
      ]),
      const SizedBox(height: 30),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _cbtn("Reset", const Color(0xFF2A2E3A), () { _t?.cancel(); setState(() { _remaining = _totalSec; _running = false; }); }),
        _cbtn(_running ? "Pause" : "Start", _running ? const Color(0xFFF59E0B) : const Color(0xFF10B981), () {
          if (_running) { _t?.cancel(); setState(() => _running = false); } else { _start(); }
        }),
      ]),
    ]);
  }

  Widget _cbtn(String t, Color c, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(
    width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: c),
    alignment: Alignment.center, child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))));
}
