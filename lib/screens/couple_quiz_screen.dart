import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';

// ── Couple Quiz: partner vs partner, both answer the same questions ──────────
class CoupleQuizScreen extends StatefulWidget {
  const CoupleQuizScreen({super.key});
  @override
  State<CoupleQuizScreen> createState() => _CoupleQuizScreenState();
}

class _CoupleQuizScreenState extends State<CoupleQuizScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic> _state = {'active': false};
  bool _loading = true;
  bool _wasActive = false;
  bool _showResult = false;
  Map<String, dynamic> _result = {};
  Timer? _poll;
  Timer? _qTimer;
  int _secondsLeft = 20;
  int _timedIndex = -1;
  String _category = 'random';

  static const _cats = [
    ['random', 'Random', '🎲'], ['love', 'Love', '❤️'], ['romantic', 'Romantic', '🥰'],
    ['food', 'Food', '🍕'], ['travel', 'Travel', '✈️'], ['habits', 'Habits', '😴'],
    ['movies', 'Movies', '🎬'], ['music', 'Music', '🎵'], ['future', 'Future', '🌟'],
    ['funny', 'Funny', '😂'], ['deep', 'Deep Talk', '💭'],
  ];

  @override
  void initState() {
    super.initState();
    _refresh(initial: true);
    _poll = Timer.periodic(const Duration(milliseconds: 1200), (_) => _refresh());
  }

  @override
  void dispose() { _poll?.cancel(); _qTimer?.cancel(); super.dispose(); }

  Future<Map<String, dynamic>> _get(String path) async {
    try { final r = await _api.get(path).timeout(const Duration(seconds: 8)); return Map<String, dynamic>.from(r.data['data'] ?? {}); }
    catch (_) { return {}; }
  }
  Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? d]) async {
    try { final r = await _api.post(path, data: d ?? {}).timeout(const Duration(seconds: 8)); return Map<String, dynamic>.from(r.data['data'] ?? {}); }
    catch (_) { return {}; }
  }

  Future<void> _refresh({bool initial = false}) async {
    final s = await _get('/quiz/state');
    if (!mounted) return;
    if (s['active'] == true) {
      setState(() { _state = s; _showResult = false; _wasActive = true; _loading = false; });
      _syncQuestionTimer();
    } else {
      if (_wasActive) {
        final r = await _get('/quiz/result');
        if (['finished', 'stopped'].contains(r['status'])) {
          setState(() { _result = r; _showResult = true; });
        }
        _wasActive = false;
      }
      setState(() { _state = s; _loading = false; });
    }
  }

  // Start a fresh 20s timer whenever a new question appears and I haven't answered.
  void _syncQuestionTimer() {
    final idx = _state['index'] ?? -1;
    final answered = _state['myAnswer'] != null;
    final revealed = _state['revealed'] == true;
    if (answered || revealed || _state['status'] != 'active') { _qTimer?.cancel(); return; }
    if (idx != _timedIndex) {
      _timedIndex = idx;
      _secondsLeft = 20;
      _qTimer?.cancel();
      _qTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        setState(() => _secondsLeft--);
        if (_secondsLeft <= 0) { t.cancel(); _answer('(no answer)'); }
      });
    }
  }

  Future<void> _start() async {
    setState(() => _loading = true);
    final s = await _post('/quiz/start', {'category': _category});
    if (!mounted) return;
    setState(() { _state = s; _wasActive = s['active'] == true; _showResult = false; _loading = false; });
    _syncQuestionTimer();
  }

  Future<void> _answer(String opt) async {
    _qTimer?.cancel();
    final s = await _post('/quiz/answer', {'answer': opt});
    if (mounted && s.isNotEmpty) setState(() => _state = s);
  }

  Future<void> _next() async {
    final s = await _post('/quiz/next', {'fromIndex': _state['index'] ?? 0});
    if (!mounted) return;
    if (s['status'] == 'finished') { final r = await _get('/quiz/result'); setState(() { _result = r; _showResult = true; _wasActive = false; }); }
    else { setState(() => _state = s); _syncQuestionTimer(); }
  }

  Future<void> _stop() async {
    final ok = await Get.dialog<bool>(AlertDialog(
      title: const Text("Stop Couple Quiz?"),
      actions: [
        TextButton(onPressed: () => Get.back(result: false), child: const Text("No")),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
          onPressed: () => Get.back(result: true), child: const Text("Yes", style: TextStyle(color: Colors.white))),
      ],
    ));
    if (ok == true) { await _post('/quiz/stop'); final r = await _get('/quiz/result'); if (mounted) setState(() { _result = r; _showResult = true; _wasActive = false; }); }
  }

  Future<void> _pauseResume() async {
    if (_state['status'] == 'paused') { await _post('/quiz/resume'); } else { await _post('/quiz/pause'); }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final on = Get.theme.colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0, foregroundColor: on,
        title: const Text("Couple Quiz 🎮", style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_state['active'] == true && !_showResult)
            PopupMenuButton<String>(
              onSelected: (v) { if (v == 'stop') _stop(); else _pauseResume(); },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'pause', child: Text(_state['status'] == 'paused' ? "Resume Game" : "Pause Game")),
                const PopupMenuItem(value: 'stop', child: Text("Stop Game")),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
          : _showResult
              ? _resultView(on)
              : (_state['active'] != true)
                  ? _setupView(on)
                  : _state['status'] == 'paused'
                      ? _pausedView(on)
                      : _gameView(on),
    );
  }

  Widget _setupView(Color on) => ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 10),
        Center(child: Column(children: [
          const Text("🎮", style: TextStyle(fontSize: 56)),
          const SizedBox(height: 8),
          Text("Couple Quiz", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: on)),
          const SizedBox(height: 4),
          const Text("Both answer the same questions — matching answers build your bond ❤️",
              textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
        ])),
        const SizedBox(height: 24),
        Text("Pick a category", style: TextStyle(fontWeight: FontWeight.w700, color: on)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: _cats.map((c) {
          final sel = _category == c[0];
          return GestureDetector(
            onTap: () => setState(() => _category = c[0]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFFE8467C) : Get.theme.cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? Colors.transparent : const Color(0xFF94A3B8).withOpacity(.25))),
              child: Text("${c[2]} ${c[1]}", style: TextStyle(color: sel ? Colors.white : on, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          );
        }).toList()),
        const SizedBox(height: 28),
        SizedBox(width: double.infinity, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C), padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: _start,
          child: const Text("Create & Invite Partner ▶", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: () { setState(() => _category = 'daily'); _start(); },
          icon: const Text("🗓️"), label: const Text("Play Today's Daily Quiz"))),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => Get.to(() => const CustomQuestionScreen()),
            icon: const Text("✍️"), label: const Text("Custom"))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: () => Get.to(() => const AchievementsScreen()),
            icon: const Text("🏆"), label: const Text("Awards"))),
        ]),
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: () => Get.to(() => const QuizHistoryScreen()), child: const Text("View History"))),
      ]);

  Widget _pausedView(Color on) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("⏸️", style: TextStyle(fontSize: 50)),
        const SizedBox(height: 10),
        Text("Quiz paused", style: TextStyle(fontWeight: FontWeight.bold, color: on, fontSize: 16)),
        Text("Resume from question ${(_state['index'] ?? 0) + 1}/${_state['total'] ?? 0}",
            style: const TextStyle(color: Color(0xFF94A3B8))),
        const SizedBox(height: 16),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
          onPressed: _pauseResume, child: const Text("Resume", style: TextStyle(color: Colors.white))),
      ]));

  Widget _gameView(Color on) {
    final q = _state['question'] as Map<String, dynamic>?;
    if (q == null) return const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)));
    final options = (q['options'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final idx = (_state['index'] ?? 0) as int;
    final total = (_state['total'] ?? 0) as int;
    final myAns = _state['myAnswer'] as String?;
    final revealed = _state['revealed'] == true;
    final matched = _state['matched'] == true;
    final partnerAns = _state['partnerAnswer'] as String?;

    return ListView(padding: const EdgeInsets.all(20), children: [
      // Score + progress header
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text("Q ${idx + 1}/$total", style: TextStyle(fontWeight: FontWeight.w800, color: on, fontSize: 16)),
        Text("${_state['matches'] ?? 0}/${total}  ·  ${_state['percent'] ?? 0}%", style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      LinearProgressIndicator(value: total > 0 ? (idx) / total : 0, color: const Color(0xFFE8467C), backgroundColor: const Color(0x22E8467C)),
      const SizedBox(height: 20),
      // Question card
      Container(
        width: double.infinity, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]), borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          if (!revealed && myAns == null)
            Align(alignment: Alignment.centerRight, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20)),
              child: Text("$_secondsLeft s", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
          const SizedBox(height: 6),
          Text(q['question'] ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
        ]),
      ),
      const SizedBox(height: 20),
      // Options
      ...options.map((opt) {
        final iPicked = myAns == opt;
        Color bg = Get.theme.cardColor; Color bd = const Color(0x3394A3B8); Widget? tr;
        if (revealed) {
          final partnerPicked = partnerAns == opt;
          if (iPicked && matched) { bg = const Color(0x2210B981); bd = const Color(0xFF10B981); tr = const Icon(Icons.check_circle, color: Color(0xFF10B981)); }
          else if (iPicked) { bg = const Color(0x22EF4444); bd = const Color(0xFFEF4444); tr = const Text("You"); }
          else if (partnerPicked) { bg = const Color(0x22E8467C); bd = const Color(0xFFE8467C); tr = const Text("Partner"); }
        } else if (iPicked) { bg = const Color(0x22E8467C); bd = const Color(0xFFE8467C); tr = const Icon(Icons.check, color: Color(0xFFE8467C)); }
        return Padding(padding: const EdgeInsets.only(bottom: 10), child: GestureDetector(
          onTap: (myAns == null && !revealed) ? () => _answer(opt) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: bd, width: 1.5)),
            child: Row(children: [
              Expanded(child: Text(opt, style: TextStyle(color: on, fontWeight: FontWeight.w600, fontSize: 15))),
              if (tr != null) DefaultTextStyle(style: const TextStyle(color: Color(0xFFE8467C), fontSize: 12, fontWeight: FontWeight.bold), child: tr),
            ]),
          ),
        ));
      }),
      const SizedBox(height: 8),
      if (myAns != null && !revealed)
        const Center(child: Text("Waiting for partner… ⏳", style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600))),
      if (revealed) ...[
        Center(child: Text(matched ? "Perfect Match ❤️" : "Oops 😅",
            style: TextStyle(color: matched ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontSize: 18, fontWeight: FontWeight.w800))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C), padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _next,
          child: Text(idx + 1 >= total ? "See Result 🎉" : "Next Question ▶", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
      ],
    ]);
  }

  Widget _resultView(Color on) => ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 20),
        const Center(child: Text("🎉", style: TextStyle(fontSize: 64))),
        const SizedBox(height: 12),
        Center(child: Text("${_result['percent'] ?? 0}%", style: const TextStyle(color: Color(0xFFE8467C), fontSize: 52, fontWeight: FontWeight.w900))),
        Center(child: Text("${_result['label'] ?? ''}", style: TextStyle(color: on, fontSize: 18, fontWeight: FontWeight.w700))),
        const SizedBox(height: 24),
        _resRow("Total Questions", "${_result['total'] ?? 0}", on),
        _resRow("Matched ❤️", "${_result['matches'] ?? 0}", on),
        _resRow("Different 😅", "${_result['wrong'] ?? 0}", on),
        const SizedBox(height: 28),
        SizedBox(width: double.infinity, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C), padding: const EdgeInsets.symmetric(vertical: 15)),
          onPressed: () => setState(() { _showResult = false; _state = {'active': false}; }),
          child: const Text("Play Again 🔁", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
        const SizedBox(height: 10),
        Center(child: TextButton(onPressed: () => Get.to(() => const QuizHistoryScreen()), child: const Text("View History"))),
      ]);

  Widget _resRow(String k, String v, Color on) => Container(
    margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: BorderRadius.circular(14)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(k, style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
      Text(v, style: TextStyle(color: on, fontWeight: FontWeight.w800, fontSize: 16)),
    ]),
  );
}

