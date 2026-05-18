import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import '../providers/app_providers.dart';

enum ReportChartType { weekly, monthly, yearly }

class ReportChartPage extends ConsumerStatefulWidget {
  const ReportChartPage.weekly({super.key, required this.reportId, required this.title})
      : type = ReportChartType.weekly,
        month = null,
        year = null;

  const ReportChartPage.monthly({super.key, required this.month, required this.year, required this.title})
      : type = ReportChartType.monthly,
        reportId = null;

  const ReportChartPage.yearly({super.key, required this.year, required this.title})
      : type = ReportChartType.yearly,
        reportId = null,
        month = null;

  final ReportChartType type;
  final int? reportId;
  final String? month;
  final int? year;
  final String title;

  @override
  ConsumerState<ReportChartPage> createState() => _ReportChartPageState();
}

class _ReportChartPageState extends ConsumerState<ReportChartPage> {
  bool _loading = true;
  String? _error;
  List<BarChartGroupData> _bars = <BarChartGroupData>[];
  List<String> _labels = <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);

      if (widget.type == ReportChartType.weekly) {
        final data = await api.getWeeklyChart(widget.reportId!);
        _labels = data.map((e) => e.day.toString()).toList();
        _bars = _toBars(data.map((e) => e.totalSugar).toList(), data.map((e) => e.sugarGrade).toList());
      } else if (widget.type == ReportChartType.monthly) {
        final data = await api.getMonthlyChart(month: widget.month!, year: widget.year!);
        _labels = data.map((e) => 'M${e.weekNumber}').toList();
        _bars = _toBars(data.map((e) => e.totalSugar).toList(), data.map((e) => e.sugarGrade).toList());
      } else {
        final data = await api.getYearlyChart(year: widget.year!);
        _labels = data.map((e) => e.month).toList();
        _bars = _toBars(data.map((e) => e.totalSugar).toList(), data.map((e) => e.sugarGrade).toList());
      }
    } catch (e) {
      _error = e.toString();
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  List<BarChartGroupData> _toBars(List<double> values, List<String> grades) {
    return List<BarChartGroupData>.generate(values.length, (index) {
      final grade = grades[index].toLowerCase();
      final color = switch (grade) {
        'merah' => const Color(0xFFFF3C3C),
        'kuning' => const Color(0xFFFFEB3B),
        'hijau' => const Color(0xFF77FF62),
        _ => const Color(0xFF27B48A),
      };

      return BarChartGroupData(
        x: index,
        barRods: [BarChartRodData(toY: values[index], color: color, width: 18, borderRadius: BorderRadius.circular(2))],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _bars.isEmpty
                    ? const Center(child: Text('Tidak ada report yang ditemukan'))
                    : BarChart(
                        BarChartData(
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: true),
                          titlesData: FlTitlesData(
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx < 0 || idx >= _labels.length) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(_labels[idx], style: const TextStyle(fontSize: 10)),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: _bars,
                        ),
                      ),
      ),
    );
  }
}
