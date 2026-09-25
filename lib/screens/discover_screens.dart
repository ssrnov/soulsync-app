import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/controllers.dart';
import '../widgets/ad_banner.dart';

// ── SoulSync Discover (Phase 1 MVP) ──────────────────────────────────────────
// Optional feature to meet new people. OFF by default; disabled while in a couple.

const kInterests = [
  'Gaming','Movies','Coding','Cricket','Football','Gym','Reading','Anime',
  'Photography','Music','Dance','Travel','Cooking','Business','Startups','Pets','Cars','Bikes','Fashion',
];
const kPurposes = {
  'relationship':'❤️ Relationship','friendship':'🤝 Friendship','gaming':'🎮 Gaming Partner',
  'study':'📚 Study Partner','travel':'✈️ Travel Buddy','chat':'💬 Just Chat',
};

class DiscoverController extends GetxController {
  final ApiService _api = ApiService();
  final RxBool loading = true.obs;
  final RxBool inCouple = false.obs;
  final RxBool onboarded = false.obs;
  final RxBool enabled = false.obs;

  Future<void> fetchStatus() async {
    loading.value = true;
    try {
      final r = await _api.get('/discover/status');
      final d = r.data['data'] ?? {};
      inCouple.value = d['inCouple'] == true;
      onboarded.value = d['onboarded'] == true;
      enabled.value = d['enabled'] == true;
    } catch (_) {}
    loading.value = false;
  }

  Future<bool> submitOnboarding(Map<String, dynamic> data) async {
    try {
      final r = await _api.post('/discover/onboarding', data: data);
      if (r.data['success'] == true) { onboarded.value = true; enabled.value = true; return true; }
    } catch (_) {}
    return false;
  }