// Create a custom question (added to the shared bank for this couple).
class CustomQuestionScreen extends StatefulWidget {
  const CustomQuestionScreen({super.key});
  @override
  State<CustomQuestionScreen> createState() => _CustomQuestionScreenState();
}

class _CustomQuestionScreenState extends State<CustomQuestionScreen> {
  final ApiService _api = ApiService();
  final _q = TextEditingController();
  final _opts = List.generate(4, (_) => TextEditingController());
  bool _saving = false;

  Future<void> _save() async {
    final q = _q.text.trim();
    final options = _opts.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (q.isEmpty || options.length < 2) { Get.snackbar("Add more", "A question and at least 2 options."); return; }
    setState(() => _saving = true);
    try {
      await _api.post('/quiz/custom', data: {'question': q, 'options': options}).timeout(const Duration(seconds: 8));
      Get.back(); Get.snackbar("Added ✍️", "Your question is in the quiz now!");
    } catch (_) { Get.snackbar("Error", "Couldn't save."); }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final on = Get.theme.colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0, foregroundColor: on,
        title: const Text("Custom Question ✍️", style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(controller: _q, style: TextStyle(color: on),
          decoration: const InputDecoration(labelText: "Your question", hintText: "What's my favorite perfume?", border: OutlineInputBorder())),
        const SizedBox(height: 16),
        Text("Options", style: TextStyle(fontWeight: FontWeight.w700, color: on)),
        const SizedBox(height: 8),
        ..._opts.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 10),
          child: TextField(controller: e.value, style: TextStyle(color: on),
            decoration: InputDecoration(labelText: "Option ${e.key + 1}${e.key < 2 ? ' *' : ''}", border: const OutlineInputBorder())))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C), padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? "Saving…" : "Save Question", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
      ]),
    );
  }
}

