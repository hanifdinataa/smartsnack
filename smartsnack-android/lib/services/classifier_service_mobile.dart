import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'api_service.dart';

class ClassifiedProductResult {
  const ClassifiedProductResult({
    required this.label,
    required this.category,
    required this.confidence,
    required this.topGap,
    required this.productId,
    this.topPredictions = const <String>[],
  });

  final String label;
  final String category;
  final double confidence;
  final double topGap;
  final int? productId;
  final List<String> topPredictions;

  bool get hasLabel => label.trim().isNotEmpty;
  bool get isStrongPrediction => confidence >= 0.20 && topGap >= 0.02;
}

class PreviewClassificationResult {
  const PreviewClassificationResult({
    required this.label,
    required this.confidence,
    required this.topGap,
  });

  final String label;
  final double confidence;
  final double topGap;
}

class ImageClassifierService {
  ImageClassifierService({required ApiService apiService}) : _apiService = apiService;

  static const String _modelAsset = 'assets/ml/smartsnack_model.tflite';
  static const String _labelsAsset = 'assets/ml/labels.txt';
  static const String _metadataAsset = 'assets/ml/smartsnack_model_metadata.json';
  static const double _minimumConfidence = 0.20;
  static const double _minimumTopGap = 0.02;
  static const bool _debugTflite = true;

  final ApiService _apiService;

  Interpreter? _baseInterpreter;
  IsolateInterpreter? _interpreter;
  List<_ModelLabel> _labels = <_ModelLabel>[];
  int _inputWidth = 224;
  int _inputHeight = 224;
  TensorType _inputType = TensorType.float32;
  TensorType _outputType = TensorType.float32;
  double _inputScale = 1.0;
  int _inputZeroPoint = 0;
  double _outputScale = 1.0;
  int _outputZeroPoint = 0;

  Future<void> _ensureReady() async {
    if (_interpreter != null && _labels.isNotEmpty) {
      try {
        _baseInterpreter!.getInputTensor(0);
        _baseInterpreter!.getOutputTensor(0);
        return;
      } catch (e, st) {
        developer.log(
          'Interpreter invalid, recreating: $e\n$st',
          name: 'ImageClassifierService',
        );
        reset();
      }
    }

    _baseInterpreter = await Interpreter.fromAsset(_modelAsset);
    _interpreter = await IsolateInterpreter.create(
      address: _baseInterpreter!.address,
    );
    final inputTensor = _baseInterpreter!.getInputTensor(0);
    final outputTensor = _baseInterpreter!.getOutputTensor(0);
    final inputShape = inputTensor.shape;
    if (inputShape.length >= 4) {
      _inputHeight = inputShape[1];
      _inputWidth = inputShape[2];
    }
    _inputType = inputTensor.type;
    _outputType = outputTensor.type;
    _inputScale = inputTensor.params.scale == 0 ? 1.0 : inputTensor.params.scale;
    _inputZeroPoint = inputTensor.params.zeroPoint;
    _outputScale = outputTensor.params.scale == 0 ? 1.0 : outputTensor.params.scale;
    _outputZeroPoint = outputTensor.params.zeroPoint;
    final outputLength =
        outputTensor.shape.isNotEmpty ? outputTensor.shape.last : 0;
    final labelText = await rootBundle.loadString(_labelsAsset);
    final labelNames = labelText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final metadataLabels = <int, _ModelLabel>{};
    try {
      final metadataText = await rootBundle.loadString(_metadataAsset);
      final metadata = jsonDecode(metadataText);
      if (metadata is List) {
        for (final item in metadata) {
          if (item is Map<String, dynamic>) {
            final labelIndex = int.tryParse(
              (item['label_index'] ?? '').toString(),
            );
            final name = (item['name'] ?? '').toString().trim();
            final category = (item['category'] ?? '').toString().trim();
            if (labelIndex != null && labelIndex >= 0 && name.isNotEmpty) {
              metadataLabels[labelIndex] = _ModelLabel(
                name: name,
                category: category.isNotEmpty ? category : _guessCategoryFromLabel(name),
              );
            }
          }
        }
      }
    } catch (e, st) {
      developer.log(
        'Metadata load failed, fallback to labels.txt only: $e\n$st',
        name: 'ImageClassifierService',
      );
    }

    if (outputLength > 0 &&
        metadataLabels.isNotEmpty &&
        metadataLabels.length == outputLength) {
      _labels = List<_ModelLabel>.generate(
        outputLength,
        (index) => metadataLabels[index] ?? const _ModelLabel(name: '', category: ''),
      );
    } else {
      _labels = labelNames
          .map(
            (name) => _ModelLabel(
              name: name,
              category: _categoryFromMetadataName(metadataLabels.values, name),
            ),
          )
          .toList();
    }

    if (outputLength > 0 &&
        _labels.isNotEmpty &&
        _labels.length != outputLength) {
      developer.log(
        'Label count mismatch | outputLen=$outputLength labels=${_labels.length}',
        name: 'ImageClassifierService',
      );
    }

    if (_debugTflite) {
      developer.log(
        'TFLite ready | inputShape=${inputTensor.shape} inputType=$_inputType '
        'inputScale=$_inputScale inputZeroPoint=$_inputZeroPoint '
        '| outputShape=${outputTensor.shape} outputType=$_outputType '
        'outputScale=$_outputScale outputZeroPoint=$_outputZeroPoint '
        '| outputLen=$outputLength labels=${_labels.length} metadata=${metadataLabels.length}',
        name: 'ImageClassifierService',
      );
    }
  }