  Future<void> pushLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low)
          .timeout(const Duration(seconds: 6));
      await _api.post('/discover/location', data: {'lat': pos.latitude, 'lng': pos.longitude});
    } catch (_) {}
  }

  // Active filters (empty = default). Keys: gender, ageMin, ageMax, maxKm, onlineOnly, verifiedOnly.
  final RxMap<String, String> filters = <String, String>{}.obs;

  Future<List<Map<String, dynamic>>> feed(String mode) async {
    try {
      final qp = <String>[];
      filters.forEach((k, v) { if (v.isNotEmpty) qp.add('$k=$v'); });
      final path = '/discover/$mode${qp.isNotEmpty ? '?${qp.join('&')}' : ''}';
      final r = await _api.get(path);
      final list = (r.data['data']?['users'] as List?) ?? [];
      return list.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) { return []; }
  }

  Future<void> wave(String toId) async {
    try { await _api.post('/discover/wave', data: {'toId': toId}); Get.snackbar('👋', 'You waved!'); }
    catch (_) {}
  }

  Future<bool> toggleFavorite(String toId) async {
    try {
      final r = await _api.post('/discover/favorite', data: {'toId': toId});
      return r.data['data']?['favorited'] == true;
    } catch (_) { return false; }
  }

  Future<List<Map<String, dynamic>>> favorites() async {
    try {
      final r = await _api.get('/discover/favorites');
      return ((r.data['data']?['users'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) { return []; }
  }

  // ── Phase 3 ──
  Future<Map<String, dynamic>> viewsData() async {
    try { final r = await _api.get('/discover/views'); return Map<String, dynamic>.from(r.data['data'] ?? {}); }
    catch (_) { return {'locked': true, 'count': 0, 'users': []}; }
  }

  // Unlock "who viewed me" for 24h. (Start.io removed — unlock directly.)
  Future<void> unlockViewsWithAd(VoidCallback onDone) async {
    try { await _api.post('/discover/views/unlock'); } catch (_) {}
    onDone();
  }

  // Load current preferences to prefill the edit screen.
  Future<Map<String, dynamic>> loadPreferences() async {
    try { final r = await _api.get('/discover/preferences'); return Map<String, dynamic>.from(r.data['data'] ?? {}); }
    catch (_) { return {}; }
  }

  // Pause / resume being visible in Discover.
  Future<void> setEnabled(bool on) async {
    try { await _api.post('/discover/visibility', data: {'enabled': on}); enabled.value = on; } catch (_) {}
  }

  Future<void> report(String id, String reason) async {
    try { await _api.post('/discover/report', data: {'targetId': id, 'reason': reason}); Get.snackbar('Reported', "Thanks — we'll review this."); } catch (_) {}
  }
  Future<void> block(String id) async {
    try { await _api.post('/discover/block', data: {'targetId': id}); Get.snackbar('Blocked', "You won't see them anymore."); } catch (_) {}
  }

  Future<void> sendRequest(String toId) async {
    try {
      final r = await _api.post('/discover/request', data: {'toId': toId});
      if (r.data['success'] == true) Get.snackbar('Sent ❤️', 'Soul request sent!');
      else Get.snackbar('Limit', r.data['message']?.toString() ?? 'Could not send');
    } catch (_) { Get.snackbar('Error', 'Could not send request'); }
  }

  Future<List<Map<String, dynamic>>> requests() async {
    try {
      final r = await _api.get('/discover/requests');
      return ((r.data['data']?['requests'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) { return []; }
  }

  Future<Map<String, dynamic>?> respond(String requestId, bool accept) async {
    try {
      final r = await _api.post('/discover/request/respond', data: {'requestId': requestId, 'accept': accept});
      return Map<String, dynamic>.from(r.data['data'] ?? {});
    } catch (_) { return null; }
  }

  Future<List<Map<String, dynamic>>> matches() async {
    try {
      final r = await _api.get('/discover/matches');
      return ((r.data['data']?['matches'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) { return []; }
  }
}

// Entry: routes to the right screen based on status.
class DiscoverScreen extends StatefulWidget {
  final int initialTab; // 0 nearby … 4 requests, 5 favorites, 6 chats
  final bool singleMode; // true = shown as the whole app (Single Mode) with a footer nav
  const DiscoverScreen({super.key, this.initialTab = 0, this.singleMode = false});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final DiscoverController c = Get.put(DiscoverController());
  @override
  void initState() { super.initState(); c.fetchStatus(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0,
        automaticallyImplyLeading: !widget.singleMode,
        title: Text("Discover ✨", style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold)),
        actions: [
          // Single Mode: an easy way to exit back to couple mode.
          if (widget.singleMode)
            TextButton.icon(
              onPressed: () => Get.find<AuthController>().setSingleMode(false),
              icon: const Icon(Icons.favorite, color: Color(0xFFE8467C), size: 18),
              label: const Text("Exit", style: TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.w700)),
            ),
          Obx(() => (c.onboarded.value && !c.inCouple.value)
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Text("👀", style: TextStyle(fontSize: 20)),
                    tooltip: "Who viewed you",
                    onPressed: () => Get.to(() => DiscoverViewsScreen(controller: c))),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.settings_outlined, color: cs.onSurface),
                    onSelected: (v) async {
                      if (v == 'edit') {
                        final p = await c.loadPreferences();
                        Get.to(() => DiscoverOnboarding(controller: c, initial: p, isEdit: true));
                      } else if (v == 'pause') {
                        await c.setEnabled(!c.enabled.value);
                        Get.snackbar('Discover', c.enabled.value ? "You're visible again 👁️" : "You're now hidden 🙈");
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text("⚙️ Edit preferences")),
                      PopupMenuItem(value: 'pause', child: Text(c.enabled.value ? "🙈 Pause (go hidden)" : "👁️ Resume (be visible)")),
                    ],
                  ),
                ])
              : const SizedBox.shrink()),
        ],
      ),
      body: Obx(() {
        if (c.loading.value) return const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)));
        if (c.inCouple.value) {
          return _msg("💑", "You're connected with a partner",
              "Discover is only for singles. Disconnect your partner to use it.");
        }
        if (!c.onboarded.value) return DiscoverOnboarding(controller: c);
        return DiscoverHome(controller: c, initialTab: widget.initialTab, singleMode: widget.singleMode);
      }),
    );
  }

  Widget _msg(String emoji, String title, String sub) => Center(
    child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 54)),
      const SizedBox(height: 14),
      Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
      const SizedBox(height: 8),
      Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF94A3B8))),
    ])),
  );
}

// ── Onboarding (single scroll form for MVP) ──
class DiscoverOnboarding extends StatefulWidget {
  final DiscoverController controller;
  final Map<String, dynamic>? initial;   // prefill (edit mode)
  final bool isEdit;
  const DiscoverOnboarding({super.key, required this.controller, this.initial, this.isEdit = false});
  @override
  State<DiscoverOnboarding> createState() => _DiscoverOnboardingState();
}

