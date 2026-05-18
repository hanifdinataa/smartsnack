import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import '../providers/app_providers.dart';
import 'report_chart_page.dart';

enum ReportListType { weekly, monthly, yearly }

class ReportListPage extends ConsumerStatefulWidget {
  const ReportListPage({super.key, required this.type});

  final ReportListType type;

  @override
  ConsumerState<ReportListPage> createState() => _ReportListPageState();
}

class _ReportListPageState extends ConsumerState<ReportListPage> {
  final _search = TextEditingController();
  bool _loading = true;
  List<ReportListItem> _items = <ReportListItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      List<ReportListItem> data;
      switch (widget.type) {
        case ReportListType.weekly:
          data = await api.getWeeklyReports();
          break;
        case ReportListType.monthly:
          data = await api.getMonthlyReports();
          break;
        case ReportListType.yearly:
          data = await api.getYearlyReports();
          break;
      }

      if (widget.type == ReportListType.monthly) {
        final seen = <String>{};
        data = data.where((e) => seen.add('${e.month}-${e.year}')).toList();
      }

      if (widget.type == ReportListType.yearly) {
        final seen = <int>{};
        data = data.where((e) => e.year != null && seen.add(e.year!)).toList();
      }

      if (mounted) {
        setState(() {
          _items = data;
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

  Future<void> _searchAction() async {
    final query = _search.text.trim();
    if (query.isEmpty) {
      await _load();
      return;
    }

    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      var data = await api.searchReports(query);

      if (widget.type == ReportListType.monthly) {
        final seen = <String>{};
        data = data.where((e) => seen.add('${e.month}-${e.year}')).toList();
      }

      if (widget.type == ReportListType.yearly) {
        final seen = <int>{};
        data = data.where((e) => e.year?.toString() == query && e.year != null && seen.add(e.year!)).toList();
      }

      if (mounted) {
        setState(() {
          _items = data;
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

  String get _title {
    switch (widget.type) {
      case ReportListType.weekly:
        return 'Weekly Report';
      case ReportListType.monthly:
        return 'Monthly Report';
      case ReportListType.yearly:
        return 'Yearly Report';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchAction(),
                    decoration: const InputDecoration(hintText: 'Cari report', prefixIcon: Icon(Icons.search)),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _searchAction, child: const Text('Cari')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? const Center(child: Text('Tidak ada report ditemukan'))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            String text;
                            if (widget.type == ReportListType.weekly) {
                              text = item.report ?? '-';
                            } else if (widget.type == ReportListType.monthly) {
                              text = '${item.month ?? ''} ${item.year ?? ''}';
                            } else {
                              text = 'Tahun ${item.year ?? '-'}';
                            }

                            return Card(
                              child: ListTile(
                                title: Text(text),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  if (widget.type == ReportListType.weekly && item.id != null) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ReportChartPage.weekly(
                                          reportId: item.id!,
                                          title: '${item.month ?? ''} ${item.year ?? ''}',
                                        ),
                                      ),
                                    );
                                  } else if (widget.type == ReportListType.monthly && item.month != null && item.year != null) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ReportChartPage.monthly(
                                          month: item.month!,
                                          year: item.year!,
                                          title: '${item.month!} ${item.year!}',
                                        ),
                                      ),
                                    );
                                  } else if (widget.type == ReportListType.yearly && item.year != null) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ReportChartPage.yearly(
                                          year: item.year!,
                                          title: 'Tahun ${item.year!}',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
