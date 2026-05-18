import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class NutritionLabelOcrService {
  Future<String> recognizeTextFromFile(XFile file) async {
    throw UnsupportedError('OCR label gizi belum tersedia di platform ini.');
  }

  Future<String> recognizeTextFromBytes(Uint8List bytes) async {
    throw UnsupportedError('OCR label gizi belum tersedia di platform ini.');
  }
}
