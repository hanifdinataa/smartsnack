import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

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
  bool get isStrongPrediction => confidence >= 0.40 && topGap >= 0.08;
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

  final ApiService _apiService;

  Future<ClassifiedProductResult?> classifyProduct(
    XFile file, {
    bool allowPackageDetectionFallback = false,
    bool requireStrongPrediction = true,
  }) async {
    final productId = await _apiService.classifyProductByImage(file);
    if (productId == null) {
      return null;
    }
    return ClassifiedProductResult(
      label: '',
      category: '',
      confidence: 1,
      topGap: 1,
      productId: productId,
    );
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
    return null;
  }

  void dispose() {}
}
