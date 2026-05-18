import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import '../providers/app_providers.dart';
import '../widgets/smart_network_image.dart';
import 'cek_sugar_page.dart';
import 'product_result_page.dart';
import 'product_search_page.dart';
import 'report_page.dart';
import 'sugar_info_page.dart';
import 'tambah_kemasan_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _pageController = PageController(viewportFraction: 1);
  int _bannerIndex = 0;
  bool _loadingRecommendations = true;
  List<ProductItem> _recommendedItems = <ProductItem>[];

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadRecommendations() async {
    setState(() => _loadingRecommendations = true);
    try {
      final products = await ref.read(apiServiceProvider).getAllProducts();
      final visibleItems = products.where((item) {
        return item.id > 0 && item.name.trim().isNotEmpty;
      }).toList()
        ..sort((a, b) => a.grSugarContent.compareTo(b.grSugarContent));
      final lowAndMedium = visibleItems.where((item) => !_isHighSugar(item)).take(4).toList();
      final fallbackItems = visibleItems.take(4).toList();
      if (!mounted) return;
      setState(() {
        _recommendedItems = lowAndMedium.isNotEmpty ? lowAndMedium : fallbackItems;
        _loadingRecommendations = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recommendedItems = <ProductItem>[];
        _loadingRecommendations = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return RefreshIndicator(
      onRefresh: _loadRecommendations,
      color: const Color(0xFF0D9F6E),
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, topInset + 24, 20, 32),
        children: [
          // ─── OLD Title ───
          // const Text('SMART SNACK', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF10A341), letterSpacing: 0.2)),
          // ─── NEW Title ───
          const Text(
            'SMART SNACK',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 22),
          _SearchBar(onTap: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProductSearchPage()));
          }),
          const SizedBox(height: 24),
          // Banner
          SizedBox(
            height: 276,
            child: Stack(children: [
              Positioned.fill(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (value) => setState(() => _bannerIndex = value),
                  children: const [
                    _BannerImage(assetPath: 'assets/images/image-home-1.png'),
                    _BannerImage(assetPath: 'assets/images/image-home-2.png'),
                    _BannerImage(assetPath: 'assets/images/image-home-3.png'),
                  ],
                ),
              ),
              const Positioned.fill(child: IgnorePointer(child: _BannerTextOverlay())),
              Positioned(
                left: 24, bottom: 28,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CekSugarPage()));
                  },
                  // ─── OLD style ───
                  // style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0B8F2B), ...),
                  // ─── NEW style ───
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9F6E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    elevation: 4,
                    shadowColor: const Color(0x400D9F6E),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  label: const Text('Scan Sekarang', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          // Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: index == _bannerIndex ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: index == _bannerIndex ? const Color(0xFF0D9F6E) : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(99),
              ),
            )),
          ),
          const SizedBox(height: 26),
          // Shortcut cards
          Row(children: [
            Expanded(child: _ShortcutCard(
              accentColor: const Color(0xFFD1FAE5),
              iconColor: const Color(0xFF0D9F6E),
              icon: Icons.camera_alt_rounded,
              title: 'Tambah\nKemasan',
              subtitle: 'Scan foto label &\nGizi',
              actionLabel: 'Add',
              onTap: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TambahKemasanPage())); },
            )),
            const SizedBox(width: 14),
            Expanded(child: _ShortcutCard(
              accentColor: const Color(0xFFFEF3C7),
              iconColor: const Color(0xFFD97706),
              icon: Icons.bar_chart_rounded,
              title: 'Sugar Grade',
              subtitle: 'Pelajari level gula',
              actionLabel: 'Pelajari',
              actionColor: const Color(0xFFD97706),
              onTap: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SugarInfoPage())); },
            )),
          ]),
          const SizedBox(height: 16),
          _ReportCard(onTap: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportPage()));
          }),
          const SizedBox(height: 28),
          // Recommendations header
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const Expanded(
              child: Text('Rekomendasi Snack\nRendah Gula', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827), height: 1.3, letterSpacing: -0.3)),
            ),
            TextButton(
              onPressed: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProductSearchPage())); },
              child: const Text('Lihat Semua →', style: TextStyle(color: Color(0xFF0D9F6E), fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ]),
          const SizedBox(height: 12),
          if (_loadingRecommendations)
            const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Center(child: CircularProgressIndicator()))
          else if (_recommendedItems.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF0F0F0)),
              ),
              child: const Text('Produk rekomendasi belum tersedia.', style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recommendedItems.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.62,
              ),
              itemBuilder: (context, index) {
                final item = _recommendedItems[index];
                return _RecommendationCard(
                  product: item,
                  badgeLabel: _badgeLabel(item),
                  badgeColor: _badgeColor(item),
                  onTap: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductResultPage(productId: item.id))); },
                );
              },
            ),
        ],
      ),
    );
  }

  bool _isHighSugar(ProductItem item) {
    final normalized = _normalizeGrade(item);
    if (normalized == 'merah' || normalized == 'high') return true;
    return item.grSugarContent > 11.25;
  }

  String _badgeLabel(ProductItem item) {
    final normalized = _normalizeGrade(item);
    if (normalized == 'hijau' || normalized == 'green' || item.grSugarContent < 2.5) return 'Low Sugar';
    if (normalized == 'kuning' || normalized == 'yellow' || item.grSugarContent <= 11.25) return 'Medium Sugar';
    return 'High Sugar';
  }

  Color _badgeColor(ProductItem item) {
    final label = _badgeLabel(item);
    if (label == 'Low Sugar') return const Color(0xFF10B981);
    if (label == 'Medium Sugar') return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String _normalizeGrade(ProductItem item) => item.sugarGrade.trim().toLowerCase();
}