// Achievements / awards.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic> _data = {};
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final r = await _api.get('/quiz/achievements').timeout(const Duration(seconds: 8));
      if (mounted) setState(() { _data = Map<String, dynamic>.from(r.data['data'] ?? {}); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }
  @override
  Widget build(BuildContext context) {
    final on = Get.theme.colorScheme.onSurface;
    final ach = (_data['achievements'] as List?) ?? [];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0, foregroundColor: on,
        title: const Text("Achievements 🏆", style: TextStyle(fontWeight: FontWeight.w800))),
      body: _loading ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat("${_data['gamesPlayed'] ?? 0}", "Games", on),
                _stat("${_data['totalMatches'] ?? 0}", "Matches", on),
                _stat("${_data['perfectGames'] ?? 0}", "Perfect", on),
              ]),
              const SizedBox(height: 20),
              ...ach.map((a) {
                final unlocked = a['unlocked'] == true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: unlocked ? const Color(0xFFE8467C) : Colors.transparent)),
                  child: Row(children: [
                    Opacity(opacity: unlocked ? 1 : 0.35, child: Text(a['emoji'] ?? '🏅', style: const TextStyle(fontSize: 30))),
                    const SizedBox(width: 14),
                    Expanded(child: Text(a['title'] ?? '', style: TextStyle(color: on, fontWeight: FontWeight.w700))),
                    Icon(unlocked ? Icons.check_circle : Icons.lock_outline, color: unlocked ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                  ]),
                );
              }),
            ]),
    );
  }
  Widget _stat(String v, String k, Color on) => Column(children: [
    Text(v, style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w900, fontSize: 24)),
    Text(k, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
  ]);
}