class _DiscoverOnboardingState extends State<DiscoverOnboarding> {
  final _purposes = <String>{};
  final _interests = <String>{};
  String _gender = 'male';
  String _want = 'everyone';
  final _age = TextEditingController(text: '20');
  RangeValues _ageRange = const RangeValues(18, 30);
  double _distance = 50;
  final _city = TextEditingController();
  final _bio = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    if (d != null && d.isNotEmpty) {
      _purposes.addAll(((d['purposes'] as List?) ?? []).map((e) => e.toString()));
      _interests.addAll(((d['interests'] as List?) ?? []).map((e) => e.toString()));
      _gender = (d['gender'] ?? 'male').toString();
      _want = (d['wantGender'] ?? 'everyone').toString();
      _age.text = (d['age'] ?? 20).toString();
      final double mn = ((d['ageMin'] ?? 18) as num).toDouble().clamp(18.0, 60.0).toDouble();
      final double mx = ((d['ageMax'] ?? 30) as num).toDouble().clamp(mn, 60.0).toDouble();
      _ageRange = RangeValues(mn, mx);
      _distance = ((d['distanceKm'] ?? 50) as num).toDouble().clamp(5.0, 100.0).toDouble();
      _city.text = (d['city'] ?? '').toString();
      _bio.text = (d['bio'] ?? '').toString();
    }
  }

  Future<void> _save() async {
    if (_purposes.isEmpty) { Get.snackbar('Pick one', 'Choose what you are looking for'); return; }
    setState(() => _saving = true);
    final ok = await widget.controller.submitOnboarding({
      'age': int.tryParse(_age.text) ?? 20, 'gender': _gender, 'city': _city.text.trim(), 'bio': _bio.text.trim(),
      'purposes': _purposes.toList(), 'wantGender': _want,
      'ageMin': _ageRange.start.round(), 'ageMax': _ageRange.end.round(),
      'distanceKm': _distance.round(), 'interests': _interests.toList(),
    });
    setState(() => _saving = false);
    if (ok) {
      await widget.controller.pushLocation();
      if (widget.isEdit) { Get.back(); Get.snackbar('Updated ✨', 'Preferences saved'); }
      else { widget.controller.fetchStatus(); }
    } else {
      Get.snackbar('Error', 'Could not save. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: on)));
    Widget chip(String txt, bool sel, VoidCallback tap) => GestureDetector(onTap: tap, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: sel ? const Color(0xFFE8467C) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? Colors.transparent : const Color(0xFF94A3B8).withOpacity(.25))),
      child: Text(txt, style: TextStyle(color: sel ? Colors.white : on, fontSize: 12.5, fontWeight: FontWeight.w600)),
    ));

    final body = ListView(padding: const EdgeInsets.all(16), children: [
      Text(widget.isEdit ? "Edit your preferences" : "Set up your Discover profile", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: on)),
      const Text("Change these anytime — who you want, age, distance, interests.", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
      label("What are you looking for?"),
      Wrap(spacing: 8, runSpacing: 8, children: kPurposes.entries.map((e) => chip(e.value, _purposes.contains(e.key),
          () => setState(() => _purposes.contains(e.key) ? _purposes.remove(e.key) : _purposes.add(e.key)))).toList()),
      label("I am"),
      Row(children: [for (final g in ['male','female','other']) Padding(padding: const EdgeInsets.only(right: 8),
          child: chip(g[0].toUpperCase()+g.substring(1), _gender==g, () => setState(() => _gender=g)))]),
      label("Show me"),
      Row(children: [for (final g in ['male','female','everyone']) Padding(padding: const EdgeInsets.only(right: 8),
          child: chip(g[0].toUpperCase()+g.substring(1), _want==g, () => setState(() => _want=g)))]),
      label("Your age"),
      TextField(controller: _age, keyboardType: TextInputType.number, style: TextStyle(color: on),
        decoration: InputDecoration(filled: true, fillColor: Theme.of(context).cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      label("Age range you want: ${_ageRange.start.round()}–${_ageRange.end.round()}"),
      RangeSlider(values: _ageRange, min: 18, max: 60, activeColor: const Color(0xFFE8467C),
        onChanged: (v) => setState(() => _ageRange = v)),
      label("Max distance: ${_distance.round()} km"),
      Slider(value: _distance, min: 5, max: 100, activeColor: const Color(0xFFE8467C),
        onChanged: (v) => setState(() => _distance = v)),
      label("City (optional)"),
      TextField(controller: _city, style: TextStyle(color: on),
        decoration: InputDecoration(hintText: "e.g. Delhi", filled: true, fillColor: Theme.of(context).cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      label("Interests (tap to select)"),
      Wrap(spacing: 8, runSpacing: 8, children: kInterests.map((i) => chip(i, _interests.contains(i),
          () => setState(() => _interests.contains(i) ? _interests.remove(i) : _interests.add(i)))).toList()),
      label("Short bio (optional)"),
      TextField(controller: _bio, maxLines: 3, style: TextStyle(color: on),
        decoration: InputDecoration(hintText: "Tell people about you…", filled: true, fillColor: Theme.of(context).cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C), padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: _saving ? null : _save,
        child: _saving ? const SizedBox(height:18,width:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white))
            : Text(widget.isEdit ? "Save changes" : "Start Discovering ✨", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
      const SizedBox(height: 30),
    ]);
    // As the Discover entry screen it's placed inside DiscoverScreen's Scaffold.
    // In edit mode it's pushed as its own route, so it needs its own Scaffold
    // (otherwise text renders unstyled with yellow underlines).
    if (widget.isEdit) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          foregroundColor: on,
          title: const Text("Edit preferences", style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: body,
      );
    }
    return body;
  }
}

// Shared avatar with online dot.
Widget dvAvatar(BuildContext ctx, String? url, String? name, bool online) => Stack(children: [
  CircleAvatar(radius: 26, backgroundColor: const Color(0xFFE8467C).withOpacity(.15),
    backgroundImage: (url != null && url.toString().isNotEmpty) ? NetworkImage(url) : null,
    child: (url == null || url.toString().isEmpty)
      ? Text((name ?? '?').toString().isNotEmpty ? name![0].toUpperCase() : '?',
          style: const TextStyle(color: Color(0xFFE8467C), fontWeight: FontWeight.bold, fontSize: 20)) : null),
  if (online) Positioned(right: 0, bottom: 0, child: Container(width: 13, height: 13,
    decoration: BoxDecoration(color: const Color(0xFF22C55E), shape: BoxShape.circle, border: Border.all(color: Theme.of(ctx).scaffoldBackgroundColor, width: 2)))),
]);

Widget dvEmpty(BuildContext ctx, String t, String s) => Center(child: Padding(padding: const EdgeInsets.all(28),
  child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Text("✨", style: TextStyle(fontSize: 44)), const SizedBox(height: 12),
    Text(t, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.onSurface)),
    const SizedBox(height: 6), Text(s, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF94A3B8))),
  ])));

