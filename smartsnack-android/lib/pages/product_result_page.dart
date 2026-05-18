import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import '../providers/app_providers.dart';
import '../widgets/grade_badge.dart';
import '../widgets/product_card.dart';
import '../widgets/smart_network_image.dart';

class ProductResultPage extends ConsumerStatefulWidget {
  const ProductResultPage({
    super.key,
    required this.productId,
    this.isFromClassifier = false,
    this.previewBytes,
  });

  final int productId;
  final bool isFromClassifier;
  final Uint8List? previewBytes;

  @override
  ConsumerState<ProductResultPage> createState() => _ProductResultPageState();
}

class _ProductResultPageState extends ConsumerState<ProductResultPage> with SingleTickerProviderStateMixin {
  ProductDetail? _detail;
  List<ProductItem> _recommendations = <ProductItem>[];
  SnackBoxStatus? _boxStatus;
  bool _loading = true;
  double _todaySugar = 0;
  double _sugarLimit = 25;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final detail = await api.getProductDetail(widget.productId);
      List<ProductItem> recommendations = <ProductItem>[];
      SnackBoxStatus? boxStatus;

      try {
        recommendations = await api.getRecommendations(widget.productId);
      } catch (_) {}

      try {
        await api.saveSearchProduct(widget.productId);
      } catch (_) {}

      try {
        boxStatus = await api.getSnackBoxStatus();
      } catch (_) {}

      _detail = detail;
      _recommendations = recommendations;
      _boxStatus = boxStatus;
      _todaySugar = boxStatus?.todaySugar ?? 0;
      _sugarLimit = boxStatus?.sugarLimit ?? 25;

      if (mounted) {
        _showGradeDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _consumeProduct() async {
    if (_detail == null || _boxStatus == null) return;

    try {
      final api = ref.read(apiServiceProvider);
      if (!_boxStatus!.canConsume) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_boxStatus!.message)),
          );
        }
        return;
      }

      await api.consumeProduct(productId: widget.productId);
      final refreshedStatus = await api.getSnackBoxStatus();
      if (mounted) {
        setState(() {
          _boxStatus = refreshedStatus;
          _todaySugar = refreshedStatus.todaySugar;
          _sugarLimit = refreshedStatus.sugarLimit;
        });
        ref.read(profileRefreshSignalProvider.notifier).state++;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk berhasil dikonsumsi')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  String _resolveGradeFromShownSugar(ProductDetail detail) {
    final sugar = detail.grSugarContent;
    if (sugar < 2.5) return 'Hijau';
    if (sugar <= 11.25) return 'Kuning';
    return 'Merah';
  }

  void _showGradeDialog() {
    if (_detail == null) return;
    final resolvedGrade = _resolveGradeFromShownSugar(_detail!);
    final grade = resolvedGrade.toLowerCase();
    String message;
    switch (grade) {
      case 'merah':
        message = 'Kadar gula produk ini tinggi. Batasi konsumsi agar tidak melebihi 25 gram per hari.';
        break;
      case 'kuning':
        message = 'Kadar gula produk ini sedang. Konsumsi tetap perlu diperhatikan.';
        break;
      case 'hijau':
        message = 'Kadar gula produk ini rendah dan relatif lebih aman.';
        break;
      default:
        message = 'Kadar gula produk ini tidak diketahui.';
    }

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Sugar Grade: $resolvedGrade'),
        content: Text(message),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_detail?.name ?? 'Detail Produk'),
          bottom: const TabBar(tabs: [Tab(text: 'Sugar Grade'), Tab(text: 'Informasi Lainnya')]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _detail == null
                ? const Center(child: Text('Detail produk tidak tersedia'))
                : TabBarView(
                    children: [
                      Builder(
                        builder: (context) {
                          final resolvedGrade = _resolveGradeFromShownSugar(_detail!);
                          final normalizedResolvedGrade = resolvedGrade.toLowerCase();
                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              if (widget.previewBytes != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.memory(widget.previewBytes!, height: 210, fit: BoxFit.cover),
                                )
                              else
                                SizedBox(
                                  height: 210,
                                  width: double.infinity,
                                  child: SmartNetworkImage(
                                    imageUrl: _detail!.image,
                                    width: double.infinity,
                                    height: 210,
                                    fit: BoxFit.cover,
                                    borderRadius: 16,
                                  ),
                                ),
                              const SizedBox(height: 12),
                              GradeBadge(grade: resolvedGrade),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF6F1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Jumlah gula produk ini: ${_detail!.grSugarContent.toStringAsFixed(2)} gram',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A8F6B),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                normalizedResolvedGrade == 'merah'
                                    ? 'Produk ini mengandung kadar gula tinggi.'
                                    : normalizedResolvedGrade == 'kuning'
                                        ? 'Produk ini mengandung kadar gula sedang.'
                                        : 'Produk ini mengandung kadar gula rendah.',
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Batas gula harian: ${_sugarLimit.toStringAsFixed(0)}g | Konsumsi hari ini: ${_todaySugar.toStringAsFixed(2)}g',
                                style: const TextStyle(color: Colors.black54),
                              ),
                              if (_boxStatus != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Prediksi diabetes: ${_boxStatus!.riskDiabetes} | Sisa kuota: ${_boxStatus!.remainingSugar.toStringAsFixed(2)}g',
                                  style: const TextStyle(color: Colors.black54),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _boxStatus!.message,
                                  style: TextStyle(
                                    color: _boxStatus!.canConsume ? Colors.green.shade700 : Colors.red.shade700,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: (_boxStatus?.canConsume ?? false) ? _consumeProduct : null,
                                  child: const Text('Konsumsi Produk Ini'),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(_detail!.information),
                          const SizedBox(height: 16),
                          if (_recommendations.isNotEmpty)
                            const Text(
                              'Temukan produk serupa dengan sugar grade yang lebih rendah!',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          const SizedBox(height: 8),
                          ..._recommendations.map(
                            (item) => ProductCard(
                              product: item,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ProductResultPage(productId: item.id),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}
