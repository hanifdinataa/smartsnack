import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import '../providers/app_providers.dart';
import '../widgets/product_card.dart';
import 'edit_profile_page.dart';
import 'product_result_page.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> with SingleTickerProviderStateMixin {
  List<ProductItem> _consumed = <ProductItem>[];
  List<ProductItem> _history = <ProductItem>[];
  HealthMonitoringRecord? _healthRecord;
  List<HealthMonitoringRecord> _healthHistory = <HealthMonitoringRecord>[];
  SnackBoxStatus? _snackBoxStatus;
  bool _loading = true;
  ProviderSubscription<int>? _profileRefreshSub;

  // ─── ALL LOGIC UNCHANGED ────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _profileRefreshSub = ref.listenManual<int>(profileRefreshSignalProvider, (previous, next) { if (!mounted) return; _load(); });
    _load();
  }

  @override
  void dispose() { _profileRefreshSub?.close(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await ref.read(sessionProvider.notifier).refreshUser();
      final api = ref.read(apiServiceProvider);
      final consumed = await api.getConsumedProducts();
      final history = await api.getSearchHistory();
      final snackBoxStatus = await api.getSnackBoxStatus();
      final healthHistory = await api.getHealthMonitoringHistory();
      if (mounted) { setState(() { _consumed = consumed; _history = history; _snackBoxStatus = snackBoxStatus; _healthHistory = healthHistory; _healthRecord = healthHistory.isEmpty ? null : healthHistory.first; _loading = false; }); }
    } catch (e) { if (mounted) { setState(() => _loading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); } }
  }

  Future<void> _deleteAllConsumedItems() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Hapus Semua Konsumsi'), content: const Text('Hapus semua produk/kemasan yang sudah dikonsumsi?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus Semua'))],
    )) ?? false;
    if (!ok) return;
    try {
      final deletedCount = await ref.read(apiServiceProvider).deleteAllConsumedProducts();
      if (!mounted) return; await _load(); if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$deletedCount data konsumsi berhasil dihapus.')));
    } catch (e) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
  }

  Future<void> _deleteConsumedItem(ProductItem item) async {
    final id = item.consumptionRecordId;
    if (id == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID konsumsi tidak ditemukan.'))); return; }
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Hapus Konsumsi'), content: Text('Hapus ${item.name} dari daftar konsumsi?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus'))],
    )) ?? false;
    if (!ok) return;
    try {
      await ref.read(apiServiceProvider).deleteConsumedProduct(consumptionRecordId: id);
      if (!mounted) return; await _load(); if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Konsumsi berhasil dihapus.')));
    } catch (e) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
  }

  // ─── BUILD (UI UPGRADED) ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = session.user;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF0D9F6E),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  SizedBox(height: MediaQuery.of(context).padding.top + 16),
                  // ─── OLD profile header ───
                  // Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: ...), ...);
                  // ─── NEW profile header ───
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF0D9F6E), Color(0xFF10B981)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [BoxShadow(color: Color(0x300D9F6E), blurRadius: 20, offset: Offset(0, 8))],
                    ),
                    child: Row(children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                        child: const Icon(Icons.person_rounded, size: 30, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(user?.name ?? '-', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white, letterSpacing: -0.3)),
                        const SizedBox(height: 4),
                        Text(user?.email ?? '-', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w500)),
                      ])),
                      Container(
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                        child: IconButton(
                          onPressed: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfilePage())).then((_) => _load()); },
                          icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  // Logout button
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: () => ref.read(sessionProvider.notifier).signOut(),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Logout'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  )),
                  const SizedBox(height: 16),
                  _buildHealthMonitoringCard(),
                  const SizedBox(height: 20),
                  // Tab bar
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(16)),
                    child: const TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'Poppins'),
                      unselectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Poppins'),
                      labelPadding: EdgeInsets.symmetric(horizontal: 16),
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(color: Color(0xFF0D9F6E), borderRadius: BorderRadius.all(Radius.circular(12))),
                      labelColor: Colors.white,
                      unselectedLabelColor: Color(0xFF6B7280),
                      tabs: [Tab(text: 'Konsumsi Saya'), Tab(text: 'Riwayat Produk'), Tab(text: 'Riwayat Kesehatan')],
                    ),
                  ),
                  SizedBox(
                    height: 480,
                    child: TabBarView(children: [
                      _ProductListView(items: _consumed, showDelete: true, onDelete: (item) => _deleteConsumedItem(item), onDeleteAll: _deleteAllConsumedItems),
                      _ProductListView(items: _history),
                      _HealthHistoryList(items: _healthHistory),
                    ]),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildHealthMonitoringCard() {
    final data = _healthRecord;
    final status = _snackBoxStatus;
    // ─── OLD card ───
    // return Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), ...));
    // ─── NEW card ───
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.favorite_rounded, size: 18, color: Color(0xFF0D9F6E))),
            const SizedBox(width: 10),
            const Text('Monitoring Kesehatan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF111827))),
          ]),
          const SizedBox(height: 16),
          _healthRow(Icons.favorite_rounded, 'Denyut Jantung', data == null ? '-' : '${data.heartRate.toStringAsFixed(0)} bpm'),
          _healthRow(Icons.thermostat_rounded, 'Suhu Tubuh', data == null ? '-' : '${data.bodyTemp.toStringAsFixed(1)} °C'),
          _healthRow(Icons.wc_rounded, 'Gender', data == null ? '-' : (data.gender == 'Female' ? 'Perempuan' : 'Laki-laki')),
          _healthRow(Icons.speed_rounded, 'BMI', data == null ? '-' : data.bmi.toStringAsFixed(2)),
          _healthRow(Icons.warning_amber_rounded, 'Risiko Diabetes', data?.riskDiabetes ?? '-'),
          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFFF3F4F6)),
          const SizedBox(height: 14),
          Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.inventory_2_rounded, size: 18, color: Color(0xFFD97706))),
            const SizedBox(width: 10),
            const Text('Smart Snack Box', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF111827))),
          ]),
          const SizedBox(height: 12),
          _healthRow(Icons.water_drop_rounded, 'Limit gula', status == null ? '-' : '${status.sugarLimit.toStringAsFixed(0)} g'),
          _healthRow(Icons.today_rounded, 'Konsumsi hari ini', status == null ? '-' : '${status.todaySugar.toStringAsFixed(2)} g'),
          _healthRow(Icons.hourglass_bottom_rounded, 'Sisa kuota', status == null ? '-' : '${status.remainingSugar.toStringAsFixed(2)} g'),
          _healthRow(Icons.lock_open_rounded, 'Servo', status == null ? '-' : (status.canOpenServo ? 'Bisa dibuka' : 'Terkunci')),
          if (status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(status.message, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), fontStyle: FontStyle.italic))),
        ]),
      ),
    );
  }

  Widget _healthRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 16, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 10),
        Text('$label: ', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827)), textAlign: TextAlign.right)),
      ]),
    );
  }
}

