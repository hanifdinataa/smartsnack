import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_providers.dart';
import 'report_list_page.dart';

class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key});

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  bool _loading = true;
  double _todaySugar = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _todaySugar = await ref.read(apiServiceProvider).getTodaySugar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(DateTime.now());
    final color = _todaySugar > 25
        ? const Color(0xFFFF3C3C)
        : _todaySugar >= 12.5
            ? const Color(0xFFFFEB3B)
            : const Color(0xFF27B48A);

    return Scaffold(
      appBar: AppBar(title: const Text('Report Konsumsi Gula')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(formattedDate, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 10),
                Card(
                  color: color,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Konsumsi Gula Hari Ini', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text('${_todaySugar.toStringAsFixed(1)} g / 25 g', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _MenuTile(
                  title: 'Weekly Report',
                  imageAsset: 'assets/icons/icon_week_rep.png',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ReportListPage(type: ReportListType.weekly)),
                    );
                  },
                ),
                _MenuTile(
                  title: 'Monthly Report',
                  imageAsset: 'assets/icons/icon_month_rep.png',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ReportListPage(type: ReportListType.monthly)),
                    );
                  },
                ),
                _MenuTile(
                  title: 'Yearly Report',
                  imageAsset: 'assets/icons/icon_year_rep.png',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ReportListPage(type: ReportListType.yearly)),
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.title, required this.imageAsset, required this.onTap});

  final String title;
  final String imageAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Image.asset(imageAsset, width: 28, height: 28),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
