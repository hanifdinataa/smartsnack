import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import '../providers/app_providers.dart';
import '../widgets/smart_network_image.dart';
import 'article_detail_page.dart';

class ArticlePage extends ConsumerStatefulWidget {
  const ArticlePage({super.key, required this.onBackHome});
  final VoidCallback onBackHome;
  @override
  ConsumerState<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends ConsumerState<ArticlePage> {
  bool _loading = true;
  String _error = '';
  List<ArticleItem> _articles = const [];

  // ─── ALL LOGIC UNCHANGED ────────────────────────────────────────────────
  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final data = await ref.read(apiServiceProvider).getArticles();
      if (!mounted) return;
      setState(() => _articles = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  // ─── BUILD (UI UPGRADED) ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 32)),
          const SizedBox(height: 16),
          Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('Coba Lagi')),
        ]),
      ));
    }
    if (_articles.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.article_outlined, color: Color(0xFF9CA3AF), size: 32)),
        const SizedBox(height: 16),
        const Text('Belum ada artikel.', style: TextStyle(color: Color(0xFF6B7280), fontSize: 15, fontWeight: FontWeight.w500)),
      ]));
    }

    return Column(children: [
      // ─── OLD header ───
      // Container(color: const Color(0xFFEAF6F1), padding: EdgeInsets.fromLTRB(8, topInset + 6, 8, 10),
      //   child: Row(children: [IconButton(onPressed: widget.onBackHome, icon: const Icon(Icons.arrow_back)),
      //     const Text('Artikel', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))]));
      // ─── NEW header ───
      Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        padding: EdgeInsets.fromLTRB(8, topInset + 8, 20, 12),
        child: Row(children: [
          IconButton(
            onPressed: widget.onBackHome,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Color(0xFF374151)),
            ),
          ),
          const SizedBox(width: 4),
          const Text('Artikel', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF111827), letterSpacing: -0.3)),
          const Spacer(),
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.auto_stories_rounded, color: Color(0xFF0D9F6E), size: 20),
          ),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          color: const Color(0xFF0D9F6E),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            itemCount: _articles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (_, index) {
              final article = _articles[index];
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArticleDetailPage(articleId: article.id)));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF0F0F0)),
                      boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 12, offset: Offset(0, 4))],
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // ─── OLD image ───
                      // article.image.isNotEmpty ? SmartNetworkImage(imageUrl: article.image, width: 96, height: 96, ...)
                      //   : ClipRRect(..., child: Container(width: 96, height: 96, color: const Color(0xFFEAF6F1)));
                      // ─── NEW image ───
                      article.image.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SmartNetworkImage(imageUrl: article.image, width: 88, height: 88, fit: BoxFit.cover, fallbackAsset: 'assets/images/image-logo.png', borderRadius: 14),
                          )
                        : Container(
                            width: 88, height: 88,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFFD1FAE5), Color(0xFFECFDF5)]),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.article_rounded, color: Color(0xFF0D9F6E), size: 32),
                          ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(article.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF111827), height: 1.3, letterSpacing: -0.2)),
                        const SizedBox(height: 8),
                        Text(article.excerpt.isNotEmpty ? article.excerpt : article.content, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13, height: 1.4)),
                        const SizedBox(height: 8),
                        const Text('Baca selengkapnya →', style: TextStyle(color: Color(0xFF0D9F6E), fontWeight: FontWeight.w600, fontSize: 12)),
                      ])),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}