// Quiz history.
class QuizHistoryScreen extends StatefulWidget {
  const QuizHistoryScreen({super.key});
  @override
  State<QuizHistoryScreen> createState() => _QuizHistoryScreenState();
}

class _QuizHistoryScreenState extends State<QuizHistoryScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final r = await _api.get('/quiz/history').timeout(const Duration(seconds: 8));
      final l = (r.data['data']?['history'] ?? []) as List;
      if (mounted) setState(() { _list = l.map((e) => Map<String, dynamic>.from(e)).toList(); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }
  @override
  Widget build(BuildContext context) {
    final on = Get.theme.colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0, foregroundColor: on,
        title: const Text("Quiz History", style: TextStyle(fontWeight: FontWeight.w800))),
      body: _loading ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
          : _list.isEmpty ? const Center(child: Text("No games yet.", style: TextStyle(color: Color(0xFF94A3B8))))
          : ListView.builder(padding: const EdgeInsets.all(12), itemCount: _list.length, itemBuilder: (_, i) {
              final h = _list[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: Get.theme.cardColor, borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: const Color(0x22E8467C),
                    child: Text("${h['percent'] ?? 0}%", style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold, fontSize: 12))),
                  title: Text("${(h['category'] ?? 'random').toString().toUpperCase()}  ·  ${h['matches'] ?? 0}/${h['total'] ?? 0}", style: TextStyle(color: on, fontWeight: FontWeight.w600)),
                  subtitle: Text("${(h['date'] ?? '').toString().split(' ').first}  ·  ${h['status'] ?? ''}", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                ),
              );
            }),
    );
  }
}

