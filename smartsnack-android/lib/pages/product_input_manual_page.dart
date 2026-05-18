import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/api_models.dart';
import '../providers/app_providers.dart';
import '../services/nutrition_label_parser.dart';
import '../widgets/camera_capture_view.dart';
import 'product_result_page.dart';

enum ProductInputMode { manual }

extension on ProductInputMode {
  String get pageTitle {
    return 'Input Produk';
  }

  String get scanSource {
    return 'manual_input';
  }
}

class ProductInputPage extends ConsumerStatefulWidget {
  const ProductInputPage({
    super.key,
    this.mode = ProductInputMode.manual,
    this.initialValue,
  });

  final ProductInputMode mode;
  final String? initialValue;

  @override
  ConsumerState<ProductInputPage> createState() => _ProductInputPageState();
}

class _ProductInputPageState extends ConsumerState<ProductInputPage> {
  late final AppLifecycleListener _appLifecycleListener;
  final _nameController = TextEditingController();
  final _sugarController = TextEditingController();
  final _netWeightController = TextEditingController();

  Uint8List? _labelPreviewBytes;
  XFile? _labelImageFile;
  Uint8List? _packagePreviewBytes;
  XFile? _packageImageFile;
  String _selectedCategory = 'food';
  String _rawText = '';
  bool _processingLabel = false;
  bool _submitting = false;
  bool _hasRecognizedImage = false;
  bool _labelReadyForProcess = false;
  bool _processingPackageDetection = false;
  bool _hasDetectedPackageData = false;
  bool _packageReadyForProcess = false;
  String _packageDetectionSource = 'manual';
  String? _packageDetectionStatusMessage;
  bool _packageMatchedExisting = false;

  bool get _isBusy => _processingLabel || _submitting || _processingPackageDetection;

  @override
  void initState() {
    super.initState();
    _appLifecycleListener = AppLifecycleListener(
      onResume: () {
        ref.read(classifierServiceProvider).dispose();
      },
    );
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    _nameController.dispose();
    _sugarController.dispose();
    _netWeightController.dispose();
    super.dispose();
  }

  Future<void> _pickLabelImage() async {
    if (_isBusy) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    _setPickedLabelImage(file, bytes);
  }

  Future<void> _openMobileCamera() async {
    if (_isBusy) return;
    if (kIsWeb) {
      await _captureFromWebCamera(forPackagePhoto: false);
      return;
    }
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    _setPickedLabelImage(file, bytes);
  }

