import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

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
  late final String _viewType;
  html.VideoElement? _video;
  html.MediaStream? _stream;
  bool _ready = false;
  String? _error;
  Timer? _frameTimer;
  bool _capturingFrame = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'nutrition-camera-view-${DateTime.now().microsecondsSinceEpoch}';
    unawaited(_setup());
  }

  Future<void> _setup() async {
    final video = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.border = '0'
      ..style.backgroundColor = '#000';

    _video = video;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => video);

    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw Exception('Browser tidak menyediakan akses kamera.');
      }

      html.MediaStream stream;
      try {
        stream = await mediaDevices.getUserMedia({
          'video': {
            'facingMode': {'ideal': 'environment'},
          },
          'audio': false,
        });
      } catch (_) {
        stream = await mediaDevices.getUserMedia({'video': true, 'audio': false});
      }

      _stream = stream;
      video.srcObject = stream;
      await video.play();

      if (mounted) {
        setState(() {
          _ready = true;
          _error = null;
        });
        _startPreviewFrames();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Kamera tidak bisa dibuka: $e';
        });
      }
    }
  }

  Future<void> _captureFrame() async {
    final video = _video;
    if (video == null || video.videoWidth <= 0 || video.videoHeight <= 0) {
      return;
    }

    final canvas = html.CanvasElement(
      width: video.videoWidth,
      height: video.videoHeight,
    );
    final ctx = canvas.context2D;
    ctx.drawImageScaled(
      video,
      0,
      0,
      video.videoWidth.toDouble(),
      video.videoHeight.toDouble(),
    );

    final blob = await canvas.toBlob('image/jpeg', 0.95);
    if (blob == null) return;

    final reader = html.FileReader();
    final completer = Completer<Uint8List>();
    reader.onLoadEnd.first.then((_) {
      final result = reader.result;
      if (result is Uint8List) {
        completer.complete(result);
        return;
      }
      if (result is ByteBuffer) {
        completer.complete(Uint8List.view(result));
        return;
      }
      completer.complete(Uint8List(0));
    });
    reader.readAsArrayBuffer(blob);

    final bytes = await completer.future;
    if (bytes.isEmpty) return;
    await widget.onCapture(bytes);
  }

  void _startPreviewFrames() {
    _frameTimer?.cancel();
    if (widget.onFrameCaptured == null) return;
    _frameTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      unawaited(_capturePreviewFrame());
    });
  }

  Future<void> _capturePreviewFrame() async {
    if (_capturingFrame || widget.isProcessing || !_ready || _error != null) {
      return;
    }
    final video = _video;
    if (video == null || video.videoWidth <= 0 || video.videoHeight <= 0) {
      return;
    }
    _capturingFrame = true;
    try {
      final canvas = html.CanvasElement(
        width: video.videoWidth,
        height: video.videoHeight,
      );
      final ctx = canvas.context2D;
      ctx.drawImageScaled(
        video,
        0,
        0,
        video.videoWidth.toDouble(),
        video.videoHeight.toDouble(),
      );
      final blob = await canvas.toBlob('image/jpeg', 0.75);
      if (blob == null) return;

      final reader = html.FileReader();
      final completer = Completer<Uint8List>();
      reader.onLoadEnd.first.then((_) {
        final result = reader.result;
        if (result is Uint8List) {
          completer.complete(result);
          return;
        }
        if (result is ByteBuffer) {
          completer.complete(Uint8List.view(result));
          return;
        }
        completer.complete(Uint8List(0));
      });
      reader.readAsArrayBuffer(blob);
      final bytes = await completer.future;
      if (bytes.isEmpty) return;
      await widget.onFrameCaptured?.call(bytes);
    } finally {
      _capturingFrame = false;
    }
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    for (final track in _stream?.getTracks() ?? const <html.MediaStreamTrack>[]) {
      track.stop();
    }
    _video?.pause();
    _video?.srcObject = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(24);

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        color: const Color(0xFF0E1B18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_error == null) HtmlElementView(viewType: _viewType),
            if (!_ready && _error == null)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white70, width: 2),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              top: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.58),
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
              bottom: 78,
              child: OutlinedButton.icon(
                onPressed: (!_ready || widget.isProcessing || _error != null || widget.onAnalyzeCapture == null)
                    ? null
                    : () async {
                        final video = _video;
                        if (video == null || video.videoWidth <= 0 || video.videoHeight <= 0) {
                          return;
                        }
                        final canvas = html.CanvasElement(
                          width: video.videoWidth,
                          height: video.videoHeight,
                        );
                        final ctx = canvas.context2D;
                        ctx.drawImageScaled(
                          video,
                          0,
                          0,
                          video.videoWidth.toDouble(),
                          video.videoHeight.toDouble(),
                        );
                        final blob = await canvas.toBlob('image/jpeg', 0.95);
                        if (blob == null) return;
                        final reader = html.FileReader();
                        final completer = Completer<Uint8List>();
                        reader.onLoadEnd.first.then((_) {
                          final result = reader.result;
                          if (result is Uint8List) {
                            completer.complete(result);
                            return;
                          }
                          if (result is ByteBuffer) {
                            completer.complete(Uint8List.view(result));
                            return;
                          }
                          completer.complete(Uint8List(0));
                        });
                        reader.readAsArrayBuffer(blob);
                        final bytes = await completer.future;
                        if (bytes.isEmpty) return;
                        await widget.onAnalyzeCapture?.call(bytes);
                      },
                icon: const Icon(Icons.search_outlined),
                label: Text(widget.analyzeLabel),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: FilledButton.icon(
                onPressed: (!_ready || widget.isProcessing || _error != null)
                    ? null
                    : _captureFrame,
                 icon: const Icon(Icons.camera_alt_outlined),
                 label: Text(widget.captureLabel),
               ),
             ),
          ],
        ),
      ),
    );
  }
}