// ── Live Couple-Quiz card rendered INSIDE the chat (like Truth & Dare) ───────
class CoupleQuizChatCard extends StatefulWidget {
  const CoupleQuizChatCard({super.key});
  @override
  State<CoupleQuizChatCard> createState() => _CoupleQuizChatCardState();
}

class _CoupleQuizChatCardState extends State<CoupleQuizChatCard> {
  final ApiService _api = ApiService();
  Map<String, dynamic> _state = {'active': false};
  Map<String, dynamic> _result = {};
  bool _wasActive = false, _showResult = false, _loaded = false;
  Timer? _poll, _qTimer;
  int _secondsLeft = 20, _timedIndex = -1;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(milliseconds: 1200), (_) => _refresh());
  }

  @override
  void dispose() { _poll?.cancel(); _qTimer?.cancel(); super.dispose(); }

  Future<Map<String, dynamic>> _get(String p) async {
    try { final r = await _api.get(p).timeout(const Duration(seconds: 8)); return Map<String, dynamic>.from(r.data['data'] ?? {}); } catch (_) { return {}; }
  }
  Future<Map<String, dynamic>> _postReq(String p, [Map<String, dynamic>? d]) async {
    try { final r = await _api.post(p, data: d ?? {}).timeout(const Duration(seconds: 8)); return Map<String, dynamic>.from(r.data['data'] ?? {}); } catch (_) { return {}; }
  }

  Future<void> _refresh() async {
    final s = await _get('/quiz/state');
    if (!mounted) return;
    if (s['active'] == true) { setState(() { _state = s; _wasActive = true; _showResult = false; _loaded = true; }); _syncTimer(); }
    else {
      if (_wasActive) { final r = await _get('/quiz/result'); if (['finished','stopped'].contains(r['status'])) setState(() { _result = r; _showResult = true; }); _wasActive = false; }
      setState(() { _state = s; _loaded = true; });
    }
  }

  void _syncTimer() {
    final idx = _state['index'] ?? -1;
    if (_state['myAnswer'] != null || _state['revealed'] == true || _state['status'] != 'active') { _qTimer?.cancel(); return; }
    if (idx != _timedIndex) {
      _timedIndex = idx; _secondsLeft = 20; _qTimer?.cancel();
      _qTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        setState(() => _secondsLeft--);
        if (_secondsLeft <= 0) { t.cancel(); _answer('(no answer)'); }
      });
    }
  }

  Future<void> _answer(String o) async { _qTimer?.cancel(); final s = await _postReq('/quiz/answer', {'answer': o}); if (mounted && s.isNotEmpty) setState(() => _state = s); }
  Future<void> _next() async {
    final s = await _postReq('/quiz/next', {'fromIndex': _state['index'] ?? 0});
    if (!mounted) return;
    if (s['status'] == 'finished') { final r = await _get('/quiz/result'); setState(() { _result = r; _showResult = true; _wasActive = false; }); }
    else { setState(() => _state = s); _syncTimer(); }
  }
  Future<void> _stop() async {
    final ok = await Get.dialog<bool>(AlertDialog(
      title: const Text("Stop Couple Quiz?"),
      content: const Text("Either of you can stop the game. Current score will be saved."),
      actions: [
        TextButton(onPressed: () => Get.back(result: false), child: const Text("No")),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
          onPressed: () => Get.back(result: true), child: const Text("Yes, stop", style: TextStyle(color: Colors.white))),
      ],
    ));
    if (ok != true) return;
    await _postReq('/quiz/stop');
    final r = await _get('/quiz/result');
    if (mounted) setState(() { _result = r; _showResult = true; _wasActive = false; });
  }
  Future<void> _pause() async { await _postReq('/quiz/pause'); _refresh(); }
  Future<void> _resume() async { await _postReq('/quiz/resume'); _refresh(); }

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    Widget shell(Widget child) => Container(
      width: double.infinity, margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8467C).withOpacity(0.3))),
      child: child,
    );

    if (!_loaded) return shell(const Center(child: Padding(padding: EdgeInsets.all(8), child: Text("🎮 Couple Quiz…", style: TextStyle(color: Color(0xFF94A3B8))))));

    if (_showResult) {
      return shell(Column(children: [
        const Text("🎉 Quiz Result", style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFE8467C))),
        const SizedBox(height: 6),
        Text("${_result['percent'] ?? 0}%  ·  ${_result['label'] ?? ''}", style: TextStyle(color: on, fontWeight: FontWeight.w700, fontSize: 16)),
        Text("Matched ${_result['matches'] ?? 0}/${_result['total'] ?? 0}", style: const TextStyle(color: Color(0xFF94A3B8))),
      ]));
    }

    if (_state['active'] != true) {
      return shell(const Text("🎮 Couple Quiz ended.", style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)));
    }

    // Paused: either partner can resume or stop.
    if (_state['status'] == 'paused') {
      return shell(Row(children: [
        const Text("⏸️  Quiz paused", style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w700)),
        const Spacer(),
        TextButton(onPressed: _resume, child: const Text("Resume")),
        TextButton(onPressed: _stop, child: const Text("Stop", style: TextStyle(color: Color(0xFFEF4444)))),
      ]));
    }

    final q = _state['question'] as Map<String, dynamic>?;
    if (q == null) return shell(const Text("🎮 Couple Quiz…", style: TextStyle(color: Color(0xFF94A3B8))));
    final options = (q['options'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final idx = (_state['index'] ?? 0) as int, total = (_state['total'] ?? 0) as int;
    final myAns = _state['myAnswer'] as String?;
    final revealed = _state['revealed'] == true, matched = _state['matched'] == true;
    final partnerAns = _state['partnerAnswer'] as String?;

    return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text("🎮 Couple Quiz  ·  Q${idx + 1}/$total", style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w800, fontSize: 13)),
        Row(children: [
          Text("${_state['percent'] ?? 0}%", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          if (!revealed && myAns == null) Padding(padding: const EdgeInsets.only(left: 8), child: Text("$_secondsLeft s", style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12))),
          // Either contestant can pause or stop mid-game.
          SizedBox(width: 26, height: 22, child: PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF94A3B8)),
            onSelected: (v) { if (v == 'pause') _pause(); else _stop(); },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pause', child: Text("Pause Game")),
              PopupMenuItem(value: 'stop', child: Text("Stop Game")),
            ],
          )),
        ]),
      ]),
      const SizedBox(height: 10),
      Text(q['question'] ?? '', style: TextStyle(color: on, fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 12),
      ...options.map((opt) {
        final iPicked = myAns == opt; final partnerPicked = partnerAns == opt;
        Color bg = Theme.of(context).scaffoldBackgroundColor, bd = const Color(0x3394A3B8); String? tag;
        if (revealed) {
          if (iPicked && matched) { bg = const Color(0x2210B981); bd = const Color(0xFF10B981); tag = "✓"; }
          else if (iPicked) { bg = const Color(0x22EF4444); bd = const Color(0xFFEF4444); tag = "You"; }
          else if (partnerPicked) { bg = const Color(0x22E8467C); bd = const Color(0xFFE8467C); tag = "Partner"; }
        } else if (iPicked) { bg = const Color(0x22E8467C); bd = const Color(0xFFE8467C); tag = "✓"; }
        return Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(
          onTap: (myAns == null && !revealed) ? () => _answer(opt) : null,
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: bd, width: 1.4)),
            child: Row(children: [
              Expanded(child: Text(opt, style: TextStyle(color: on, fontWeight: FontWeight.w600))),
              if (tag != null) Text(tag, style: const TextStyle(color: Color(0xFFE8467C), fontSize: 11, fontWeight: FontWeight.bold)),
            ])),
        ));
      }),
      if (myAns != null && !revealed) const Text("Waiting for partner… ⏳", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, fontWeight: FontWeight.w600)),
      if (revealed) ...[
        Center(child: Text(matched ? "Perfect Match ❤️" : "Oops 😅", style: TextStyle(color: matched ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontWeight: FontWeight.w800))),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C), padding: const EdgeInsets.symmetric(vertical: 10)),
          onPressed: _next, child: Text(idx + 1 >= total ? "See Result 🎉" : "Next ▶", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
      ],
    ]));
  }
}
