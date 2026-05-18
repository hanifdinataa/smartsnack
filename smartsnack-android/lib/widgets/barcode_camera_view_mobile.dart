import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────────────────────────
// Top-level function untuk compute() isolate.
// Harus top-level (bukan method instance) agar bisa di-spawn ke isolate.
// Menerima Map berisi raw plane bytes + metadata, mengembalikan JPEG bytes.
// ─────────────────────────────────────────────────────────────────────────────
Uint8List _convertFrameInIsolate(Map<String, dynamic> args) {
  final format = args['format'] as String;
  final width = args['width'] as int;
  final height = args['height'] as int;

  img.Image frame;

  if (format == 'yuv420') {
    final yBytes = args['y'] as Uint8List;
    final uBytes = args['u'] as Uint8List;
    final vBytes = args['v'] as Uint8List;
    final yRowStride = args['yRowStride'] as int;
    final uvRowStride = args['uvRowStride'] as int;
    final uvPixelStride = args['uvPixelStride'] as int;

    final out = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      final yOffset = y * yRowStride;
      final uvOffset = (y >> 1) * uvRowStride;
      for (var x = 0; x < width; x++) {
        final yValue = yBytes[yOffset + x].toDouble();
        final uvIndex = uvOffset + (x >> 1) * uvPixelStride;
        final uValue = uBytes[uvIndex].toDouble() - 128.0;
        final vValue = vBytes[uvIndex].toDouble() - 128.0;
        int r = (yValue + 1.402 * vValue).round().clamp(0, 255);
        int g = (yValue - 0.344136 * uValue - 0.714136 * vValue).round().clamp(0, 255);
        int b = (yValue + 1.772 * uValue).round().clamp(0, 255);
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    frame = out;
  } else if (format == 'bgra8888') {
    final bytes = args['bytes'] as Uint8List;
    final out = img.Image(width: width, height: height);
    var i = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final b = bytes[i];
        final g = bytes[i + 1];
        final r = bytes[i + 2];
        out.setPixelRgb(x, y, r, g, b);
        i += 4;
      }
    }
    frame = out;
  } else {
    // Fallback: kembalikan empty
    return Uint8List(0);
  }

  // Rotate jika landscape
  if (frame.width > frame.height) {
    frame = img.copyRotate(frame, angle: 90);
  }

  // Center-crop menjadi square agar classifier mendapat input konsisten
  final side = frame.width < frame.height ? frame.width : frame.height;
  final cx = (frame.width - side) ~/ 2;
  final cy = (frame.height - side) ~/ 2;
  frame = img.copyCrop(frame, x: cx, y: cy, width: side, height: side);

  return Uint8List.fromList(img.encodeJpg(frame, quality: 72));
}

// ─────────────────────────────────────────────────────────────────────────────

class CameraCaptureView extends StatefulWidget {
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
  State<CameraCaptureView> createState() => _CameraCaptureViewState();
}