// ─── PRODUCT LIST VIEW (UI UPGRADED, LOGIC UNCHANGED) ─────────────────────
class _ProductListView extends StatelessWidget {
  const _ProductListView({required this.items, this.showDelete = false, this.onDelete, this.onDeleteAll});
  final List<ProductItem> items;
  final bool showDelete;
  final Future<void> Function(ProductItem item)? onDelete;
  final Future<void> Function()? onDeleteAll;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 56, height: 56, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.inbox_rounded, color: Color(0xFF9CA3AF), size: 28)),
        const SizedBox(height: 12),
        const Text('Belum ada data', style: TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500)),
      ]));
    }
    return Column(children: [
      if (showDelete && onDeleteAll != null)
        Align(alignment: Alignment.centerRight, child: TextButton.icon(
          onPressed: onDeleteAll,
          icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFEF4444), size: 18),
          label: const Text('Hapus Semua', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
        )),
      Expanded(child: ListView.builder(
        primary: false, physics: const ClampingScrollPhysics(), itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Column(children: [
            ProductCard(product: item, showSecondaryInfo: false,
              onTap: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductResultPage(productId: item.id))); }),
            if (showDelete && onDelete != null)
              Align(alignment: Alignment.centerRight, child: TextButton.icon(
                onPressed: () => onDelete!(item),
                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 16),
                label: const Text('Hapus', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
              )),
          ]);
        },
      )),
    ]);
  }
}

// ─── HEALTH HISTORY LIST (UI UPGRADED, LOGIC UNCHANGED) ───────────────────
class _HealthHistoryList extends StatelessWidget {
  const _HealthHistoryList({required this.items});
  final List<HealthMonitoringRecord> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 56, height: 56, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.history_rounded, color: Color(0xFF9CA3AF), size: 28)),
        const SizedBox(height: 12),
        const Text('Belum ada riwayat kesehatan', style: TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500)),
      ]));
    }
    return ListView.builder(itemCount: items.length, itemBuilder: (context, index) {
      final item = items[index];
      final dt = DateTime.tryParse(item.checkedAtIso);
      final dateText = dt == null ? item.checkedAtIso
        : '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      // ─── OLD Card ───
      // return Card(margin: const EdgeInsets.symmetric(vertical: 6), child: Padding(...));
      // ─── NEW Card ───
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF0F0F0)),
          boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(8)),
              child: Text(dateText, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF065F46))),
            ),
          ]),
          const SizedBox(height: 12),
          _row('Denyut Jantung', '${item.heartRate.toStringAsFixed(0)} bpm'),
          _row('Suhu Tubuh', '${item.bodyTemp.toStringAsFixed(1)} °C'),
          _row('Umur', '${item.age} tahun'),
          _row('Gender', item.gender == 'Female' ? 'Perempuan' : 'Laki-laki'),
          _row('Tinggi', '${item.heightCm.toStringAsFixed(1)} cm'),
          _row('Berat', '${item.weightKg.toStringAsFixed(1)} kg'),
          _row('BMI', item.bmi.toStringAsFixed(2)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (item.riskDiabetes.toUpperCase().trim() == 'YES' || item.riskDiabetes.toUpperCase().trim() == 'YA')
                ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text('Risiko: ${item.riskDiabetes}', style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 12,
              color: (item.riskDiabetes.toUpperCase().trim() == 'YES' || item.riskDiabetes.toUpperCase().trim() == 'YA')
                ? const Color(0xFFDC2626) : const Color(0xFF065F46),
            )),
          ),
        ]),
      );
    });
  }

  Widget _row(String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
      Text('$label: ', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827)), textAlign: TextAlign.right)),
    ]));
  }
}