// ─── SEARCH BAR ──────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    // ─── OLD SearchBar ───
    // return Material(color: Colors.white, borderRadius: BorderRadius.circular(999), elevation: 0,
    //   child: InkWell(borderRadius: BorderRadius.circular(999), onTap: onTap,
    //     child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    //       decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFBDCCB9))),
    //       child: const Row(children: [Icon(Icons.search, color: Color(0xFF7A8477), size: 30), SizedBox(width: 12),
    //         Text('Cari snack favoritmu...', style: TextStyle(fontSize: 16, color: Color(0xFF69727D), fontWeight: FontWeight.w500))]),
    //     ),
    //   ),
    // );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.search_rounded, color: Color(0xFF0D9F6E), size: 22),
            ),
            const SizedBox(width: 14),
            const Text('Cari snack favoritmu...', style: TextStyle(fontSize: 15, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

// ─── BANNER IMAGE ────────────────────────────────────────────────────────────
class _BannerImage extends StatelessWidget {
  const _BannerImage({required this.assetPath});
  final String assetPath;
  @override
  Widget build(BuildContext context) {
    // ─── OLD ───
    // return Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(28),
    //   boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, 10))]),
    //   child: ClipRRect(borderRadius: BorderRadius.circular(28),
    //     child: Image.asset(assetPath, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFE6F4EF)))),
    // );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.asset(assetPath, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFD1FAE5))),
      ),
    );
  }
}

// ─── BANNER TEXT OVERLAY ─────────────────────────────────────────────────────
class _BannerTextOverlay extends StatelessWidget {
  const _BannerTextOverlay();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(fit: StackFit.expand, children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Color(0xAA09130B), Color(0x3309130B), Color(0x0009130B)],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 88),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Spacer(),
              Text('Cek sugar snack favoritmu', style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.3)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── SHORTCUT CARD ───────────────────────────────────────────────────────────
class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.accentColor, required this.iconColor, required this.icon,
    required this.title, required this.subtitle, required this.actionLabel,
    required this.onTap, this.actionColor = const Color(0xFF0D9F6E),
  });
  final Color accentColor, iconColor, actionColor;
  final IconData icon;
  final String title, subtitle, actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // ─── OLD ShortcutCard ───
    // return Material(color: Colors.white, borderRadius: BorderRadius.circular(28), child: InkWell(...));
    // ─── NEW ───
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          height: 240,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFF0F0F0)),
            boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827), height: 1.35, letterSpacing: -0.2)),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500, height: 1.4)),
            const Spacer(),
            Text('$actionLabel →', style: TextStyle(color: actionColor, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}

// ─── REPORT CARD ─────────────────────────────────────────────────────────────
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    // ─── OLD ───
    // return Material(color: Colors.transparent, child: InkWell(...));
    // ─── NEW ───
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(colors: [Color(0xFF0D9F6E), Color(0xFF10B981)]),
            boxShadow: const [BoxShadow(color: Color(0x300D9F6E), blurRadius: 20, offset: Offset(0, 8))],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Row(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.assessment_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 18),
              const Expanded(
                child: Text('Report Konsumsi\nKemasan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, height: 1.4, letterSpacing: -0.2)),
              ),
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 26),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── RECOMMENDATION CARD ─────────────────────────────────────────────────────
class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.product, required this.badgeLabel, required this.badgeColor, required this.onTap});
  final ProductItem product;
  final String badgeLabel;
  final Color badgeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A6B4F), Color(0xFF2D8B6E)]),
                boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 16, offset: Offset(0, 6))],
              ),
              child: Stack(children: [
                Positioned(
                  top: 14, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(999)),
                    child: Text(badgeLabel, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 40, 8, 8),
                    child: SmartNetworkImage(imageUrl: product.image, width: 156, height: 182, fit: BoxFit.contain, fallbackAsset: 'assets/images/dummyproduct.png'),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827), height: 1.25, letterSpacing: -0.2)),
          const SizedBox(height: 3),
          Text(_secondaryText(product), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  String _secondaryText(ProductItem product) {
    if (product.category.trim().isNotEmpty) return product.category;
    if (product.netWeight.trim().isNotEmpty) return product.netWeight;
    return 'Smart Snack';
  }
}