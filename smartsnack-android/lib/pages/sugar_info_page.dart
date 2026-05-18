import 'package:flutter/material.dart';

class SugarInfoPage extends StatelessWidget {
  const SugarInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sugar Grade')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text(
            'Sugar Grade menggunakan Multiple Traffic Light (MTL). Batas konsumsi gula harian anak adalah 25 gram.',
            style: TextStyle(fontSize: 15),
          ),
          SizedBox(height: 16),
          _GradeTile(title: 'Hijau', subtitle: 'Rendah', rule: '< 2.5 gram gula per 100 mL / 100 g'),
          _GradeTile(title: 'Kuning', subtitle: 'Sedang', rule: '2.5 - 11.25 gram gula per 100 mL / 100 g'),
          _GradeTile(title: 'Merah', subtitle: 'Tinggi', rule: '> 11.25 gram gula per 100 mL / 100 g'),
        ],
      ),
    );
  }
}

class _GradeTile extends StatelessWidget {
  const _GradeTile({required this.title, required this.subtitle, required this.rule});

  final String title;
  final String subtitle;
  final String rule;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text('$title - $subtitle', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(rule),
      ),
    );
  }
}