  Future<void> _pickPackageImage() async {
    if (_isBusy) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _packageImageFile = file;
      _packagePreviewBytes = bytes;
      _hasDetectedPackageData = false;
      _packageReadyForProcess = true;
      _packageDetectionStatusMessage = null;
      _packageMatchedExisting = false;
    });
  }

  Future<void> _openPackageCamera() async {
    if (_isBusy) return;
    if (kIsWeb) {
      await _captureFromWebCamera(forPackagePhoto: true);
      return;
    }
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _packageImageFile = file;
      _packagePreviewBytes = bytes;
      _hasDetectedPackageData = false;
      _packageReadyForProcess = true;
      _packageDetectionStatusMessage = null;
      _packageMatchedExisting = false;
    });
  }

  void _setPickedLabelImage(XFile file, Uint8List previewBytes) {
    setState(() {
      _labelImageFile = file;
      _labelPreviewBytes = previewBytes;
      _labelReadyForProcess = true;
      _hasRecognizedImage = false;
      _rawText = '';
    });
  }

  Future<void> _captureFromWebCamera({required bool forPackagePhoto}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: CameraCaptureView(
                isProcessing: _isBusy,
                captureLabel: forPackagePhoto ? 'Foto Kemasan' : 'Ambil Foto Label',
                onCapture: (bytes) async {
                  final now = DateTime.now().millisecondsSinceEpoch;
                  final xfile = XFile.fromData(
                    bytes,
                    mimeType: 'image/jpeg',
                    name: forPackagePhoto ? 'package_$now.jpg' : 'label_$now.jpg',
                  );
                  if (forPackagePhoto) {
                    setState(() {
                      _packageImageFile = xfile;
                      _packagePreviewBytes = bytes;
                      _hasDetectedPackageData = false;
                      _packageReadyForProcess = true;
                      _packageDetectionStatusMessage = null;
                      _packageMatchedExisting = false;
                    });
                  } else {
                    _setPickedLabelImage(xfile, bytes);
                  }
                  if (mounted) {
                    Navigator.of(ctx).pop();
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _processLabelImage() async {
    if (_processingLabel || _submitting) return;
    final file = _labelImageFile;
    final previewBytes = _labelPreviewBytes;
    if (file == null || previewBytes == null) {
      _showSnackBar('Pilih atau ambil foto label gizi terlebih dahulu.');
      return;
    }

    await _analyzePickedImage(file, previewBytes: previewBytes);
  }

  Future<void> _processPackageImage() async {
    final file = _packageImageFile;
    if (file == null) {
      _showSnackBar('Pilih atau ambil foto kemasan terlebih dahulu.');
      return;
    }
    await _detectProductFromPackageImage(file);
    if (mounted) {
      setState(() => _packageReadyForProcess = false);
    }
  }

  Future<void> _detectProductFromPackageImage(XFile file) async {
    if (_processingPackageDetection) return;
    setState(() {
      _processingPackageDetection = true;
      _packageDetectionSource = 'manual';
      _hasDetectedPackageData = false;
      _packageDetectionStatusMessage = null;
      _packageMatchedExisting = false;
    });

    try {
      final modelDetected = await _detectFromModel(file);
      if (modelDetected) {
        return;
      }

      if (mounted) {
        setState(() {
          _selectedCategory = 'food';
          _packageDetectionStatusMessage =
              'Produk belum dikenali. Silakan isi nama dan kategori secara manual.';
          _packageMatchedExisting = false;
        });
        _showSnackBar('Produk belum dikenali. Silakan isi nama dan kategori secara manual.');
      }
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      if (message.toLowerCase().contains('tidak dapat terhubung')) {
        _showSnackBar('API tidak terhubung. Pastikan backend aktif.');
      } else {
        _showSnackBar('Deteksi nama/kategori dari foto kemasan gagal.');
      }
    } finally {
      if (mounted) {
        setState(() => _processingPackageDetection = false);
      }
    }
  }

  Future<bool> _detectFromModel(XFile file) async {
    try {
      final classifier = ref.read(classifierServiceProvider);
      final result = await classifier.classifyProduct(
        file,
        allowPackageDetectionFallback: false,
        requireStrongPrediction: false,
      );
      if (result == null || !result.hasLabel || !result.isStrongPrediction) {
        if (mounted) {
          setState(() {
            _packageDetectionStatusMessage =
                'Produk belum dikenali. Coba foto kemasan yang lebih jelas.';
            _packageMatchedExisting = false;
          });
          _showSnackBar('Model tidak menemukan produk yang cocok.');
        }
        return false;
      }

      if (result.productId != null && result.productId! > 0) {
        final detail = await ref.read(apiServiceProvider).getProductDetail(result.productId!);
        if (!mounted) return false;
        final name = detail.name.trim();
        final category = detail.category == 'drink' ? 'drink' : 'food';
        if (name.isEmpty) {
          return false;
        }
        setState(() {
          _nameController.text = name;
          _selectedCategory = category;
          _hasDetectedPackageData = true;
          _packageDetectionSource = 'model';
          _packageDetectionStatusMessage = 'Produk ditemukan di database.';
          _packageMatchedExisting = true;
        });
        return true;
      }

      if (!mounted) return false;
      setState(() {
        _nameController.text = result.label.trim();
        if (result.category.trim().isNotEmpty) {
          _selectedCategory = result.category == 'drink' ? 'drink' : 'food';
        }
        _hasDetectedPackageData = true;
        _packageDetectionSource = 'model';
        _packageDetectionStatusMessage =
            'Produk belum ada di database, silakan lengkapi data untuk menambahkan.';
        _packageMatchedExisting = false;
      });
      return true;
    } catch (e) {
      if (mounted) {
        final message = e.toString().replaceFirst('Exception: ', '');
        if (message.toLowerCase().contains('tidak dapat terhubung')) {
          _showSnackBar('API tidak terhubung. Pastikan backend aktif.');
        } else {
          _showSnackBar('Model tidak cocok untuk foto kemasan ini.');
        }
      }
      return false;
    }
  }

  Future<void> _analyzePickedImage(
    XFile file, {
    required Uint8List previewBytes,
  }) async {
    if (_processingLabel || _submitting) return;

    setState(() {
      _processingLabel = true;
      _labelPreviewBytes = previewBytes;
    });

    try {
      final detected = await ref.read(apiServiceProvider).detectNutritionLabelFromFile(file);
      _applyDetectionResult(detected);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _processingLabel = false);
      }
    }
  }

  void _applyDraft(NutritionLabelDraft draft, {required String rawText}) {
    if (draft.sugarGrams != null) {
      _sugarController.text = _formatNumber(draft.sugarGrams!);
    }
    if (draft.netWeight != null) {
      _netWeightController.text = _formatNumber(draft.netWeight!);
    }
    if (draft.category.isNotEmpty) {
      _selectedCategory = draft.category;
    }
    _rawText = rawText.trim();
    _hasRecognizedImage = true;
    _labelReadyForProcess = false;

    setState(() {});

    if (!draft.hasUsefulData && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Teks informasi nilai gizi belum terbaca jelas. Coba foto lebih lurus dan terang.',
          ),
        ),
      );
    }
  }

  void _applyDetectionResult(NutritionLabelDetectionResult detected) {
    final fallbackDraft = NutritionLabelParser.parse(detected.rawText);
    // Kategori harus mengikuti hasil foto kemasan jika sudah pernah terdeteksi.
    // OCR label gizi hanya untuk gula & takaran saji, bukan sumber utama kategori.
    final hasLockedCategoryFromPackage =
        _hasDetectedPackageData && _packageDetectionSource != 'manual';
    final resolvedCategory = hasLockedCategoryFromPackage
        ? _selectedCategory
        : (fallbackDraft.category.isNotEmpty
            ? fallbackDraft.category
            : (detected.category.trim().isNotEmpty
                ? detected.category.trim()
                : _selectedCategory));
    final resolvedSugar = _resolveSugar(
      detectedSugar: detected.grSugarContent,
      parserSugar: fallbackDraft.sugarGrams,
      detectedNetWeight: detected.netWeight,
      parserNetWeight: fallbackDraft.netWeight,
    );
    final resolvedNetWeight = _resolveNetWeight(
      detectedNetWeight: detected.netWeight,
      parserNetWeight: fallbackDraft.netWeight,
    );

    _applyDraft(
      NutritionLabelDraft(
        name: _nameController.text.trim(),
        category: resolvedCategory.isEmpty ? 'food' : resolvedCategory,
        sugarGrams: resolvedSugar,
        netWeight: resolvedNetWeight,
        rawText: detected.rawText,
      ),
      rawText: detected.rawText,
    );
  }

  double? _resolveSugar({
    required double? detectedSugar,
    required double? parserSugar,
    required double? detectedNetWeight,
    required double? parserNetWeight,
  }) {
    final p = parserSugar;
    final d = detectedSugar;
    // Prioritaskan hasil AI service label-gizi-service.
    // Parser lokal hanya fallback saat service tidak memberi nilai valid.
    if (d != null && d >= 0 && d <= 80) return d;
    if (p != null && p >= 0 && p <= 80) return p;
    return null;
  }

  double? _resolveNetWeight({
    required double? detectedNetWeight,
    required double? parserNetWeight,
  }) {
    final p = parserNetWeight;
    final d = detectedNetWeight;
    // Sama seperti gula: utamakan hasil service, parser lokal sebagai fallback.
    if (d != null && d >= 5 && d <= 2000) return d;
    if (p != null && p >= 5 && p <= 2000) return p;
    return null;
  }

  Future<void> _submitNutritionData() async {
    final name = _nameController.text.trim();
    final sugar = double.tryParse(_sugarController.text.replaceAll(',', '.'));
    final netWeight =
        double.tryParse(_netWeightController.text.replaceAll(',', '.'));
    final category = _selectedCategory == 'drink' ? 'drink' : 'food';

    if (name.isEmpty) {
      _showSnackBar('Nama kemasan wajib diisi.');
      return;
    }
    if (sugar == null || sugar < 0) {
      _showSnackBar('Jumlah gula harus berupa angka yang valid.');
      return;
    }
    if (netWeight == null || netWeight <= 0) {
      _showSnackBar(
        'Takaran saji / berat bersih wajib diisi agar alert gula bisa dihitung.',
      );
      return;
    }
    if (_labelImageFile != null && _labelReadyForProcess) {
      _showSnackBar('Tekan tombol Proses pada foto label gizi terlebih dahulu.');
      return;
    }
    if (_packageImageFile == null) {
      _showSnackBar('Foto kemasan produk wajib diupload/diambil agar gambar produk tersimpan sesuai.');
      return;
    }
    if (_packageImageFile != null && _packageReadyForProcess) {
      _showSnackBar('Tekan tombol Proses pada foto kemasan terlebih dahulu.');
      return;
    }

    if (_submitting || _processingLabel || _processingPackageDetection) return;
    setState(() => _submitting = true);

    try {
      final result = await ref.read(apiServiceProvider).recognizeNutritionLabel(
            name: name,
            category: category,
            grSugarContent: sugar,
            netWeight: netWeight,
            scanSource: widget.mode.scanSource,
            rawText: _rawText.isEmpty ? null : _rawText,
            productImageFile: _packageImageFile,
          );

      if (!mounted) return;
      await _showResultAlert(result);
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ProductResultPage(
            productId: result.productId,
            previewBytes: _labelPreviewBytes,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(_friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _showResultAlert(NutritionScanResult result) async {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_resultTitle),
        content: Text(
          'Nama kemasan: ${result.productName}\n'
          'Jumlah gula: ${result.grSugarContent.toStringAsFixed(2)} gram\n'
          'Jenis produk: ${result.category}\n'
          'Alert gula: ${result.sugarGrade}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Lihat Detail'),
          ),
        ],
      ),
    );
  }

  String get _resultTitle {
    return 'Hasil Input Produk';
  }

  String _formatNumber(double value) {
    if (value.truncateToDouble() == value) {
      return value.toStringAsFixed(0);
    }
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _friendlyError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  String _packageSourceLabel() {
    switch (_packageDetectionSource) {
      case 'model':
        return 'model';
      case 'legacy-service':
        return 'label-gizi-service';
      case 'ocr':
        return 'OCR kemasan';
      default:
        return 'input manual';
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.mode.pageTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _buildIntroCard(),
          const SizedBox(height: 16),
          _buildFormCard(
            showDetectedBadge: _hasRecognizedImage,
          ),
          if (_rawText.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildRawTextCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6F1),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              widget.mode.pageTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          const Center(
            child: Text(
    'Tips: Fokuskan Kamera, jika kameramu jelek, gunakan upload gambar saja, maaf.',
    textAlign: TextAlign.center,
    style: const TextStyle(color: Colors.black54, fontSize: 16),

            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard({required bool showDetectedBadge}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Foto Kemasan Produk',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload/ambil foto depan kemasan agar tampil di Cari Produk.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isBusy ? null : _pickPackageImage,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Upload Kemasan'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isBusy ? null : _openPackageCamera,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Foto Kemasan'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isBusy ? null : _processPackageImage,
              icon: const Icon(Icons.play_circle_outline),
              label: Text(_processingPackageDetection ? 'Memproses...' : 'Proses'),
            ),
          ),
          if (_packageReadyForProcess) ...[
            const SizedBox(height: 8),
            const Text(
              'Foto kemasan siap diproses. Tekan tombol Proses.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
          if (_packagePreviewBytes != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                _packagePreviewBytes!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (_processingPackageDetection) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'Mendeteksi nama & kategori dari foto kemasan...',
              style: TextStyle(color: Colors.black54),
            ),
          ],
          if (_hasDetectedPackageData && !_processingPackageDetection) ...[
            const SizedBox(height: 8),
            Text(
              'Nama produk dan kategori terisi otomatis dari ${_packageSourceLabel()}.',
              style: const TextStyle(
                color: Color(0xFF27B48A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_packageDetectionStatusMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _packageMatchedExisting ? const Color(0xFFE9F8F2) : const Color(0xFFFFF6E7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _packageMatchedExisting ? const Color(0xFF27B48A) : const Color(0xFFE1A73B),
                ),
              ),
              child: Text(
                _packageDetectionStatusMessage!,
                style: TextStyle(
                  color: _packageMatchedExisting ? const Color(0xFF1A7F60) : const Color(0xFF8A5A00),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Ambil Data Dari Label Gizi',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'upload/ambil foto label nilai gizi',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isBusy ? null : _pickLabelImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Upload Gizi'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isBusy ? null : _openMobileCamera,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Ambil Foto'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isBusy ? null : _processLabelImage,
              icon: const Icon(Icons.play_circle_outline),
              label: Text(_processingLabel ? 'Memproses...' : 'Proses'),
            ),
          ),
          if (_labelReadyForProcess) ...[
            const SizedBox(height: 8),
            const Text(
              'Foto label siap diproses. Tekan tombol Proses untuk OCR.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
          if (_labelPreviewBytes != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                _labelPreviewBytes!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Data Produk',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              if (showDetectedBadge)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF6F1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Hasil OCR',
                    style: TextStyle(
                      color: Color(0xFF27B48A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Cek dan edit hasil deteksi sebelum disimpan.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_packageDetectionSource != 'manual') {
                setState(() => _packageDetectionSource = 'manual');
              }
            },
            decoration: const InputDecoration(
              labelText: 'Nama kemasan',
              hintText: 'Contoh: Choco Pie',
            ),
          ),
          if (_hasRecognizedImage) ...[
            const SizedBox(height: 10),
            const Text(
              'Hasil OCR sudah masuk ke form. Anda bisa edit sebelum simpan.',
              style: TextStyle(
                color: Color(0xFF27B48A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            decoration: const InputDecoration(labelText: 'Kategori'),
            items: const [
              DropdownMenuItem(value: 'food', child: Text('Food')),
              DropdownMenuItem(value: 'drink', child: Text('Drink')),
            ],
            onChanged: _isBusy
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedCategory = value;
                      if (_packageDetectionSource != 'manual') {
                        _packageDetectionSource = 'manual';
                      }
                    });
                  },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _sugarController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Jumlah gula (gram)',
              hintText: 'Contoh: 12',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _netWeightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Takaran saji / berat bersih (gram/ml)',
              hintText: 'Contoh: 70',
              helperText: 'Field ini dipakai untuk menghitung alert gula.',
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isBusy ? null : _submitNutritionData,
              child: Text(_submitting ? 'Menyimpan...' : 'Simpan & Tampilkan Hasil'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawTextCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111A17),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          collapsedIconColor: Colors.white70,
          iconColor: Colors.white,
          title: const Text(
            'Lihat teks OCR',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Dipakai sebagai bahan isi otomatis',
            style: TextStyle(color: Colors.white70),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(
                _rawText,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
