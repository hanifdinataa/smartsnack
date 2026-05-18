import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../models/api_models.dart';
import '../providers/app_providers.dart';
import '../widgets/product_card.dart';
import 'product_result_page.dart';

class ProductSearchPage extends ConsumerStatefulWidget {
  const ProductSearchPage({super.key});

  @override
  ConsumerState<ProductSearchPage> createState() => _ProductSearchPageState();
}

class _ProductSearchPageState extends ConsumerState<ProductSearchPage> with RouteAware {
  final _searchController = TextEditingController();
  bool _loading = true;
  Set<int> _consumingIds = <int>{};
  List<ProductItem> _items = <ProductItem>[];
  bool _routeSubscribed = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
      _routeSubscribed = false;
    }
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final result = await ref.read(apiServiceProvider).getAllProducts();
      if (mounted) {
        setState(() {
          _items = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      await _loadAll();
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await ref.read(apiServiceProvider).searchProducts(query);
      if (mounted) {
        setState(() {
          _items = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _consumeFromSearch(ProductItem item) async {
    if (_consumingIds.contains(item.id)) return;
    setState(() {
      _consumingIds = {..._consumingIds, item.id};
    });

    try {
      final api = ref.read(apiServiceProvider);
      await api.consumeProduct(productId: item.id);
      ref.read(profileRefreshSignalProvider.notifier).state++;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} berhasil dikonsumsi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        final next = {..._consumingIds};
        next.remove(item.id);
        _consumingIds = next;
      });
    }
  }

  String _gradeByShownSugar(double sugarGram) {
    if (sugarGram < 2.5) return 'Hijau';
    if (sugarGram <= 11.25) return 'Kuning';
    return 'Merah';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cari Produk')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      hintText: 'Masukkan nama produk',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _search, child: const Text('Cari')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? const Center(child: Text('Tidak ada produk ditemukan'))
                      : RefreshIndicator(
                          onRefresh: _loadAll,
                          child: ListView.builder(
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return ProductCard(
                                product: item,
                                showSecondaryInfo: false,
                                gradeOverride: _gradeByShownSugar(item.grSugarContent),
                                action: FilledButton(
                                  onPressed: _consumingIds.contains(item.id) ? null : () => _consumeFromSearch(item),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    minimumSize: const Size(0, 32),
                                  ),
                                  child: Text(_consumingIds.contains(item.id) ? 'Proses...' : 'Konsumsi'),
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ProductResultPage(productId: item.id),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
