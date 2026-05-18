import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/app_providers.dart';
import '../widgets/camera_capture_view.dart';

class TambahKemasanPage extends ConsumerStatefulWidget {
  const TambahKemasanPage({super.key});
  @override
  ConsumerState<TambahKemasanPage> createState() => _TambahKemasanPageState();
}

class _TambahKemasanPageState extends ConsumerState<TambahKemasanPage> {
  late final AppLifecycleListener _appLifecycleListener;
  final _nameController = TextEditingController();
  final _sugarController = TextEditingController();
  final _netWeightController = TextEditingController(text: '100');

  XFile? _packageImageFile;
  Uint8List? _packagePreviewBytes;
  XFile? _nutritionImageFile;
  Uint8List? _nutritionPreviewBytes;

  String _category = 'food';
  String _rawNutritionText = '';
  bool _processingPackage = false;
  bool _processingNutrition = false;
  bool _saving = false;
  bool _packageDone = false;
  bool _nutritionDone = false;
  String? _packageStatusMessage;
  bool _packageMatchedExisting = false;

  bool get _busy => _processingPackage || _processingNutrition || _saving;

  // ─── ALL LOGIC METHODS UNCHANGED ─────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _appLifecycleListener = AppLifecycleListener(onResume: () { ref.read(classifierServiceProvider).dispose(); });
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    _nameController.dispose();
    _sugarController.dispose();
    _netWeightController.dispose();
    super.dispose();
  }

  Future<void> _pickPackageImage() => _pickImage(forPackage: true);
  Future<void> _pickNutritionImage() => _pickImage(forPackage: false);

  Future<void> _pickImage({required bool forPackage}) async {
    if (_busy) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1800, maxHeight: 1800);
    if (file == null) return;
    _setImage(file, await file.readAsBytes(), forPackage: forPackage);
  }

  Future<void> _openCamera({required bool forPackage}) async {
    if (_busy) return;
    if (kIsWeb) { await _captureFromWebCamera(forPackage: forPackage); return; }
    final file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1800, maxHeight: 1800, preferredCameraDevice: CameraDevice.rear);
    if (file == null) return;
    _setImage(file, await file.readAsBytes(), forPackage: forPackage);
  }

  void _setImage(XFile file, Uint8List bytes, {required bool forPackage}) {
    setState(() {
      if (forPackage) { _packageImageFile = file; _packagePreviewBytes = bytes; _packageDone = false; _packageStatusMessage = null; _packageMatchedExisting = false; }
      else { _nutritionImageFile = file; _nutritionPreviewBytes = bytes; _nutritionDone = false; _rawNutritionText = ''; }
    });
  }

  Future<void> _captureFromWebCamera({required bool forPackage}) async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) {
      return SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: AspectRatio(aspectRatio: 3 / 4, child: CameraCaptureView(
        isProcessing: _busy, captureLabel: forPackage ? 'Foto Kemasan' : 'Foto Label Gizi',
        onCapture: (bytes) async {
          final now = DateTime.now().millisecondsSinceEpoch;
          final file = XFile.fromData(bytes, mimeType: 'image/jpeg', name: forPackage ? 'kemasan_$now.jpg' : 'label_gizi_$now.jpg');
          _setImage(file, bytes, forPackage: forPackage); Navigator.of(ctx).pop();
        },
      ))));
    });
  }

  Future<void> _processPackage() async {
    final file = _packageImageFile;
    if (file == null) { _showSnack('Upload atau ambil foto kemasan terlebih dahulu.'); return; }
    setState(() => _processingPackage = true);
    try {
      final detected = await _detectPackageFromModel(file);
      setState(() { _packageDone = detected; });
      if (detected) { _showSnack('Nama kemasan dan kategori berhasil terdeteksi otomatis.'); }
      else { _showSnack('Produk belum dikenali. Silakan isi nama dan kategori secara manual.'); }
    } catch (e) { _showSnack(_friendlyError(e)); }
    finally { if (mounted) setState(() => _processingPackage = false); }
  }

  Future<bool> _detectPackageFromModel(XFile file) async {
    try {
      final classifier = ref.read(classifierServiceProvider);
      final result = await classifier.classifyProduct(file, allowPackageDetectionFallback: false, requireStrongPrediction: false);
      if (result == null || !result.hasLabel || !result.isStrongPrediction) {
        if (!mounted) return false;
        setState(() { _packageStatusMessage = 'Produk belum dikenali. Coba foto kemasan yang lebih jelas.'; _packageMatchedExisting = false; });
        return false;
      }
      if (!mounted) return false;
      if (result.productId != null && result.productId! > 0) {
        final detail = await ref.read(apiServiceProvider).getProductDetail(result.productId!);
        if (!mounted) return false;
        final name = detail.name.trim();
        if (name.isEmpty) return false;
        setState(() { _nameController.text = name; _category = detail.category == 'drink' ? 'drink' : 'food'; _packageStatusMessage = 'Produk ditemukan di database.'; _packageMatchedExisting = true; });
        return true;
      }
      setState(() {
        _nameController.text = result.label.trim();
        if (result.category.trim().isNotEmpty) { _category = result.category == 'drink' ? 'drink' : 'food'; }
        _packageStatusMessage = 'Produk belum ada di database, silakan lengkapi data untuk menambahkan.'; _packageMatchedExisting = false;
      });
      return true;
    } catch (_) { return false; }
  }

  Future<void> _processNutrition() async {
    final file = _nutritionImageFile;
    if (file == null) { _showSnack('Upload atau ambil foto label gizi terlebih dahulu.'); return; }
    setState(() => _processingNutrition = true);
    try {
      final result = await ref.read(apiServiceProvider).detectNutritionLabelFromFile(file);
      final sugar = result.grSugarContent;
      if (sugar == null) { _showSnack('Jumlah gula belum terbaca. Coba foto label gizi yang lebih lurus dan terang.'); return; }
      setState(() {
        _sugarController.text = _formatNumber(sugar);
        if (result.netWeight != null && result.netWeight! > 0) { _netWeightController.text = _formatNumber(result.netWeight!); }
        _rawNutritionText = result.rawText; _nutritionDone = true;
      });
      _showSnack('Label gizi berhasil diproses.');
    } catch (e) { _showSnack(_friendlyError(e)); }
    finally { if (mounted) setState(() => _processingNutrition = false); }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final sugar = double.tryParse(_sugarController.text.replaceAll(',', '.'));
    final netWeight = double.tryParse(_netWeightController.text.replaceAll(',', '.'));
    if (name.isEmpty) { _showSnack('Nama kemasan wajib diisi.'); return; }
    if (sugar == null || sugar < 0) { _showSnack('Jumlah gula wajib berupa angka.'); return; }
    if (netWeight == null || netWeight <= 0) { _showSnack('Takaran saji wajib berupa angka lebih dari 0.'); return; }
    if (_packageImageFile == null) { _showSnack('Foto kemasan wajib ada agar produk tampil di pencarian.'); return; }
    setState(() => _saving = true);
    try {
      final result = await ref.read(apiServiceProvider).recognizeNutritionLabel(
        name: name, category: _category, grSugarContent: sugar, netWeight: netWeight,
        scanSource: 'manual_input', rawText: _rawNutritionText.isEmpty ? null : _rawNutritionText, productImageFile: _packageImageFile,
      );
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Kemasan Tersimpan'),
        content: Text('Nama: ${result.productName}\nKategori: ${result.category}\nGula: ${result.grSugarContent.toStringAsFixed(2)} gram\nProduk sudah masuk ke pencarian.'),
        actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Oke'))],
      ));
      if (!mounted) return;
      _showSnack('Produk tersimpan. Cek di menu pencarian produk.');
      setState(() {
        _nameController.clear(); _sugarController.clear(); _netWeightController.text = '100';
        _category = 'food'; _rawNutritionText = ''; _packageImageFile = null; _packagePreviewBytes = null;
        _nutritionImageFile = null; _nutritionPreviewBytes = null; _packageDone = false; _nutritionDone = false;
        _packageStatusMessage = null; _packageMatchedExisting = false;
      });
    } catch (e) { _showSnack(_friendlyError(e)); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  String _formatNumber(double value) {
    if (value.truncateToDouble() == value) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  String _friendlyError(Object error) => error.toString().replaceFirst('Exception: ', '');
  void _showSnack(String message) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }

  // ─── BUILD (UI UPGRADED) ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ─── OLD appBar ───
      // appBar: AppBar(title: const Text('Tambah Kemasan')),
      // ─── NEW appBar ───
      appBar: AppBar(
        title: const Text('Tambah Kemasan'),
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
          // Step indicator
          _buildStepHeader(1, 'Scan Kemasan', _packageDone),
          const SizedBox(height: 10),
          _buildScanBlock(
            subtitle: 'Output: nama kemasan dan kategori.',
            previewBytes: _packagePreviewBytes, done: _packageDone, loading: _processingPackage,
            uploadLabel: 'Upload', cameraLabel: 'Foto',
            processLabel: _processingPackage ? 'Memproses...' : 'Proses Kemasan',
            onUpload: _busy ? null : _pickPackageImage,
            onCamera: _busy ? null : () => _openCamera(forPackage: true),
            onProcess: _busy ? null : _processPackage,
          ),
          const SizedBox(height: 20),
          _buildStepHeader(2, 'Scan Label Gizi', _nutritionDone),
          const SizedBox(height: 10),
          _buildScanBlock(
            subtitle: 'Output: jumlah gula/sugar dari label gizi.',
            previewBytes: _nutritionPreviewBytes, done: _nutritionDone, loading: _processingNutrition,
            uploadLabel: 'Upload', cameraLabel: 'Foto',
            processLabel: _processingNutrition ? 'Memproses...' : 'Proses Label',
            onUpload: _busy ? null : _pickNutritionImage,
            onCamera: _busy ? null : () => _openCamera(forPackage: false),
            onProcess: _busy ? null : _processNutrition,
          ),
          const SizedBox(height: 20),
          _buildStepHeader(3, 'Form Kemasan', false),
          const SizedBox(height: 10),
          _buildForm(),
        ],
      ),
    );
  }

  Widget _buildStepHeader(int step, String title, bool done) {
    return Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: done ? const Color(0xFF0D9F6E) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(child: done
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
          : Text('$step', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: done ? Colors.white : const Color(0xFF374151)))),
      ),
      const SizedBox(width: 12),
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827), letterSpacing: -0.2)),
      if (done) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(99)),
          child: const Text('Selesai', style: TextStyle(color: Color(0xFF0D9F6E), fontWeight: FontWeight.w600, fontSize: 12)),
        ),
      ],
    ]);
  }

  // ─── OLD _buildScanBlock ───
  // Widget _buildScanBlock({...}) { return Container(padding: const EdgeInsets.all(16), ...); }
  // ─── NEW _buildScanBlock ───
  Widget _buildScanBlock({
    required String subtitle, required Uint8List? previewBytes, required bool done,
    required bool loading, required String uploadLabel, required String cameraLabel,
    required String processLabel, required VoidCallback? onUpload, required VoidCallback? onCamera, required VoidCallback? onProcess,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(subtitle, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _actionButton(Icons.image_outlined, uploadLabel, onUpload, outlined: true)),
          const SizedBox(width: 10),
          Expanded(child: _actionButton(Icons.photo_camera_outlined, cameraLabel, onCamera, outlined: true)),
        ]),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: onProcess,
          icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
          label: Text(processLabel),
        )),
        if (loading) ...[const SizedBox(height: 12), ClipRRect(borderRadius: BorderRadius.circular(8), child: const LinearProgressIndicator(minHeight: 4))],
        if (previewBytes != null) ...[
          const SizedBox(height: 14),
          ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(previewBytes, height: 180, width: double.infinity, fit: BoxFit.cover)),
        ],
      ]),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback? onPressed, {bool outlined = false}) {
    if (outlined) {
      return OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label, style: const TextStyle(fontSize: 13)));
    }
    return FilledButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label, style: const TextStyle(fontSize: 13)));
  }

  // ─── OLD _buildForm ───
  // Widget _buildForm() { return Container(padding: const EdgeInsets.all(16), ...); }
  // ─── NEW _buildForm ───
  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_packageStatusMessage != null) ...[
          Container(
            width: double.infinity, padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _packageMatchedExisting ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _packageMatchedExisting ? const Color(0xFF0D9F6E) : const Color(0xFFF59E0B)),
            ),
            child: Row(children: [
              Icon(_packageMatchedExisting ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                color: _packageMatchedExisting ? const Color(0xFF0D9F6E) : const Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(_packageStatusMessage!, style: TextStyle(
                color: _packageMatchedExisting ? const Color(0xFF065F46) : const Color(0xFF92400E), fontWeight: FontWeight.w600, fontSize: 13,
              ))),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nama kemasan', prefixIcon: Icon(Icons.inventory_2_outlined, size: 20))),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: _category,
          decoration: const InputDecoration(labelText: 'Kategori kemasan', prefixIcon: Icon(Icons.category_outlined, size: 20)),
          items: const [DropdownMenuItem(value: 'food', child: Text('Food')), DropdownMenuItem(value: 'drink', child: Text('Drink'))],
          onChanged: _busy ? null : (value) => setState(() => _category = value ?? 'food'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _sugarController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(labelText: 'Jumlah gula / sugar (gram)', prefixIcon: Icon(Icons.water_drop_outlined, size: 20)),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _netWeightController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(
            labelText: 'Takaran saji / berat bersih (gram/ml)',
            helperText: 'Default 100 jika label tidak mencantumkan takaran.',
            prefixIcon: Icon(Icons.scale_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_rounded, size: 20),
            label: Text(_saving ? 'Menyimpan...' : 'Simpan ke Pencarian Produk'),
          ),
        ),
      ]),
    );
  }
}
