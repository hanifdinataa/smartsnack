import 'dart:typed_data';

import 'package:flutter/material.dart';

class CameraCaptureView extends StatelessWidget {
  const CameraCaptureView({
    super.key,
    required this.onCapture,
    required this.isProcessing,
    this.captureLabel = 'Ambil Foto',
    this.onFrameCaptured,
    this.previewLabelText,
    this.onAnalyzeCapture,
    this.analyzeLabel = 'Deteksi Nama',
  });

  final Future<void> Function(Uint8List bytes) onCapture;
  final bool isProcessing;
  final String captureLabel;
  final Future<void> Function(Uint8List bytes)? onFrameCaptured;
  final String? previewLabelText;
  final Future<void> Function(Uint8List bytes)? onAnalyzeCapture;
  final String analyzeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE6F4EF),
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: Alignment.center,
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Mode kamera langsung tersedia di Flutter Web. Pada mobile, gunakan tombol buka kamera di halaman ini.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