// ── Discover Home: 7 tabs + filters + feed ads ──
class DiscoverHome extends StatefulWidget {
  final DiscoverController controller;
  final int initialTab;
  final bool singleMode;
  const DiscoverHome({super.key, required this.controller, this.initialTab = 0, this.singleMode = false});
  @override
  State<DiscoverHome> createState() => _DiscoverHomeState();
}

class _DiscoverHomeState extends State<DiscoverHome> with SingleTickerProviderStateMixin {
  late TabController _tab;
  int _filterVer = 0; // bump to force feed reload after filter change

  @override
  void initState() { super.initState(); _tab = TabController(length: 7, vsync: this, initialIndex: widget.initialTab.clamp(0, 6)); widget.controller.pushLocation(); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  void _openFilters() {
    final f = widget.controller.filters;
    String gender = f['gender'] ?? 'everyone';
    bool onlineOnly = f['onlineOnly'] == 'true';
    bool verifiedOnly = f['verifiedOnly'] == 'true';
    double maxKm = double.tryParse(f['maxKm'] ?? '') ?? 50;
    Get.bottomSheet(StatefulBuilder(builder: (ctx, setSt) {
      final on = Theme.of(ctx).colorScheme.onSurface;
      Widget gchip(String g) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
        label: Text(g[0].toUpperCase()+g.substring(1)), selected: gender==g,
        selectedColor: const Color(0xFFE8467C), labelStyle: TextStyle(color: gender==g?Colors.white:on),
        onSelected: (_) => setSt(() => gender=g)));
      return Container(padding: const EdgeInsets.fromLTRB(20,14,20,28),
        decoration: BoxDecoration(color: Theme.of(ctx).cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width:42,height:5,decoration: BoxDecoration(color: const Color(0xFF94A3B8).withOpacity(.35), borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 14),
          Text("🔍 Filters", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: on)),
          const SizedBox(height: 14),
          Text("Show", style: TextStyle(color: on, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [gchip('male'), gchip('female'), gchip('everyone')]),
          const SizedBox(height: 8),
          Text("Max distance: ${maxKm.round()} km", style: TextStyle(color: on)),
          Slider(value: maxKm, min: 5, max: 100, activeColor: const Color(0xFFE8467C), onChanged: (v)=>setSt(()=>maxKm=v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, activeColor: const Color(0xFFE8467C),
            title: Text("Online only", style: TextStyle(color: on)), value: onlineOnly, onChanged: (v)=>setSt(()=>onlineOnly=v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, activeColor: const Color(0xFFE8467C),
            title: Text("Verified only", style: TextStyle(color: on)), value: verifiedOnly, onChanged: (v)=>setSt(()=>verifiedOnly=v)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
            onPressed: () {
              widget.controller.filters.assignAll({
                'gender': gender, 'maxKm': maxKm.round().toString(),
                'onlineOnly': onlineOnly.toString(), 'verifiedOnly': verifiedOnly.toString(),
              });
              Get.back();
              setState(() => _filterVer++);
            },
            child: const Text("Apply", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
        ]));
    }));
  }

  @override
  Widget build(BuildContext context) {
    final tabView = TabBarView(
      controller: _tab,
      physics: widget.singleMode ? const NeverScrollableScrollPhysics() : null,
      children: [
        _FeedList(widget.controller, 'nearby', key: ValueKey('nearby$_filterVer')),
        _FeedList(widget.controller, 'recommended', key: ValueKey('rec$_filterVer')),
        _FeedList(widget.controller, 'online', key: ValueKey('online$_filterVer')),
        _FeedList(widget.controller, 'new', key: ValueKey('new$_filterVer')),
        _RequestsTab(widget.controller),
        _FavoritesTab(widget.controller),
        _ChatsTab(widget.controller),
      ],
    );

    // Single Mode: Discover's sections become the app's FOOTER (bottom nav),
    // replacing all the partner tabs.
    if (widget.singleMode) {
      const map = [0, 2, 4, 5, 6]; // footer item → tab index
      int cur = map.indexOf(_tab.index); if (cur < 0) cur = 0;
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: tabView,
        floatingActionButton: FloatingActionButton.small(
          backgroundColor: const Color(0xFFE8467C),
          onPressed: _openFilters,
          child: const Icon(Icons.tune, color: Colors.white),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: cur,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).cardColor,
          selectedItemColor: const Color(0xFFE8467C),
          unselectedItemColor: const Color(0xFF94A3B8),
          onTap: (i) => setState(() => _tab.index = map[i]),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.explore_outlined), label: 'Discover'),
            BottomNavigationBarItem(icon: Icon(Icons.circle, size: 12), label: 'Online'),
            BottomNavigationBarItem(icon: Icon(Icons.favorite_border), label: 'Requests'),
            BottomNavigationBarItem(icon: Icon(Icons.star_border), label: 'Favorites'),
            BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
          ],
        ),
      );
    }

    return Column(children: [
      Row(children: [
        Expanded(child: TabBar(controller: _tab, isScrollable: true, tabAlignment: TabAlignment.start,
          labelColor: const Color(0xFFE8467C), unselectedLabelColor: const Color(0xFF94A3B8),
          indicatorColor: const Color(0xFFE8467C), tabs: const [
            Tab(text:"📍 Nearby"), Tab(text:"✨ For You"), Tab(text:"🟢 Online"), Tab(text:"🆕 New"),
            Tab(text:"❤️ Requests"), Tab(text:"⭐ Favorites"), Tab(text:"💬 Chats"),
          ])),
        IconButton(icon: const Icon(Icons.tune, color: Color(0xFFE8467C)), onPressed: _openFilters),
      ]),
      Expanded(child: tabView),
    ]);
  }
}

