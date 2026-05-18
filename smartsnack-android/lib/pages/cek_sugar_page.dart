import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/app_providers.dart';
import '../widgets/camera_capture_view.dart';
import 'product_result_page.dart';

class CekSugarPage extends ConsumerStatefulWidget {
  const CekSugarPage({super.key});
  @override
  ConsumerState<CekSugarPage> createState() => _CekSugarPageState();
}

class _CekSugarPageState extends ConsumerState<CekSugarPage> {
  late final AppLifecycleListener _appLifecycleListener;
  XFile? _selectedFile;
  Uint8List? _previewBytes;
  bool _processing = false;
  bool _validatingCapture = false;
  String? _validatedProductName;
  int? _validatedProductId;
  String? _captureStatusMessage;

  // ─── ALL LOGIC UNCHANGED ────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _appLifecycleListener = AppLifecycleListener(onResume: () { ref.invalidate(classifierServiceProvider); });
  }

  @override
  void dispose() { _appLifecycleListener.dispose(); super.dispose(); }

  Future<void> _pickImage(ImageSource source) async {
    if (_processing || _validatingCapture) return;
    try {
      if (source == ImageSource.camera) { await _openCustomCamera(); return; }
      final file = await ImagePicker().pickImage(source: source, imageQuality: 90, maxWidth: 1600, maxHeight: 1600, preferredCameraDevice: CameraDevice.rear);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() { _selectedFile = file; _previewBytes = bytes; _validatedProductName = null; _validatedProductId = null; _captureStatusMessage = 'Memvalidasi produk...'; });
      await _validateCapturedProduct(file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _openCustomCamera() async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) {
      return SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: AspectRatio(aspectRatio: 3 / 4, child: CameraCaptureView(
        isProcessing: _processing || _validatingCapture, captureLabel: 'Foto Gambar', previewLabelText: 'Arahkan produk lalu ambil foto',
        onCapture: (bytes) async {
          final now = DateTime.now().millisecondsSinceEpoch;
          final file = XFile.fromData(bytes, mimeType: 'image/jpeg', name: 'cek_sugar_$now.jpg');
          if (!mounted) return;
          setState(() { _selectedFile = file; _previewBytes = bytes; _validatedProductName = null; _validatedProductId = null; _captureStatusMessage = 'Memvalidasi produk...'; });
          Navigator.of(ctx).pop();
          await _validateCapturedProduct(file);
        },
      ))));
    });
  }

  Future<void> _validateCapturedProduct(XFile file) async {
    if (_validatingCapture) return;
    setState(() => _validatingCapture = true);
    try {
      final classifier = ref.read(classifierServiceProvider);
      final result = await classifier.classifyProduct(file, allowPackageDetectionFallback: false, requireStrongPrediction: true);
      if (!mounted) return;
      if (result == null || !result.hasLabel || !result.isStrongPrediction) {
        setState(() { _validatedProductName = null; _validatedProductId = null; _captureStatusMessage = 'Produk belum dikenali. Coba foto ulang dengan kemasan lebih jelas dan terpusat.'; });
        return;
      }
      var resolvedName = result.label.trim();
      var resolvedProductId = result.productId;
      if (resolvedProductId != null && resolvedProductId > 0) {
        try {
          final detail = await ref.read(apiServiceProvider).getProductDetail(resolvedProductId);
          final dbName = detail.name.trim();
          if (dbName.isNotEmpty) resolvedName = dbName;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _validatedProductName = resolvedName.isEmpty ? null : resolvedName;
        _validatedProductId = resolvedProductId;
        _captureStatusMessage = resolvedName.isEmpty ? 'Produk belum dikenali. Coba foto ulang dengan kemasan lebih jelas dan terpusat.' : 'Produk terdeteksi: $resolvedName';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _validatedProductName = null; _validatedProductId = null; _captureStatusMessage = e.toString().replaceFirst('Exception: ', ''); });
    } finally { if (mounted) setState(() => _validatingCapture = false); }
  }

  Future<void> _processImage() async {
    final file = _selectedFile;
    final previewBytes = _previewBytes;
    if (file == null || previewBytes == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih atau foto gambar produk dulu.'))); return; }
    if (_validatedProductName == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk belum dikenali. Foto ulang sampai hasil valid.'))); return; }
    setState(() => _processing = true);
    try {
      final classifier = ref.read(classifierServiceProvider);
      final result = await classifier.classifyProduct(file, allowPackageDetectionFallback: false, requireStrongPrediction: true);
      if (!mounted) return;
      final productId = result?.productId ?? _validatedProductId;
      if (productId == null || productId <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk terdeteksi tetapi belum ada di database.'))); return; }
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductResultPage(productId: productId, isFromClassifier: true, previewBytes: previewBytes)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally { if (mounted) setState(() => _processing = false); }
  }

  // ─── BUILD (UI UPGRADED) ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isBusy = _processing || _validatingCapture;

    return Scaffold(
      // ─── OLD appBar: AppBar(title: const Text('Cek Sugar')), ───
      appBar: AppBar(
        title: const Text('Cek Sugar'),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // ─── OLD info box ───
          // Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF3FBF8), ...),
          // ─── NEW info box ───
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFD1FAE5), Color(0xFFECFDF5)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: const Color(0xFF0D9F6E).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF0D9F6E), size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Cek sugar dari gambar produk', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827), letterSpacing: -0.2)),
                SizedBox(height: 6),
                Text('Ambil foto atau upload gambar kemasan produk. Nama produk hanya akan muncul setelah foto berhasil divalidasi.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5)),
              ])),
            ]),
          ),
          const SizedBox(height: 20),
          // Image preview
          if (_previewBytes != null)
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 16, offset: Offset(0, 6))]),
              child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.memory(_previewBytes!, height: 250, width: double.infinity, fit: BoxFit.cover)),
            )
          else
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.image_search_outlined, size: 32, color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(height: 14),
                const Text('Belum ada gambar dipilih', style: TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500, fontSize: 14)),
              ]),
            ),
          const SizedBox(height: 16),
          // Status message
          if (_captureStatusMessage != null)
            Container(
              width: double.infinity, padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _validatedProductName == null ? const Color(0xFFFEF3C7) : const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _validatedProductName == null ? const Color(0xFFF59E0B) : const Color(0xFF0D9F6E)),
              ),
              child: Row(children: [
                Icon(_validatedProductName == null ? Icons.info_outline_rounded : Icons.check_circle_rounded,
                  color: _validatedProductName == null ? const Color(0xFFF59E0B) : const Color(0xFF0D9F6E), size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_captureStatusMessage!, style: TextStyle(
                  color: _validatedProductName == null ? const Color(0xFF92400E) : const Color(0xFF065F46), fontWeight: FontWeight.w600, fontSize: 13,
                ))),
              ]),
            ),
          if (_captureStatusMessage != null) const SizedBox(height: 12),
          // Product name
          if (_validatedProductName != null)
            Container(
              width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD1FAE5)),
                boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Row(children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF0D9F6E), size: 22),
                const SizedBox(width: 10),
                Expanded(child: Text('Nama produk: $_validatedProductName', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF111827)))),
              ]),
            ),
          if (_validatedProductName != null) const SizedBox(height: 16),
          // Action buttons
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: isBusy ? null : () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.upload_rounded, size: 20),
              label: const Text('Upload'),
            )),
            const SizedBox(width: 12),
            Expanded(child: FilledButton.icon(
              onPressed: isBusy ? null : () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_rounded, size: 20),
              label: const Text('Foto'),
            )),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isBusy ? null : _processImage,
              icon: isBusy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome_rounded, size: 20),
              label: Text(isBusy ? 'Memproses...' : 'Proses Cek Sugar'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D9F6E),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
