import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';

// "Ask Each Other" turn-based quiz card, played inside the chat.
// Flow: accept → race to ask → asker writes custom Q + options → partner answers → reveal → next round.
class QuizAskCard extends StatefulWidget {
  final String myId;
  final int sid; // this invite message's own session id (0 = unknown/legacy)
  const QuizAskCard({super.key, required this.myId, this.sid = 0});
  @override
  State<QuizAskCard> createState() => _QuizAskCardState();
}

class _QuizAskCardState extends State<QuizAskCard> {
  final ApiService _api = ApiService();
  Map<String, dynamic> _s = {'active': false};
  bool _loaded = false, _busy = false;
  Timer? _poll;
  final _qC = TextEditingController();
  final _oC = List.generate(4, (_) => TextEditingController());
  final _ansC = TextEditingController(); // Truth & Dare free-text answer
  String _tdType = 'Truth';
  // Default-from-database question suggestion for the asker.
  Map<String, dynamic>? _suggest;   // {question, options, answerKey}
  bool _useOwn = true;              // couples ALWAYS write their own — no preset bank
  bool _suggestBusy = false;
  int _suggestForSid = 0;           // session the current suggestion belongs to
  int _correctIdx = -1;             // which option the asker marked correct (-1 = none)

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(milliseconds: 1200), (_) => _refresh());
  }

  @override
  void dispose() { _poll?.cancel(); _qC.dispose(); _ansC.dispose(); for (final c in _oC) { c.dispose(); } super.dispose(); }

  Future<Map<String, dynamic>> _get(String p) async {
    try { final r = await _api.get(p).timeout(const Duration(seconds: 8)); return Map<String, dynamic>.from(r.data['data'] ?? {}); } catch (_) { return {}; }
  }
  Future<Map<String, dynamic>> _post(String p, [Map<String, dynamic>? d]) async {
    try { final r = await _api.post(p, data: d ?? {}).timeout(const Duration(seconds: 8)); return Map<String, dynamic>.from(r.data['data'] ?? {}); } catch (_) { return {}; }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final s = await _get('/quiz/ask/state');
    if (mounted) setState(() { _s = s; _loaded = true; });
  }

  Future<void> _act(String path, [Map<String, dynamic>? d]) async {
    setState(() => _busy = true);
    final s = await _post(path, d);
    if (mounted) setState(() { if (s.isNotEmpty) _s = s; _busy = false; });
  }

  // Pull a ready-made question from the uploaded bank (default option).
  Future<void> _fetchSuggest(int sid) async {
    if (_suggestBusy) return;
    setState(() { _suggestBusy = true; _suggestForSid = sid; });
    final s = await _get('/quiz/ask/suggest');
    if (mounted) setState(() { _suggest = s.isNotEmpty ? s : null; _suggestBusy = false; });
  }

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    Widget shell(Widget c) => Container(
      width: double.infinity, margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8467C).withOpacity(0.3))),
      child: c);

    if (!_loaded) return shell(const Text("🎮 Loading game…", style: TextStyle(color: Color(0xFF94A3B8))));
    // Only the invite whose session matches the current live one stays active.
    // Older/superseded invite cards collapse so requests never pile up.
    final liveSid = int.tryParse('${_s['sessionId'] ?? 0}') ?? 0;
    if (widget.sid > 0 && liveSid > 0 && widget.sid != liveSid) {
      return shell(const Text("🎮 Game invite expired.", style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)));
    }
    if (_s['active'] != true) return shell(const Text("🎮 Game ended.", style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)));

    final phase = (_s['phase'] ?? '').toString();
    final iAmAsker = _s['iAmAsker'] == true;
    final iAmInviter = (_s['createdBy'] ?? '') == widget.myId;
    final options = (_s['options'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final game = (_s['game'] ?? 'couple_quiz').toString();
    final isTD = game == 'truth_dare';
    final isWYR = game == 'would_rather';
    final isEmoji = game == 'emoji';
    final isPuzzle = game == 'puzzle';
    final isNHIE = game == 'nhie';
    final gameName = isWYR ? 'Would You Rather' : isTD ? 'Truth & Dare' : isEmoji ? 'Emoji Challenge' : isPuzzle ? 'Puzzle Time' : isNHIE ? 'Never Have I Ever' : 'Couple Quiz';
    final gameEmoji = isWYR ? '🤔' : isTD ? '💕' : isEmoji ? '😊' : isPuzzle ? '🧩' : isNHIE ? '❤️' : '🎮';
    // Free-text answer (guess / "Done") when there are no options to pick.
    final freeAnswer = isTD || isPuzzle || (isEmoji && options.isEmpty);

    Widget title() => Text("$gameEmoji $gameName", style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w800, fontSize: 13));

    Widget btn(String t, VoidCallback onTap, {Color c = const Color(0xFFE8467C)}) => SizedBox(width: double.infinity,
      child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 12)),
        onPressed: _busy ? null : onTap, child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))));

    final askLine = isTD ? "The asker picks Truth or Dare and writes it; the partner replies."
        : isWYR ? "The asker writes two choices; the partner picks one."
        : isEmoji ? "The asker sends only emojis; the partner guesses the meaning."
        : isPuzzle ? "The asker makes a puzzle (+ the correct answer); the partner solves it."
        : isNHIE ? "The asker writes a 'Never have I ever…' — the partner answers I Have / Never."
        : "The asker writes a question + options; the partner answers.";
    Widget howToPlay() => Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        iconColor: const Color(0xFFE8467C), collapsedIconColor: const Color(0xFF94A3B8),
        title: const Text("How to play ▾", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, fontWeight: FontWeight.w600)),
        children: [Align(alignment: Alignment.centerLeft, child: Text(
          "• Accept the invite to start.\n"
          "• First round: whoever taps 'I'll go first' fastest gets to ask.\n"
          "• After that it's turn-wise — you take turns.\n"
          "• $askLine\n"
          "• Both sides are revealed. Talk about them! 💬\n"
          "• You get only 3 skips per game — after that it's compulsory.",
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.5)))],
      ),
    );

    switch (phase) {
      case 'pending_accept':
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title(), const SizedBox(height: 8),
          Text(iAmInviter ? "Waiting for your partner to accept ⏳"
                          : "${_s['inviterName'] ?? 'Partner'} invited you to play ❤️", style: TextStyle(color: on, fontWeight: FontWeight.w600)),
          howToPlay(),
          const SizedBox(height: 6),
          if (!iAmInviter) Row(children: [
            Expanded(child: btn("Accept", () => _act('/quiz/ask/accept'))),
            const SizedBox(width: 10),
            Expanded(child: btn("Decline", () => _act('/quiz/ask/decline'), c: const Color(0xFFEF4444))),
          ]),
        ]));

      case 'racing':
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title(), const SizedBox(height: 8),
          Text("Who goes first? Tap fastest to get the first turn! 🙋", style: TextStyle(color: on, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          btn("I'll go first 🙋", () => _act('/quiz/ask/claim')),
        ]));

      case 'asking':
        if (iAmAsker) {
          // Default: send a ready-made question from the database. "Write my own"
          // is the secondary option. Auto-fetch a suggestion for this turn once.
          final curSid = int.tryParse('${_s['sessionId'] ?? 0}') ?? 0;
          if (!_useOwn && _suggest == null && !_suggestBusy && _suggestForSid != curSid) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _fetchSuggest(curSid));
          }
          if (!_useOwn) {
            final sq = (_suggest?['question'] ?? '').toString();
            final sOpts = (_suggest?['options'] as List?)?.map((e) => e.toString()).toList() ?? [];
            final sKey = (_suggest?['answerKey'] ?? '').toString();
            return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title(), const SizedBox(height: 8),
              Text("Your turn — send a question 💬", style: TextStyle(color: on, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (_suggestBusy || _suggestForSid != curSid)
                const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text("Picking a question… 🎲", style: TextStyle(color: Color(0xFF94A3B8))))
              else if (sq.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text("No ready question right now — tap \"Write my own\" below 👇",
                      style: TextStyle(color: Color(0xFFEF4444), fontSize: 12.5, fontWeight: FontWeight.w600)))
              else Container(width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x3394A3B8))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(sq, style: TextStyle(color: on, fontWeight: FontWeight.w700, fontSize: 15)),
                  if (sOpts.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ...sOpts.map((o) => Padding(padding: const EdgeInsets.only(top: 3),
                      child: Text("• $o", style: TextStyle(color: on.withOpacity(0.8), fontSize: 13)))),
                  ],
                  if (sKey.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6),
                    child: Text("Answer: $sKey", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12))),
                ])),
              const SizedBox(height: 10),
              if (sq.isNotEmpty) Row(children: [
                Expanded(child: btn("Send this ▶", () {
                  _act('/quiz/ask/question', {'question': sq, 'options': sOpts.join('||'), if (sKey.isNotEmpty) 'answerKey': sKey});
                  setState(() { _suggest = null; _suggestForSid = 0; });
                })),
                const SizedBox(width: 8),
                SizedBox(width: 52, child: btn("🔀", () => _fetchSuggest(curSid), c: const Color(0xFF64748B))),
              ]),
              const SizedBox(height: 6),
              Align(alignment: Alignment.center, child: TextButton(
                onPressed: () => setState(() => _useOwn = true),
                child: const Text("✍️ Write my own question", style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w700, fontSize: 13)))),
              howToPlay(),
            ]));
          }
          final maxOpts = isWYR ? 2 : 4;
          final qHint = isTD ? "Write the truth question / dare task…"
              : isWYR ? "Would you rather…  (optional intro)"
              : isEmoji ? "Send only emojis 😊❤️🍕"
              : isPuzzle ? "Your puzzle (e.g. ❤️ _ O _ E, or a riddle)"
              : isNHIE ? "Never have I ever… (finish the sentence)" : "Your question…";
          return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            title(),
            const SizedBox(height: 4),
            Text(isTD ? "Your turn — Truth or Dare?"
                : isEmoji ? "Your turn — send emojis, they guess!"
                : isPuzzle ? "Your turn — make a puzzle!"
                : isNHIE ? "Your turn — write a 'Never have I ever…'"
                : "Your turn — ${isWYR ? 'give two choices!' : 'ask anything!'}",
                style: TextStyle(color: on, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (isTD) Row(children: [
              for (final t in ['Truth', 'Dare']) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
                label: Text(t), selected: _tdType == t, selectedColor: const Color(0xFFE8467C),
                labelStyle: TextStyle(color: _tdType == t ? Colors.white : on, fontWeight: FontWeight.w600),
                onSelected: (_) => setState(() => _tdType = t))),
            ]),
            if (isTD) const SizedBox(height: 8),
            TextField(controller: _qC, style: TextStyle(color: on),
              decoration: InputDecoration(hintText: qHint, filled: true, fillColor: Theme.of(context).scaffoldBackgroundColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none))),
            const SizedBox(height: 8),
            if (isNHIE) ...[
              const Padding(padding: EdgeInsets.only(bottom: 6),
                child: Text("Your partner will answer: ✅ I Have  /  ❌ Never", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12))),
              Row(children: [
                const Text("Correct answer (optional): ", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                for (int i = 0; i < 2; i++) Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
                  label: Text(i == 0 ? '✅ I Have' : '❌ Never'), selected: _correctIdx == i, selectedColor: const Color(0xFF10B981),
                  labelStyle: TextStyle(color: _correctIdx == i ? Colors.white : on, fontSize: 12, fontWeight: FontWeight.w600),
                  onSelected: (_) => setState(() => _correctIdx = _correctIdx == i ? -1 : i))),
              ]),
            ]
            else if (isPuzzle)
              TextField(controller: _oC[0], style: TextStyle(color: on),
                decoration: InputDecoration(hintText: "Correct answer (optional)", isDense: true, filled: true, fillColor: Theme.of(context).scaffoldBackgroundColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)))
            else if (!isTD) ...[
              // Each option has a tappable ● to mark it as the correct answer (optional).
              ...List.generate(maxOpts, (i) => Padding(padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  InkWell(onTap: () => setState(() => _correctIdx = _correctIdx == i ? -1 : i),
                    child: Padding(padding: const EdgeInsets.only(right: 8),
                      child: Icon(_correctIdx == i ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: _correctIdx == i ? const Color(0xFF10B981) : const Color(0xFF94A3B8), size: 22))),
                  Expanded(child: TextField(controller: _oC[i], style: TextStyle(color: on),
                    decoration: InputDecoration(
                      hintText: isWYR ? (i == 0 ? "Option A" : "Option B")
                          : isEmoji ? "Guess option ${i + 1} (optional)" : "Option ${i + 1}${i < 2 ? '' : ' (optional)'}",
                      isDense: true, filled: true, fillColor: Theme.of(context).scaffoldBackgroundColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)))),
                ]))),
              Padding(padding: const EdgeInsets.only(top: 2),
                child: Text("Tap the ● to mark the correct answer (optional).", style: TextStyle(color: on.withOpacity(0.5), fontSize: 11))),
            ],
            if (isEmoji) const Padding(padding: EdgeInsets.only(top: 2, bottom: 4),
              child: Text("Leave options blank to let them type a free guess.", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11))),
            const SizedBox(height: 6),
            btn("Send ▶", () {
              final q = _qC.text.trim();
              if (q.isEmpty) { Get.snackbar("Add more", isTD ? "Write your truth/dare" : isEmoji ? "Send some emojis" : isPuzzle ? "Write your puzzle" : "Write a question"); return; }
              if (isTD) {
                _act('/quiz/ask/question', {'question': "$_tdType: $q", 'options': ''});
              } else if (isNHIE) {
                final ak = _correctIdx == 0 ? '✅ I Have' : _correctIdx == 1 ? '❌ Never' : '';
                _act('/quiz/ask/question', {'question': q, 'options': '✅ I Have||❌ Never', if (ak.isNotEmpty) 'answerKey': ak});
              } else if (isPuzzle) {
                _act('/quiz/ask/question', {'question': q, 'options': '', 'answerKey': _oC[0].text.trim()});
              } else {
                final opts = _oC.take(maxOpts).map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
                if (!isEmoji && opts.length < 2) { Get.snackbar("Add more", "Add at least 2 options"); return; }
                // Correct answer = the text of the option the asker marked (if any).
                final ak = (_correctIdx >= 0 && _correctIdx < maxOpts) ? _oC[_correctIdx].text.trim() : '';
                _act('/quiz/ask/question', {'question': q, 'options': opts.join('||'), if (ak.isNotEmpty) 'answerKey': ak});
              }
              _qC.clear(); for (final c in _oC) { c.clear(); }
              setState(() { _useOwn = false; _suggest = null; _suggestForSid = 0; _correctIdx = -1; });
            }),
          ]));
        }
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title(), const SizedBox(height: 8),
          Text("${_s['askerName'] ?? 'Partner'} is thinking… ✍️", style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
        ]));

      case 'answering':
        if (iAmAsker) {
          return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            title(), const SizedBox(height: 8),
            Text("You asked: ${_s['question'] ?? ''}", style: TextStyle(color: on, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text("Waiting for their answer… ⏳", style: TextStyle(color: Color(0xFF94A3B8))),
          ]));
        }
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title(), const SizedBox(height: 8),
          Text("${_s['askerName'] ?? 'Partner'} asks:", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          const SizedBox(height: 4),
          Text(_s['question'] ?? '', style: TextStyle(color: on, fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          // Free-text reply (Truth&Dare / Emoji guess). Others: option buttons.
          if (freeAnswer) ...[
            TextField(controller: _ansC, style: TextStyle(color: on), minLines: 1, maxLines: 3,
              decoration: InputDecoration(hintText: isEmoji ? "Type your guess…" : "Your answer… (or just tap Done)", filled: true, fillColor: Theme.of(context).scaffoldBackgroundColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none))),
            const SizedBox(height: 8),
            if (isEmoji)
              btn("Send guess", () {
                if (_ansC.text.trim().isEmpty) { Get.snackbar("Guess", "Type your guess"); return; }
                _act('/quiz/ask/answer', {'answer': _ansC.text.trim()}); _ansC.clear();
              })
            else Row(children: [
              Expanded(child: btn("Send answer", () {
                final a = _ansC.text.trim().isEmpty ? "Done ✅" : _ansC.text.trim();
                _act('/quiz/ask/answer', {'answer': a}); _ansC.clear();
              })),
              const SizedBox(width: 10),
              Expanded(child: btn("Done ✅", () { _act('/quiz/ask/answer', {'answer': 'Done ✅'}); _ansC.clear(); }, c: const Color(0xFF10B981))),
            ]),
          ] else
            ...options.map((o) => Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(
              onTap: _busy ? null : () => _act('/quiz/ask/answer', {'answer': o}),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x3394A3B8))),
                child: Text(o, style: TextStyle(color: on, fontWeight: FontWeight.w600)))))),
          const SizedBox(height: 4),
          // Skip: only 3 per game, then the question is compulsory.
          if ((_s['skipsLeft'] ?? 0) > 0)
            Align(alignment: Alignment.centerRight, child: TextButton(
              onPressed: _busy ? null : () => _act('/quiz/ask/skip'),
              child: Text("Skip (${_s['skipsLeft']} left)", style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600))))
          else
            const Align(alignment: Alignment.centerRight, child: Text("No skips left — you must answer 🙂", style: TextStyle(color: Color(0xFFEF4444), fontSize: 12))),
        ]));

      case 'revealed':
        final key = _s['answerKey']?.toString();
        final correct = _s['correct'];
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title(), const SizedBox(height: 8),
          Text("Q: ${_s['question'] ?? ''}", style: TextStyle(color: on, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Container(padding: const EdgeInsets.all(12), width: double.infinity,
            decoration: BoxDecoration(color: const Color(0x22E8467C), borderRadius: BorderRadius.circular(12)),
            child: Text("${(isPuzzle || isEmoji) ? 'Their guess' : 'Answer'}: ${_s['answer'] ?? '—'}", style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w800, fontSize: 15))),
          if (key != null && key.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text("Correct answer: $key", style: TextStyle(color: on, fontWeight: FontWeight.w600)),
            if (correct != null) Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(correct == true ? "✅ Correct!" : "❌ Not quite",
                style: TextStyle(color: correct == true ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontWeight: FontWeight.w800))),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: btn("Next round 🔁", () => _act('/quiz/ask/next'))),
            const SizedBox(width: 10),
            Expanded(child: btn("Stop", () => _act('/quiz/ask/stop'), c: const Color(0xFFEF4444))),
          ]),
        ]));

      default:
        return shell(const Text("🎮 Loading…", style: TextStyle(color: Color(0xFF94A3B8))));
    }
  }
}