// A ranked feed (nearby/recommended/online/new) with Wave/Favorite/Connect + ads.
class _FeedList extends StatefulWidget {
  final DiscoverController c; final String mode;
  const _FeedList(this.c, this.mode, {super.key});
  @override
  State<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<_FeedList> {
  List<Map<String, dynamic>>? _users;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final u = await widget.c.feed(widget.mode); if (mounted) setState(() => _users = u); }

  @override
  Widget build(BuildContext context) {
    if (_users == null) return const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)));
    if (_users!.isEmpty) return dvEmpty(context, "No one here yet", "Try widening filters or check back later.");
    final on = Theme.of(context).colorScheme.onSurface;
    // Insert an ad after every 6 cards.
    final items = <Widget>[];
    for (var i = 0; i < _users!.length; i++) {
      items.add(_card(_users![i], on));
      if ((i + 1) % 6 == 0) items.add(const AdBanner('memories')); // reuse an app-ad placement
    }
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: items));
  }

  Widget _card(Map<String, dynamic> u, Color on) {
    final fav = RxBool(u['favorited'] == true);
    return GestureDetector(
      onTap: () => Get.to(() => DiscoverProfileScreen(id: u['id'].toString(), controller: widget.c)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF94A3B8).withOpacity(.12))),
        child: Row(children: [
          dvAvatar(context, u['avatar'], u['name'], u['online'] == true),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text("${u['name'] ?? ''}, ${u['age'] ?? ''}", overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, color: on, fontSize: 15))),
              if (u['verified'] == true) const Padding(padding: EdgeInsets.only(left:4), child: Icon(Icons.verified, color: Color(0xFF3B82F6), size: 15)),
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal:6,vertical:2), decoration: BoxDecoration(color: const Color(0xFFE8467C).withOpacity(.12), borderRadius: BorderRadius.circular(8)),
                child: Text("${u['match'] ?? 0}%", style: const TextStyle(color: Color(0xFFE8467C), fontSize: 10, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 2),
            Text([
              if (u['distanceKm'] != null) "${u['distanceKm']} km away",
              if ((u['area'] ?? '').toString().isNotEmpty) u['area'],
              if ((u['city'] ?? '').toString().isNotEmpty) u['city'],
            ].where((e)=>e!=null).join(' · '), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            const SizedBox(height: 4),
            Wrap(spacing: 4, children: ((u['interests'] as List?) ?? []).take(3).map((t) => Text("#$t",
                style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 11))).toList().cast<Widget>()),
          ])),
          Column(children: [
            IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              icon: const Text("👋", style: TextStyle(fontSize: 18)),
              onPressed: () => widget.c.wave(u['id'].toString())),
            const SizedBox(height: 6),
            Obx(() => IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              icon: Icon(fav.value ? Icons.star : Icons.star_border, color: const Color(0xFFF59E0B), size: 22),
              onPressed: () async { final r = await widget.c.toggleFavorite(u['id'].toString()); fav.value = r; })),
          ]),
          const SizedBox(width: 4),
          IconButton(icon: const Icon(Icons.favorite, color: Color(0xFFE8467C)),
            onPressed: () => widget.c.sendRequest(u['id'].toString())),
        ]),
      ),
    );
  }
}

