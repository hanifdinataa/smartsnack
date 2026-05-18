import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'nutrition_label_parser.dart';

class NutritionLabelOcrService {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  Future<String> recognizeTextFromFile(XFile file) async {
    final inputImage = InputImage.fromFilePath(file.path);
    final recognized = await _recognizer.processImage(inputImage);
    return NutritionLabelParser.cleanRawText(recognized.text);
  }

  Future<String> recognizeTextFromBytes(Uint8List bytes) async {
    throw UnsupportedError(
      'OCR bytes langsung tidak dipakai pada platform mobile.',
    );
  }

  Future<void> dispose() async {
    await _recognizer.close();
  }
}
