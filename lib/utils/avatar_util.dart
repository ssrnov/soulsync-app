import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:dio/dio.dart' as dio_pkg;
import '../services/api_service.dart';

// Illustrated character avatars — 10 boys + 10 girls (emoji on a gradient disc).
const List<String> kBoyChars = ['👦', '🧑', '👨', '🧔', '👨‍🦱', '👨‍🦰', '🧑‍🦱', '👨‍🦳', '🤵', '👳'];
const List<String> kGirlChars = ['👧', '👩', '👩‍🦰', '👩‍🦱', '👩‍🦳', '💁‍♀️', '👰', '🧕', '👸', '🙎‍♀️'];
const List<List<Color>> kCharColors = [
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

// Paints the emoji on a gradient disc and returns PNG bytes.
Future<Uint8List> renderCharacterPng(String emoji, Color c1, Color c2) async {
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

// Renders the chosen character and uploads it as the user's avatar.
// Requires the user to be authenticated (called after login/register).
Future<bool> uploadCharacterAvatar(String emoji, Color c1, Color c2) async {
  try {
    final bytes = await renderCharacterPng(emoji, c1, c2);
    final formData = dio_pkg.FormData.fromMap({
      'file': dio_pkg.MultipartFile.fromBytes(bytes, filename: 'character.png'),
    });
    final r = await ApiService().post('/auth/upload-avatar', data: formData);
    return r.statusCode == 200 && r.data['success'] == true;
  } catch (_) {
    return false;
  }
}