class _RequestsTab extends StatefulWidget {
  final DiscoverController c; const _RequestsTab(this.c);
  @override State<_RequestsTab> createState() => _RequestsTabState();
}
class _RequestsTabState extends State<_RequestsTab> {
  List<Map<String, dynamic>>? _reqs;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final r = await widget.c.requests(); if (mounted) setState(() => _reqs = r); }
  @override
  Widget build(BuildContext context) {
    if (_reqs == null) return const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)));
    if (_reqs!.isEmpty) return dvEmpty(context, "No requests yet", "When someone wants to connect, they'll show here.");
    final on = Theme.of(context).colorScheme.onSurface;
    return RefreshIndicator(onRefresh: _load, child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: _reqs!.length, itemBuilder: (_, i) {
      final r = _reqs![i];
      return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          dvAvatar(context, r['avatar'], r['name'], false),
          const SizedBox(width: 12),
          Expanded(child: Text("${r['name'] ?? 'Someone'}, ${r['age'] ?? ''}\nwants to connect", style: TextStyle(color: on, fontWeight: FontWeight.w600, fontSize: 13))),
          IconButton(icon: const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 30),
            onPressed: () async { final m = await widget.c.respond(r['requestId'].toString(), true);
              if (m?['matched'] == true) Get.snackbar('Soul Connected 💜', "You can now chat!"); _load(); }),
          IconButton(icon: const Icon(Icons.cancel, color: Color(0xFFEF4444), size: 30),
            onPressed: () async { await widget.c.respond(r['requestId'].toString(), false); _load(); }),
        ]));
    }));
  }
}

class _FavoritesTab extends StatefulWidget {
  final DiscoverController c; const _FavoritesTab(this.c);
  @override State<_FavoritesTab> createState() => _FavoritesTabState();
}
class _FavoritesTabState extends State<_FavoritesTab> {
  List<Map<String, dynamic>>? _list;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final r = await widget.c.favorites(); if (mounted) setState(() => _list = r); }
  @override
  Widget build(BuildContext context) {
    if (_list == null) return const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)));
    if (_list!.isEmpty) return dvEmpty(context, "No favorites yet", "Tap ⭐ on a profile to save them here.");
    final on = Theme.of(context).colorScheme.onSurface;
    return RefreshIndicator(onRefresh: _load, child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: _list!.length, itemBuilder: (_, i) {
      final u = _list![i];
      return ListTile(
        onTap: () => Get.to(() => DiscoverProfileScreen(id: u['id'].toString(), controller: widget.c)),
        leading: dvAvatar(context, u['avatar'], u['name'], u['online'] == true),
        title: Text("${u['name'] ?? ''}, ${u['age'] ?? ''}", style: TextStyle(color: on, fontWeight: FontWeight.w700)),
        subtitle: Text(u['city'] ?? '', style: const TextStyle(color: Color(0xFF94A3B8))),
        trailing: IconButton(icon: const Icon(Icons.favorite, color: Color(0xFFE8467C)),
          onPressed: () => widget.c.sendRequest(u['id'].toString())),
      );
    }));
  }
}