  List<String> _labelVariants(String raw) {
    final base = raw.trim();
    if (base.isEmpty) return const <String>[];

    final comparableBase = _denoiseLabel(base);
    final variants = <String>{base};
    if (comparableBase.isNotEmpty) {
      variants.add(comparableBase);
    }

    final normalized = _normalize(comparableBase.isNotEmpty ? comparableBase : base);
    if (normalized.isNotEmpty) {
      variants.add(normalized);
      variants.add(normalized.replaceAll('  ', ' '));
    }

    // Versi title case sederhana untuk query backend
    String toTitle(String s) => s
        .split(' ')
        .where((x) => x.isNotEmpty)
        .map((w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
        .join(' ');

    final extra = variants.map(toTitle).toList();
    variants.addAll(extra);

    return variants.where((v) => v.trim().isNotEmpty).toList();
  }


  Future<int?> _findByPackageDetection(XFile file) async {
    try {
      final detected = await _apiService.detectProductPackageFromFile(file);
      final candidates = <String>{
        detected.name.trim(),
        detected.productText.trim(),
        detected.labelText.trim(),
      }.where((v) => v.isNotEmpty).toList();

      for (final raw in candidates) {
        final tries = _labelVariants(raw);
        for (final candidate in tries) {
          final foundWithCategory = await _apiService.findProductByLabel(
            candidate,
            category: detected.category,
            allowFuzzyFallback: false,
          );
          if (foundWithCategory != null) return foundWithCategory.id;

          final foundNoCategory = await _apiService.findProductByLabel(
            candidate,
            allowFuzzyFallback: false,
          );
          if (foundNoCategory != null) return foundNoCategory.id;
        }
      }
    } catch (_) {
      // abaikan, lanjut fallback lain
    }
    return null;
  }

  Future<_ModelLabel?> _pickLabelByPackageText(
    XFile file,
    List<_ModelLabel> candidates,
  ) async {
    if (candidates.isEmpty) return null;
    try {
      final detected = await _apiService.detectProductPackageFromFile(file);
      final haystack = _normalizeComparable(
        [
          detected.name,
          detected.productText,
          detected.labelText,
          detected.rawText,
        ].where((item) => item.trim().isNotEmpty).join(' '),
      );
      if (haystack.isEmpty) return null;

      _ModelLabel? best;
      var bestScore = 0;
      for (final candidate in candidates) {
        final candidateTokens = _normalizeComparable(candidate.name)
            .split(' ')
            .where((token) => token.length >= 3)
            .toList();
        if (candidateTokens.isEmpty) {
          continue;
        }
        var score = 0;
        for (final token in candidateTokens) {
          if (haystack.contains(token)) {
            score += token.length >= 5 ? 2 : 1;
          }
        }
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }
      return bestScore > 0 ? best : null;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _findByLabelWithVariants(_ModelLabel label) async {
    // 1) Exact-first: cegah fuzzy match nyasar ke produk lain.
    final exactWithCategory = await _apiService.findProductByLabel(
      label.name,
      category: label.category,
      allowFuzzyFallback: false,
    );
    if (exactWithCategory != null && _isStrictLabelMatch(label.name, exactWithCategory.name)) {
      return exactWithCategory.id;
    }

    final exactNoCategory = await _apiService.findProductByLabel(
      label.name,
      allowFuzzyFallback: false,
    );
    if (exactNoCategory != null && _isStrictLabelMatch(label.name, exactNoCategory.name)) {
      return exactNoCategory.id;
    }

    // 2) Baru fallback ke variasi tulisan.
    final tries = _labelVariants(label.name);
    for (final candidate in tries) {
      // Coba dengan kategori dulu
      final foundWithCategory = await _apiService.findProductByLabel(
        candidate,
        category: label.category,
        allowFuzzyFallback: false,
      );
      if (foundWithCategory != null && _isStrictLabelMatch(candidate, foundWithCategory.name)) return foundWithCategory.id;

      // Fallback tanpa kategori (kategori model sering tidak konsisten)
      final foundNoCategory = await _apiService.findProductByLabel(
        candidate,
        allowFuzzyFallback: false,
      );
      if (foundNoCategory != null && _isStrictLabelMatch(candidate, foundNoCategory.name)) return foundNoCategory.id;
    }

    return null;
  }

  bool _isStrictLabelMatch(String expected, String actual) {
    final e = _normalizeComparable(expected);
    final a = _normalizeComparable(actual);
    if (e.isEmpty || a.isEmpty) return false;
    if (e == a) return true;
    // Izinkan prefiks angka/kode pada nama DB: "31 ABC Mangga" vs "ABC Mangga"
    if (a.endsWith(e) || e.endsWith(a)) return true;
    return false;
  }

  Future<ClassifiedProductResult?> classifyProduct(
    XFile file, {
    bool allowPackageDetectionFallback = false,
    bool requireStrongPrediction = true,
  }) async {
    return _classifyProductInternal(
      file,
      allowPackageDetectionFallback: allowPackageDetectionFallback,
      requireStrongPrediction: requireStrongPrediction,
      allowRetryAfterReset: true,
    );
  }

  Future<ClassifiedProductResult?> _classifyProductInternal(
    XFile file, {
    required bool allowPackageDetectionFallback,
    required bool requireStrongPrediction,
    required bool allowRetryAfterReset,
  }) async {
    try {
      await _ensureReady();

      final prediction = await _predict(file);
      if (prediction == null) {
        if (!allowPackageDetectionFallback) {
          return null;
        }
        final fallbackId = await _findByPackageDetection(file);
        if (fallbackId == null) {
          return null;
        }
        return ClassifiedProductResult(
          label: '',
          category: '',
          confidence: 0,
          topGap: 0,
          productId: fallbackId,
        );
      }

      if (_debugTflite) {
        developer.log(
          'Best => ${prediction.label.name} conf=${prediction.confidence.toStringAsFixed(4)} '
          'gap=${prediction.topGap.toStringAsFixed(4)} '
          'requireStrongPrediction=$requireStrongPrediction '
          'allowPackageDetectionFallback=$allowPackageDetectionFallback',
          name: 'ImageClassifierService',
        );
      }

      final predictedLabel = prediction.label;

      final isStrong =
          prediction.confidence >= _minimumConfidence && prediction.topGap >= _minimumTopGap;
      if (requireStrongPrediction && !isStrong) {
        return ClassifiedProductResult(
          label: predictedLabel.name,
          category: predictedLabel.category,
          confidence: prediction.confidence,
          topGap: prediction.topGap,
          productId: null,
          topPredictions: prediction.topPredictions,
        );
      }

      final matchedId = await _findByLabelWithVariants(predictedLabel);
      if (matchedId != null) {
        return ClassifiedProductResult(
          label: predictedLabel.name,
          category: predictedLabel.category,
          confidence: prediction.confidence,
          topGap: prediction.topGap,
          productId: matchedId,
          topPredictions: prediction.topPredictions,
        );
      }

      if (allowPackageDetectionFallback) {
        final packageFallbackId = await _findByPackageDetection(file);
        if (packageFallbackId != null) {
          return ClassifiedProductResult(
            label: predictedLabel.name,
            category: predictedLabel.category,
            confidence: prediction.confidence,
            topGap: prediction.topGap,
            productId: packageFallbackId,
            topPredictions: prediction.topPredictions,
          );
        }
      }

      return ClassifiedProductResult(
        label: predictedLabel.name,
        category: predictedLabel.category,
        confidence: prediction.confidence,
        topGap: prediction.topGap,
        productId: null,
        topPredictions: prediction.topPredictions,
      );
    } catch (e, st) {
      developer.log(
        'classifyProduct failed: $e\n$st',
        name: 'ImageClassifierService',
      );
      if (allowRetryAfterReset) {
        reset();
        return _classifyProductInternal(
          file,
          allowPackageDetectionFallback: allowPackageDetectionFallback,
          requireStrongPrediction: requireStrongPrediction,
          allowRetryAfterReset: false,
        );
      }
      return null;
    }
  }

  Future<int?> classifyProductId(
    XFile file, {
    bool allowPackageDetectionFallback = false,
    bool requireStrongPrediction = true,
  }) async {
    final result = await classifyProduct(
      file,
      allowPackageDetectionFallback: allowPackageDetectionFallback,
      requireStrongPrediction: requireStrongPrediction,
    );
    return result?.productId;
  }

  Future<PreviewClassificationResult?> classifyPreviewFromBytes(
    Uint8List bytes,
  ) async {
    try {
      await _ensureReady();
      final file = XFile.fromData(bytes, mimeType: 'image/jpeg');
      final prediction = await _predict(file);
      if (prediction == null) return null;
      return PreviewClassificationResult(
        label: prediction.label.name,
        confidence: prediction.confidence,
        topGap: prediction.topGap,
      );
    } catch (_) {
      return null;
    }
  }

  Future<_PredictionResult?> _predict(XFile file) async {
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }

    final resized = img.copyResize(decoded, width: _inputWidth, height: _inputHeight);
    final inputTensor = _toInputTensor(resized);
    final outputTensor = _baseInterpreter!.getOutputTensor(0);
    final outputShape = outputTensor.shape;
    final outputLength = outputShape.isNotEmpty ? outputShape.last : _labels.length;
    late final List<double> rawScores;
    if (_outputType == TensorType.uint8) {
      final output = List<List<int>>.generate(
        1,
        (_) => List<int>.filled(outputLength, 0),
      );
      await _interpreter!.run(inputTensor, output);
      rawScores = output.first
          .map((v) => (v - _outputZeroPoint) * _outputScale)
          .toList();
    } else if (_outputType == TensorType.int8) {
      final output = List<List<int>>.generate(
        1,
        (_) => List<int>.filled(outputLength, 0),
      );
      await _interpreter!.run(inputTensor, output);
      rawScores = output.first
          .map((v) => (v - _outputZeroPoint) * _outputScale)
          .toList();
    } else {
      final output = List<List<double>>.generate(
        1,
        (_) => List<double>.filled(outputLength, 0),
      );
      await _interpreter!.run(inputTensor, output);
      rawScores = output.first;
    }
    final probabilities = _softmax(rawScores);
    if (probabilities.isEmpty) {
      return null;
    }

    final usable = probabilities.length < _labels.length ? probabilities.length : _labels.length;
    if (usable <= 0) {
      return null;
    }

    var maxIndex = 0;
    var maxValue = probabilities.first;
    var secondValue = double.negativeInfinity;

    for (var i = 1; i < usable; i++) {
      final value = probabilities[i];
      if (value > maxValue) {
        secondValue = maxValue;
        maxValue = value;
        maxIndex = i;
      } else if (value > secondValue) {
        secondValue = value;
      }
    }

    if (maxIndex < 0 || maxIndex >= _labels.length) {
      return null;
    }

    final usablePairs = List<MapEntry<int, double>>.generate(
      usable,
      (i) => MapEntry<int, double>(i, probabilities[i]),
    )..sort((a, b) => b.value.compareTo(a.value));
    final topPredictions = usablePairs.take(5).map((e) {
      final label = e.key < _labels.length ? _labels[e.key].name : 'idx_${e.key}';
      return '${e.key}:${label}:${e.value.toStringAsFixed(4)}';
    }).toList();
    final topLabels = usablePairs
        .take(5)
        .where((e) => e.key >= 0 && e.key < _labels.length)
        .map((e) => _labels[e.key])
        .toList();
    if (_debugTflite) {
      developer.log('Top5 => ${topPredictions.join(' | ')}', name: 'ImageClassifierService');
    }


    final topGap = maxValue - secondValue;
    return _PredictionResult(
      label: _labels[maxIndex],
      confidence: maxValue,
      topGap: topGap.isFinite ? topGap : 0.0,
      topPredictions: topPredictions,
      topLabels: topLabels,
    );
  }

  List<double> _softmax(List<double> values) {
    if (values.isEmpty) return const <double>[];
    final sum = values.fold<double>(0.0, (acc, value) => acc + value);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final alreadyProbabilities =
        minValue >= 0.0 && maxValue <= 1.0 && (sum - 1.0).abs() <= 0.15;
    if (alreadyProbabilities) {
      return values;
    }
    final maxLogit = maxValue;
    final exps = values.map((v) => math.exp(v - maxLogit)).toList();
    final expSum = exps.fold<double>(0.0, (acc, e) => acc + e);
    if (expSum <= 0 || !expSum.isFinite) return const <double>[];
    return exps.map((e) => e / expSum).toList();
  }

  String _guessCategoryFromLabel(String name) {
    final normalized = _normalizeComparable(name);
    const drinkHints = <String>[
      'aqua',
      'air',
      'minuman',
      'drink',
      'juice',
      'kopi',
      'coffee',
      'tea',
      'teh',
      'milk',
      'susu',
      'cola',
      'sprite',
      'fanta',
      'floridina',
      'yakult',
      'cimory',
      'ultra',
      'hydro',
      'coco',
      'buavita',
      'frisian',
      'nutriboost',
      'pucuk',
    ];

    for (final hint in drinkHints) {
      if (normalized.contains(hint)) {
        return 'drink';
      }
    }
    return 'food';
  }

  String _categoryFromMetadataName(Iterable<_ModelLabel> labels, String name) {
    final normalizedName = _normalizeComparable(name);
    for (final item in labels) {
      if (_normalizeComparable(item.name) == normalizedName &&
          item.category.trim().isNotEmpty) {
        return item.category;
      }
    }
    return _guessCategoryFromLabel(name);
  }

  Object _toInputTensor(img.Image image) {
    if (_inputType == TensorType.uint8) {
      return <List<List<List<int>>>>[
        List<List<List<int>>>.generate(
          _inputHeight,
          (y) => List<List<int>>.generate(
            _inputWidth,
            (x) {
              final pixel = image.getPixel(x, y);
              return <int>[pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
            },
          ),
        ),
      ];
    }
    if (_inputType == TensorType.int8) {
      return <List<List<List<int>>>>[
        List<List<List<int>>>.generate(
          _inputHeight,
          (y) => List<List<int>>.generate(
            _inputWidth,
            (x) {
              final pixel = image.getPixel(x, y);
              int q(num channel) {
                final value = ((channel / 127.5) - 1.0);
                final scaled = (value / _inputScale) + _inputZeroPoint;
                final rounded = scaled.round();
                if (rounded < -128) return -128;
                if (rounded > 127) return 127;
                return rounded;
              }

              return <int>[q(pixel.r), q(pixel.g), q(pixel.b)];
            },
          ),
        ),
      ];
    }

    return <List<List<List<double>>>>[
      List<List<List<double>>>.generate(
        _inputHeight,
        (y) => List<List<double>>.generate(
          _inputWidth,
          (x) {
            final pixel = image.getPixel(x, y);
            return <double>[
              (pixel.r.toDouble() / 127.5) - 1.0,
              (pixel.g.toDouble() / 127.5) - 1.0,
              (pixel.b.toDouble() / 127.5) - 1.0,
            ];
          },
        ),
      ),
    ];
  }

  void dispose() {
    reset();
  }

  void reset() {
    _interpreter?.close();
    _baseInterpreter?.close();
    _interpreter = null;
    _baseInterpreter = null;
    _labels = <_ModelLabel>[];
  }
}

class _ModelLabel {
  const _ModelLabel({required this.name, required this.category});

  final String name;
  final String category;
}

class _PredictionResult {
  const _PredictionResult({
    required this.label,
    required this.confidence,
    required this.topGap,
    required this.topPredictions,
    required this.topLabels,
  });

  final _ModelLabel label;
  final double confidence;
  final double topGap;
  final List<String> topPredictions;
  final List<_ModelLabel> topLabels;
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _normalizeComparable(String value) {
  final cleaned = _denoiseLabel(value);
  return _normalize(cleaned);
}

String _denoiseLabel(String value) {
  return value
      .replaceAll(RegExp(r'\(\d+\)'), '')
      .replaceAll(RegExp(r'\bcopy\b', caseSensitive: false), '')
      .trim();
}