class _CameraCaptureViewState extends State<CameraCaptureView> {
  CameraController? _controller;
  bool _ready = false;
  String? _error;
  bool _capturing = false;
  bool _analyzing = false;
  bool _streamFrameInFlight = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);

  // FIX BUG C: Simpan args Map, bukan Uint8List, agar isolate dapat semua
  // data yang diperlukan untuk konversi tanpa akses ke CameraImage asli
  // (yang tidak valid setelah callback stream selesai).
  Map<String, dynamic>? _pendingFrameArgs;

  Timer? _frameWorker;
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    unawaited(_setup());
  }

  late final WidgetsBindingObserver _lifecycleObserver = _CameraLifecycleObserver(
    onPaused: () async {
      await _teardownCamera();
    },
    onResumed: () async {
      if (!mounted) return;
      await _setup();
    },
  );

  Future<void> _setup() async {
    if (_initializing) return;
    _initializing = true;
    try {
      await _teardownCamera();
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'Tidak ada kamera yang tersedia.');
        return;
      }
      final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back).toList();
      final cam = back.isNotEmpty ? back.first : cameras.first;
      final controller = CameraController(
        cam,
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.yuv420,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      _controller = controller;
      setState(() {
        _ready = true;
        _error = null;
      });
      _startFrameWorker();
      await _startPreviewStream();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Kamera tidak bisa dibuka: $e');
    } finally {
      // FIX BUG D: _initializing HARUS direset di finally, termasuk saat
      // exception terjadi, agar _setup() bisa dipanggil ulang pada resume.
      _initializing = false;
    }
  }

  Future<void> _startPreviewStream() async {
    final controller = _controller;
    if (controller == null || widget.onFrameCaptured == null) return;

    // FIX BUG D: Guard terhadap double-start stream. Tanpa ini, jika
    // _startPreviewStream dipanggil dua kali (misal setelah capture),
    // Android camera2 akan throw CameraException karena stream sudah aktif.
    if (controller.value.isStreamingImages) return;

    await controller.startImageStream((CameraImage image) {
      if (!mounted || widget.isProcessing || _capturing) return;

      final now = DateTime.now();
      // FIX BUG B: Kurangi throttle 500ms → 200ms.
      // 200ms = max ~5fps untuk inference preview — responsif tapi tidak
      // membanjiri pipeline TFLite yang sync.
      if (now.difference(_lastFrameAt).inMilliseconds < 200) return;
      _lastFrameAt = now;

      // Salin semua data plane ke Uint8List biasa SEBELUM callback selesai,
      // karena CameraImage buffer mungkin di-reclaim setelah return.
      // FIX: Tidak lewatkan CameraImage langsung ke isolate (tidak serializable),
      // tapi ekstrak data mentah ke Map<String, dynamic> yang bisa di-compute().
      try {
        _pendingFrameArgs = _extractFrameArgs(image);
      } catch (_) {
        // Abaikan frame yang gagal diextract
      }
    });
  }

  /// Ekstrak semua data dari CameraImage ke Map plain-Dart yang aman disimpan
  /// dan dikirim ke isolate via compute().
  Map<String, dynamic>? _extractFrameArgs(CameraImage image) {
    if (image.format.group == ImageFormatGroup.yuv420 && image.planes.length >= 3) {
      return {
        'format': 'yuv420',
        'width': image.width,
        'height': image.height,
        // Salin bytes — jangan simpan referensi asli (bisa di-GC)
        'y': Uint8List.fromList(image.planes[0].bytes),
        'u': Uint8List.fromList(image.planes[1].bytes),
        'v': Uint8List.fromList(image.planes[2].bytes),
        'yRowStride': image.planes[0].bytesPerRow,
        'uvRowStride': image.planes[1].bytesPerRow,
        'uvPixelStride': image.planes[1].bytesPerPixel ?? 1,
      };
    }
    if (image.format.group == ImageFormatGroup.bgra8888 && image.planes.isNotEmpty) {
      return {
        'format': 'bgra8888',
        'width': image.width,
        'height': image.height,
        'bytes': Uint8List.fromList(image.planes[0].bytes),
      };
    }
    return null;
  }

  void _startFrameWorker() {
    _frameWorker?.cancel();
    if (widget.onFrameCaptured == null) return;
    // FIX BUG B: Poll setiap 120ms (sebelumnya 350ms).
    // 120ms membuat worker segera mengambil frame baru setelah inference
    // selesai, mengurangi latency overlay label secara signifikan.
    _frameWorker = Timer.periodic(const Duration(milliseconds: 120), (_) {
      unawaited(_drainPendingFrame());
    });
  }

  Future<void> _drainPendingFrame() async {
    if (_streamFrameInFlight || widget.isProcessing || _capturing) return;
    final args = _pendingFrameArgs;
    if (args == null) return;
    _pendingFrameArgs = null;
    _streamFrameInFlight = true;
    try {
      // FIX BUG E: Jalankan konversi YUV→JPEG di background isolate via compute().
      // Sebelumnya konversi dilakukan synchronous di callback stream atau di
      // worker timer (keduanya memblokir Dart main isolate).
      // compute() menggunakan Flutter's isolate pool — aman, tidak ada shared state.
      final bytes = await compute(_convertFrameInIsolate, args);
      if (bytes.isEmpty) return;
      await widget.onFrameCaptured?.call(bytes);
    } catch (_) {
      // Frame inference boleh gagal — jangan crash app
    } finally {
      _streamFrameInFlight = false;
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _capturing) {
      return;
    }
    if (mounted) {
      setState(() => _capturing = true);
    } else {
      _capturing = true;
    }

    // FIX BUG C: Stop worker DULU sebelum stopImageStream agar timer tick
    // yang terjadi tepat saat capture tidak mencoba drain frame sambil
    // stream sedang di-stop (race condition → CameraException di Android).
    _frameWorker?.cancel();
    _frameWorker = null;

    // FIX BUG C: Buang frame lama — tidak relevan lagi setelah tombol ditekan
    _pendingFrameArgs = null;

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      await widget.onCapture(bytes);
    } catch (e) {
      // Tampilkan error ke user jika perlu, tapi jangan biarkan _capturing stuck
      debugPrint('[CameraCaptureView] Capture error: $e');
    } finally {
      if (mounted) {
        setState(() => _capturing = false);
      } else {
        _capturing = false;
      }
      // Restart worker dan stream setelah capture selesai (atau gagal)
      if (mounted && _controller != null) {
        _startFrameWorker();
        await _startPreviewStream();
      }
    }
  }

  Future<void> _analyzeCapture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _capturing ||
        _analyzing ||
        widget.onAnalyzeCapture == null) {
      return;
    }
    if (mounted) {
      setState(() => _analyzing = true);
    } else {
      _analyzing = true;
    }
    _frameWorker?.cancel();
    _frameWorker = null;
    _pendingFrameArgs = null;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      await widget.onAnalyzeCapture!(bytes);
    } catch (e) {
      debugPrint('[CameraCaptureView] Analyze error: $e');
    } finally {
      if (mounted) {
        setState(() => _analyzing = false);
      } else {
        _analyzing = false;
      }
      if (mounted && _controller != null) {
        _startFrameWorker();
        await _startPreviewStream();
      }
    }
  }

  Future<void> _teardownCamera() async {
    final controller = _controller;
    _controller = null;
    _pendingFrameArgs = null;
    _streamFrameInFlight = false;
    _frameWorker?.cancel();
    _frameWorker = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _frameWorker?.cancel();
    unawaited(_teardownCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        color: const Color(0xFF0E1B18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready && _controller != null) CameraPreview(_controller!),
            if (!_ready && _error == null) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: const TextStyle(color: Colors.white)),
                ),
              ),
            Positioned(
              left: 18,
              right: 18,
              top: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.previewLabelText ?? 'Arahkan produk ke kamera...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: FilledButton.icon(
                onPressed: (!_ready ||
                        widget.isProcessing ||
                        _error != null ||
                        _capturing ||
                        _analyzing)
                    ? null
                    : _capture,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(widget.captureLabel),
              ),
            ),
            if (widget.onAnalyzeCapture != null)
              Positioned(
                left: 18,
                right: 18,
                bottom: 78,
                child: OutlinedButton.icon(
                  onPressed: (!_ready ||
                          widget.isProcessing ||
                          _error != null ||
                          _capturing ||
                          _analyzing)
                      ? null
                      : _analyzeCapture,
                  icon: const Icon(Icons.search_outlined),
                  label: Text(_analyzing ? 'Mendeteksi...' : widget.analyzeLabel),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    backgroundColor: Colors.black45,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CameraLifecycleObserver extends WidgetsBindingObserver {
  _CameraLifecycleObserver({
    required this.onPaused,
    required this.onResumed,
  });

  final Future<void> Function() onPaused;
  final Future<void> Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(onPaused());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(onResumed());
    }
  }
}