class _ChatsTab extends StatefulWidget {
  final DiscoverController c; const _ChatsTab(this.c);
  @override State<_ChatsTab> createState() => _ChatsTabState();
}
class _ChatsTabState extends State<_ChatsTab> {
  List<Map<String, dynamic>>? _m;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final r = await widget.c.matches(); if (mounted) setState(() => _m = r); }
  @override
  Widget build(BuildContext context) {
    if (_m == null) return const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)));
    if (_m!.isEmpty) return dvEmpty(context, "No matches yet", "Accepted connections appear here — tap to chat.");
    final on = Theme.of(context).colorScheme.onSurface;
    return RefreshIndicator(onRefresh: _load, child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: _m!.length, itemBuilder: (_, i) {
      final m = _m![i];
      return ListTile(
        leading: dvAvatar(context, m['avatar'], m['name'], false),
        title: Text(m['name'] ?? 'User', style: TextStyle(color: on, fontWeight: FontWeight.w700)),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
        onTap: () => Get.to(() => DiscoverChatScreen(matchId: m['matchId'].toString(), name: m['name'] ?? 'User')),
      );
    }));
  }
}

// ── Full profile view (tap a card) ──
class DiscoverProfileScreen extends StatefulWidget {
  final String id; final DiscoverController controller;
  const DiscoverProfileScreen({super.key, required this.id, required this.controller});
  @override State<DiscoverProfileScreen> createState() => _DiscoverProfileScreenState();
}
class _DiscoverProfileScreenState extends State<DiscoverProfileScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _p;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final r = await _api.get('/discover/profile?id=${widget.id}'); if (mounted) setState(() => _p = Map<String,dynamic>.from(r.data['data'] ?? {})); } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0,
        iconTheme: IconThemeData(color: on),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: on),
            onSelected: (v) {
              if (v == 'report') {
                final rc = TextEditingController();
                Get.dialog(AlertDialog(backgroundColor: Theme.of(context).cardColor,
                  title: const Text("Report user"),
                  content: TextField(controller: rc, decoration: const InputDecoration(hintText: "Reason (optional)")),
                  actions: [
                    TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                      onPressed: () { Get.back(); widget.controller.report(widget.id, rc.text.trim()); },
                      child: const Text("Report", style: TextStyle(color: Colors.white))),
                  ]));
              } else if (v == 'block') {
                Get.dialog(AlertDialog(backgroundColor: Theme.of(context).cardColor,
                  title: const Text("Block user?"),
                  content: const Text("You won't see each other in Discover."),
                  actions: [
                    TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                      onPressed: () { Get.back(); widget.controller.block(widget.id); Get.back(); },
                      child: const Text("Block", style: TextStyle(color: Colors.white))),
                  ]));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text("🚩 Report")),
              PopupMenuItem(value: 'block', child: Text("🚫 Block")),
            ],
          ),
        ]),
      body: _p == null ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
        : ListView(padding: const EdgeInsets.all(20), children: [
          Center(child: dvAvatar(context, _p!['avatar'], _p!['name'], _p!['online'] == true)),
          const SizedBox(height: 12),
          Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text("${_p!['name'] ?? ''}, ${_p!['age'] ?? ''}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: on)),
            if (_p!['verified'] == true) const Padding(padding: EdgeInsets.only(left:6), child: Icon(Icons.verified, color: Color(0xFF3B82F6), size: 20)),
          ])),
          if ((_p!['city'] ?? '').toString().isNotEmpty) Center(child: Text(_p!['city'], style: const TextStyle(color: Color(0xFF94A3B8)))),
          if (((_p!['badges'] as List?) ?? []).isNotEmpty) ...[
            const SizedBox(height: 10),
            Center(child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
              children: ((_p!['badges'] as List?) ?? []).map((b) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: const Color(0xFFE8467C).withOpacity(.10), borderRadius: BorderRadius.circular(20)),
                child: Text(b.toString(), style: const TextStyle(fontSize: 11, color: Color(0xFFE8467C), fontWeight: FontWeight.w600)))).toList().cast<Widget>())),
          ],
          const SizedBox(height: 16),
          if ((_p!['bio'] ?? '').toString().isNotEmpty) ...[
            Text("About", style: TextStyle(fontWeight: FontWeight.w800, color: on)),
            const SizedBox(height: 6), Text(_p!['bio'], style: TextStyle(color: on.withOpacity(.8))), const SizedBox(height: 16),
          ],
          Text("Interests", style: TextStyle(fontWeight: FontWeight.w800, color: on)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: ((_p!['interests'] as List?) ?? []).map((t) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFF7C3AED).withOpacity(.12), borderRadius: BorderRadius.circular(20)),
            child: Text("#$t", style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 12)))).toList().cast<Widget>()),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => widget.controller.wave(widget.id),
              icon: const Text("👋"), label: const Text("Wave"))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8467C)),
              onPressed: () => widget.controller.sendRequest(widget.id),
              icon: const Icon(Icons.favorite, color: Colors.white, size: 18),
              label: const Text("Connect", style: TextStyle(color: Colors.white)))),
          ]),
        ]),
    );
  }
}

