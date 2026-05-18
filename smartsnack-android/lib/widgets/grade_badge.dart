import 'package:flutter/material.dart';

class GradeBadge extends StatelessWidget {
  const GradeBadge({super.key, required this.grade});

  final String grade;

  @override
  Widget build(BuildContext context) {
    final normalized = grade.toLowerCase();
    // ─── OLD style matching ───
    // final style = switch (normalized) {
    //   'merah' => (label: 'Gula Tinggi', color: const Color(0xFFFF3C3C), text: Colors.white),
    //   'kuning' => (label: 'Gula Sedang', color: const Color(0xFFFFEB3B), text: Colors.black87),
    //   'hijau' => (label: 'Rendah Gula', color: const Color(0xFF77FF62), text: Colors.black87),
    //   _ => (label: grade, color: const Color(0xFF27B48A), text: Colors.white),
    // };
    // ─── NEW premium style matching ───
    final style = switch (normalized) {
      'merah' => (label: 'Gula Tinggi', bg: const Color(0xFFFEE2E2), text: const Color(0xFFDC2626)),
      'kuning' => (label: 'Gula Sedang', bg: const Color(0xFFFEF3C7), text: const Color(0xFFD97706)),
      'hijau' => (label: 'Rendah Gula', bg: const Color(0xFFD1FAE5), text: const Color(0xFF065F46)),
      _ => (label: grade, bg: const Color(0xFFD1FAE5), text: const Color(0xFF0D9F6E)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: style.text,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
