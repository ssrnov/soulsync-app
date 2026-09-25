import 'dart:ui';
import 'package:flutter/material.dart';

// ── Glassmorphism Container ──────────────────────────────────────────────────
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final Color bordercolor;
  final Color bgcolor;
  final EdgeInsetsGeometry padding;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 16.0,
    this.blur = 15.0,
    this.bordercolor = const Color(0x33FFFFFF),
    this.bgcolor = const Color(0x1AFFFFFF),
    this.padding = const EdgeInsets.all(16.0),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: bgcolor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: bordercolor, width: 1.0),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

// ── Premium Gradient Button ──────────────────────────────────────────────────
class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isLoading;

  const GradientButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFE05CB0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}

// ── Custom Input Field ────────────────────────────────────────────────────────
class CustomInputField extends StatelessWidget {
  final String label;
  final String placeholder;
  final bool isPassword;
  final TextEditingController controller;
  final TextInputType keyboardType;

  const CustomInputField({
    super.key,
    required this.label,
    required this.placeholder,
    required this.controller,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white10),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Permission Wizard Step Card ──────────────────────────────────────────────
class PermissionStepCard extends StatelessWidget {
  final String title;
  final String description;
  final bool isGranted;
  final VoidCallback onTap;
  final String emoji;

  const PermissionStepCard({
    super.key,
    required this.title,
    required this.description,
    required this.isGranted,
    required this.onTap,
    this.emoji = "💗",
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isGranted ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: isGranted
              ? LinearGradient(colors: [
                  const Color(0xFF10B981).withOpacity(0.16),
                  const Color(0xFF10B981).withOpacity(0.05),
                ])
              : const LinearGradient(colors: [Color(0x33E8467C), Color(0x1A7C3AED)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isGranted ? const Color(0xFF10B981).withOpacity(0.5) : const Color(0x55E8467C),
          ),
          boxShadow: isGranted
              ? []
              : [BoxShadow(color: const Color(0xFFE8467C).withOpacity(0.18), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            // Emoji avatar
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(description, style: const TextStyle(color: Colors.white60, fontSize: 11.5, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Allow pill / granted check
            isGranted
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle, color: Color(0xFF10B981), size: 15),
                      SizedBox(width: 4),
                      Text("On", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w800, fontSize: 12)),
                    ]),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFE8467C), Color(0xFF7C3AED)]),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [BoxShadow(color: const Color(0xFFE8467C).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: const Text("Allow 💕", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                  ),
          ],
        ),
      ),
    );
  }
}
