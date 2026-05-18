import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/api_models.dart';
import '../providers/app_providers.dart';
import '../widgets/smart_network_image.dart';

class ArticleDetailPage extends ConsumerStatefulWidget {
  const ArticleDetailPage({super.key, required this.articleId});

  final int articleId;

  @override
  ConsumerState<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends ConsumerState<ArticleDetailPage> {
  bool _loading = true;
  String _error = '';
  ArticleItem? _article;
  List<ArticleItem> _recommended = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await ref.read(apiServiceProvider).getArticleDetail(widget.articleId);
      if (!mounted) return;
      setState(() {
        _article = data.article;
        _recommended = data.recommendedArticles;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Artikel')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Text(_error))
              : _article == null
                  ? const Center(child: Text('Artikel tidak ditemukan'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_article!.image.isNotEmpty)
                          SizedBox(
                            height: 220,
                            width: double.infinity,
                            child: SmartNetworkImage(
                              imageUrl: _article!.image,
                              width: double.infinity,
                              height: 220,
                              fit: BoxFit.cover,
                              fallbackAsset: 'assets/images/image-logo.png',
                              borderRadius: 16,
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          _article!.title,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatPublishedAt(_article!.publishedAt),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _article!.content,
                          style: const TextStyle(fontSize: 16, height: 1.5),
                        ),
                        if (_recommended.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          const Text(
                            'Rekomendasi Artikel Lain',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          ..._recommended.map((item) {
                            return Card(
                              child: ListTile(
                                leading: item.image.isNotEmpty
                                    ? SmartNetworkImage(
                                        imageUrl: item.image,
                                        width: 52,
                                        height: 52,
                                        fit: BoxFit.cover,
                                        fallbackAsset: 'assets/images/image-logo.png',
                                        borderRadius: 8,
                                      )
                                    : const SizedBox(width: 52, height: 52),
                                title: Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  _formatPublishedAt(item.publishedAt),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => ArticleDetailPage(articleId: item.id),
                                    ),
                                  );
                                },
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
    );
  }

  String _formatPublishedAt(String raw) {
    if (raw.trim().isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd MMMM yyyy', 'id_ID').format(parsed.toLocal());
  }
}