// ── Discover match chat ──
class DiscoverChatScreen extends StatefulWidget {
  final String matchId; final String name;
  const DiscoverChatScreen({super.key, required this.matchId, required this.name});
  @override
  State<DiscoverChatScreen> createState() => _DiscoverChatScreenState();
}

class _DiscoverChatScreenState extends State<DiscoverChatScreen> {
  final ApiService _api = ApiService();
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _msgs = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await _api.get('/discover/chat/list?matchId=${widget.matchId}');
      final list = (r.data['data'] as List?) ?? [];
      if (mounted) setState(() => _msgs = list.map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (_) {}
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim(); if (t.isEmpty) return;
    _ctrl.clear();
    try { await _api.post('/discover/chat/send', data: {'matchId': widget.matchId, 'content': t}); } catch (_) {}
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final myId = Get.find<AuthController>().currentUser.value?.id ?? '';
    final on = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0,
        title: Text(widget.name, style: TextStyle(color: on))),
      body: Column(children: [
        Expanded(child: ListView.builder(reverse: true, padding: const EdgeInsets.all(12), itemCount: _msgs.length,
          itemBuilder: (_, i) {
            final m = _msgs[i]; final me = m['senderId'].toString() == myId;
            return Align(alignment: me ? Alignment.centerRight : Alignment.centerLeft, child: Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .7),
              decoration: BoxDecoration(color: me ? const Color(0xFFE8467C) : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16)),
              child: Text(m['content'] ?? '', style: TextStyle(color: me ? Colors.white : on)),
            ));
          })),
        Container(padding: const EdgeInsets.all(8), color: Theme.of(context).scaffoldBackgroundColor,
          child: Row(children: [
            Expanded(child: TextField(controller: _ctrl, style: TextStyle(color: on),
              decoration: InputDecoration(hintText: "Message", filled: true, fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16)))),
            IconButton(icon: const Icon(Icons.send, color: Color(0xFFE8467C)), onPressed: _send),
          ])),
      ]),
    );
  }
}

// ── Who viewed you (Premium / rewarded-ad unlock) ──
class DiscoverViewsScreen extends StatefulWidget {
  final DiscoverController controller;
  const DiscoverViewsScreen({super.key, required this.controller});
  @override
  State<DiscoverViewsScreen> createState() => _DiscoverViewsScreenState();
}

class _DiscoverViewsScreenState extends State<DiscoverViewsScreen> {
  Map<String, dynamic>? _d;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final d = await widget.controller.viewsData(); if (mounted) setState(() => _d = d); }

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(backgroundColor: Theme.of(context).scaffoldBackgroundColor, elevation: 0,
        iconTheme: IconThemeData(color: on),
        title: Text("Who viewed you 👀", style: TextStyle(color: on))),
      body: _d == null ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8467C)))
        : (_d!['locked'] == true)
          ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text("👀", style: TextStyle(fontSize: 54)),
              const SizedBox(height: 12),
              Text("${_d!['count'] ?? 0} people viewed your profile",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: on)),
              const SizedBox(height: 6),
              const Text("Unlock to see who they are.", style: TextStyle(color: Color(0xFF94A3B8))),
              const SizedBox(height: 22),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () => widget.controller.unlockViewsWithAd(_load),
                icon: const Text("🎬"), label: const Text("Watch ad → see for 24h", style: TextStyle(color: Colors.white)))),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: () => Get.find<AuthController>().openPremiumSheet(),
                icon: const Text("👑"), label: const Text("Go Premium (unlimited)"))),
            ])))
          : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12),
              children: ((_d!['users'] as List?) ?? []).map((u) => ListTile(
                onTap: () => Get.to(() => DiscoverProfileScreen(id: u['id'].toString(), controller: widget.controller)),
                leading: dvAvatar(context, u['avatar'], u['name'], false),
                title: Text("${u['name'] ?? ''}, ${u['age'] ?? ''}", style: TextStyle(color: on, fontWeight: FontWeight.w700)),
                subtitle: Text(u['city'] ?? '', style: const TextStyle(color: Color(0xFF94A3B8))),
                trailing: IconButton(icon: const Icon(Icons.favorite, color: Color(0xFFE8467C)),
                  onPressed: () => widget.controller.sendRequest(u['id'].toString())),
              )).toList().cast<Widget>())),
    );
  }
}
