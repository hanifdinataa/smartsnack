import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'nutrition_label_parser.dart';

class NutritionLabelOcrService {
  static Future<void>? _loader;

  Future<String> recognizeTextFromFile(XFile file) async {
    final bytes = await file.readAsBytes();
    return recognizeTextFromBytes(bytes);
  }

  Future<String> recognizeTextFromBytes(Uint8List bytes) async {
    await _ensureTesseractLoaded();
    final sources = await _buildSources(bytes);
    _OcrCandidate? best;

    for (final source in sources) {
      final text = await _recognizeCanvas(source);
      final candidate = _scoreText(text, source.label);
      if (best == null || candidate.score > best.score) {
        best = candidate;
      }
      if (candidate.score >= 80) {
        break;
      }
    }

    return best?.text.trim() ?? '';
  }

  Future<void> _ensureTesseractLoaded() async {
    _loader ??= () async {
      final existing = js_util.getProperty(html.window, 'Tesseract');
      if (existing != null) {
        return;
      }

      final completer = Completer<void>();
      final script = html.ScriptElement()
        ..src = 'https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js'
        ..async = true;

      script.onError.first.then((_) {
        if (!completer.isCompleted) {
          completer.completeError(
            Exception('Gagal memuat mesin OCR web.'),
          );
        }
      });
      script.onLoad.first.then((_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      html.document.head?.append(script);
      await completer.future;
    }();

    await _loader!;
  }

  Future<List<_OcrSource>> _buildSources(Uint8List bytes) async {
    final image = await _loadImage(bytes);
    final base = _drawToCanvas(image);
    final brightPanel = _findBrightPanel(base) ?? base;
    final topSection = _cropByFraction(brightPanel, left: 0.04, top: 0.03, width: 0.92, height: 0.32);
    final bodySection = _cropByFraction(brightPanel, left: 0.04, top: 0.28, width: 0.92, height: 0.48);
    final lowerSection = _cropByFraction(brightPanel, left: 0.04, top: 0.48, width: 0.92, height: 0.34);

    final sources = <_OcrSource>[
      _OcrSource(base, 'base'),
      _OcrSource(brightPanel, 'panel'),
      _OcrSource(_upscale(brightPanel, 2), 'panel-x2'),
      _OcrSource(_upscale(brightPanel, 3), 'panel-x3'),
      _OcrSource(_grayscale(brightPanel), 'panel-gray'),
      _OcrSource(_threshold(brightPanel, 160), 'panel-th160'),
      _OcrSource(_threshold(_upscale(brightPanel, 2), 170), 'panel-th170-x2'),
      _OcrSource(_sharpen(_upscale(brightPanel, 2)), 'panel-sharp-x2'),
      _OcrSource(topSection, 'top'),
      _OcrSource(_upscale(topSection, 3), 'top-x3'),
      _OcrSource(_threshold(_upscale(topSection, 3), 175), 'top-th175-x3'),
      _OcrSource(bodySection, 'body'),
      _OcrSource(_upscale(bodySection, 3), 'body-x3'),
      _OcrSource(_threshold(_upscale(bodySection, 3), 175), 'body-th175-x3'),
      _OcrSource(_sharpen(_upscale(bodySection, 3)), 'body-sharp-x3'),
      _OcrSource(lowerSection, 'lower'),
      _OcrSource(_upscale(lowerSection, 2), 'lower-x2'),
      _OcrSource(_threshold(_upscale(lowerSection, 2), 165), 'lower-th165-x2'),
    ];

    return sources.where((source) {
      final width = source.canvas.width ?? 0;
      final height = source.canvas.height ?? 0;
      return width > 20 && height > 20;
    }).toList();
  }

  html.CanvasElement? _findBrightPanel(html.CanvasElement source) {
    final width = source.width ?? 0;
    final height = source.height ?? 0;
    if (width <= 0 || height <= 0) return null;

    final ctx = source.context2D;
    final image = ctx.getImageData(0, 0, width, height);
    final pixels = image.data;

    var minX = width;
    var minY = height;
    var maxX = 0;
    var maxY = 0;
    var count = 0;

    for (var y = 0; y < height; y += 2) {
      for (var x = 0; x < width; x += 2) {
        final i = ((y * width) + x) * 4;
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        final brightness = (r + g + b) / 3;
        final spread = [r, g, b]..sort();
        final colorSpread = spread.last - spread.first;

        if (brightness >= 175 && colorSpread <= 55) {
          count++;
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (count < 400) return null;
    final boxWidth = maxX - minX;
    final boxHeight = maxY - minY;
    if (boxWidth < width * 0.35 || boxHeight < height * 0.25) {
      return null;
    }

    final padX = (boxWidth * 0.04).round();
    final padY = (boxHeight * 0.04).round();
    return _crop(
      source,
      x: (minX - padX).clamp(0, width - 1).toInt(),
      y: (minY - padY).clamp(0, height - 1).toInt(),
      w: (boxWidth + (padX * 2)).clamp(1, width).toInt(),
      h: (boxHeight + (padY * 2)).clamp(1, height).toInt(),
    );
  }

  html.CanvasElement _cropByFraction(
    html.CanvasElement source, {
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    final sourceWidth = source.width ?? 0;
    final sourceHeight = source.height ?? 0;
    return _crop(
      source,
      x: (sourceWidth * left).round(),
      y: (sourceHeight * top).round(),
      w: (sourceWidth * width).round(),
      h: (sourceHeight * height).round(),
    );
  }

  html.CanvasElement _crop(
    html.CanvasElement source, {
    required int x,
    required int y,
    required int w,
    required int h,
  }) {
    final sourceWidth = source.width ?? 0;
    final sourceHeight = source.height ?? 0;
    final safeX = x.clamp(0, sourceWidth - 1).toInt();
    final safeY = y.clamp(0, sourceHeight - 1).toInt();
    final maxWidth = sourceWidth - safeX;
    final maxHeight = sourceHeight - safeY;
    final safeW = w.clamp(1, maxWidth).toInt();
    final safeH = h.clamp(1, maxHeight).toInt();

    final canvas = html.CanvasElement(width: safeW, height: safeH);
    canvas.context2D.drawImageScaledFromSource(
      source,
      safeX.toDouble(),
      safeY.toDouble(),
      safeW.toDouble(),
      safeH.toDouble(),
      0,
      0,
      safeW.toDouble(),
      safeH.toDouble(),
    );
    return canvas;
  }

  html.CanvasElement _sharpen(html.CanvasElement source) {
    final width = source.width ?? 0;
    final height = source.height ?? 0;
    final srcCanvas = _grayscale(source);
    final srcCtx = srcCanvas.context2D;
    final srcData = srcCtx.getImageData(0, 0, width, height);
    final src = srcData.data;
    final outCanvas = html.CanvasElement(width: width, height: height);
    final outCtx = outCanvas.context2D;
    final outData = outCtx.createImageData(width, height);
    final out = outData.data;
    const kernel = <int>[
      0, -1, 0,
      -1, 5, -1,
      0, -1, 0,
    ];

    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        var acc = 0.0;
        var k = 0;
        for (var ky = -1; ky <= 1; ky++) {
          for (var kx = -1; kx <= 1; kx++) {
            final idx = (((y + ky) * width) + (x + kx)) * 4;
            acc += src[idx] * kernel[k++];
          }
        }
        final clamped = acc.clamp(0, 255).round();
        final outIdx = ((y * width) + x) * 4;
        out[outIdx] = clamped;
        out[outIdx + 1] = clamped;
        out[outIdx + 2] = clamped;
        out[outIdx + 3] = 255;
      }
    }

    outCtx.putImageData(outData, 0, 0);
    return outCanvas;
  }

  Future<html.ImageElement> _loadImage(Uint8List bytes) {
    final completer = Completer<html.ImageElement>();
    final blob = html.Blob(<dynamic>[bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final image = html.ImageElement();

    image.onLoad.first.then((_) {
      html.Url.revokeObjectUrl(url);
      completer.complete(image);
    });
    image.onError.first.then((_) {
      html.Url.revokeObjectUrl(url);
      completer.completeError(Exception('Gambar label gizi tidak bisa dibaca.'));
    });

    image.src = url;
    return completer.future;
  }

  html.CanvasElement _drawToCanvas(html.ImageElement image) {
    final width = image.naturalWidth ?? image.width ?? 0;
    final height = image.naturalHeight ?? image.height ?? 0;
    final canvas = html.CanvasElement(width: width, height: height);
    canvas.context2D.drawImageScaled(
      image,
      0,
      0,
      width.toDouble(),
      height.toDouble(),
    );
    return canvas;
  }

  html.CanvasElement _upscale(html.CanvasElement source, int scale) {
    final width = (source.width ?? 0) * scale;
    final height = (source.height ?? 0) * scale;
    final canvas = html.CanvasElement(width: width, height: height);
    final ctx = canvas.context2D;
    ctx.imageSmoothingEnabled = false;
    ctx.drawImageScaled(source, 0, 0, width.toDouble(), height.toDouble());
    return canvas;
  }

  html.CanvasElement _grayscale(html.CanvasElement source) {
    final width = source.width ?? 0;
    final height = source.height ?? 0;
    final canvas = html.CanvasElement(width: width, height: height);
    final ctx = canvas.context2D;
    ctx.drawImage(source, 0, 0);
    final data = ctx.getImageData(0, 0, width, height);
    final pixels = data.data;
    for (var i = 0; i < pixels.length; i += 4) {
      final gray = (pixels[i] * 0.299 + pixels[i + 1] * 0.587 + pixels[i + 2] * 0.114).round();
      pixels[i] = gray;
      pixels[i + 1] = gray;
      pixels[i + 2] = gray;
    }
    ctx.putImageData(data, 0, 0);
    return canvas;
  }

  html.CanvasElement _threshold(html.CanvasElement source, int limit) {
    final canvas = _grayscale(source);
    final width = canvas.width ?? 0;
    final height = canvas.height ?? 0;
    final ctx = canvas.context2D;
    final data = ctx.getImageData(0, 0, width, height);
    final pixels = data.data;
    for (var i = 0; i < pixels.length; i += 4) {
      final value = pixels[i] >= limit ? 255 : 0;
      pixels[i] = value;
      pixels[i + 1] = value;
      pixels[i + 2] = value;
    }
    ctx.putImageData(data, 0, 0);
    return canvas;
  }

  Future<String> _recognizeCanvas(_OcrSource source) async {
    final tesseract = js_util.getProperty(html.window, 'Tesseract');
    final result = await js_util.promiseToFuture<Object>(
      js_util.callMethod(
        tesseract,
        'recognize',
        <Object>[
          source.canvas.toDataUrl('image/png'),
          'eng',
          js_util.jsify({
            'logger': null,
          }),
        ],
      ),
    );

    final data = js_util.getProperty(result, 'data');
    final text = js_util.getProperty(data, 'text');
    return NutritionLabelParser.cleanRawText((text ?? '').toString());
  }

  _OcrCandidate _scoreText(String value, String label) {
    final parsed = NutritionLabelParser.parse(value);
    final lowered = value.toLowerCase();
    final lines = value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    var score = 0.0;
    if (lowered.contains('gula') || lowered.contains('sugar')) score += 18;
    if (lowered.contains('takaran') || lowered.contains('serving size')) score += 18;
    if (lowered.contains('nutrition') || lowered.contains('informasi')) score += 10;
    if (parsed.sugarGrams != null) score += 34;
    if (parsed.netWeight != null) score += 28;
    if (parsed.name.isNotEmpty) score += 8;
    score += lines.length.clamp(0, 14).toDouble();
    score -= _gibberishPenalty(lines);

    if (label.contains('panel')) score += 5;
    if (label.contains('top') && parsed.netWeight != null) score += 8;
    if (label.contains('body') && parsed.sugarGrams != null) score += 10;

    return _OcrCandidate(
      text: value,
      label: label,
      score: score,
    );
  }

  double _gibberishPenalty(List<String> lines) {
    var penalty = 0.0;
    for (final line in lines) {
      if (line.length < 3) continue;
      final weirdChars = RegExp(r'[^A-Za-z0-9%/(),.:+\- ]').allMatches(line).length;
      penalty += weirdChars * 1.5;
      if (RegExp(r'^[A-Za-z]{1,3}\s+[A-Za-z]{1,3}\s+[A-Za-z]{1,3}$').hasMatch(line)) {
        penalty += 2;
      }
    }
    return penalty;
  }
}

class _OcrSource {
  const _OcrSource(this.canvas, this.label);

  final html.CanvasElement canvas;
  final String label;
}

class _OcrCandidate {
  const _OcrCandidate({
    required this.text,
    required this.label,
    required this.score,
  });

  final String text;
  final String label;
  final double score;
}
