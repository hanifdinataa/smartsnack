import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import '../providers/app_providers.dart';

class HealthMonitoringPage extends ConsumerStatefulWidget {
  const HealthMonitoringPage({super.key});
  @override
  ConsumerState<HealthMonitoringPage> createState() => _HealthMonitoringPageState();
}

class _HealthMonitoringPageState extends ConsumerState<HealthMonitoringPage> {
  static const int _heartMeasureSeconds = 60;
  static const int _tempMeasureSeconds = 5;

  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  String _selectedGender = 'Male';

  int? _checkId;
  double? _heartRate;
  double? _bodyTemp;

  bool _loadingHeartRate = false;
  bool _loadingBodyTemp = false;
  bool _processing = false;
  int _heartRemainingSeconds = 0;
  int _tempRemainingSeconds = 0;
  Timer? _heartTimer;
  Timer? _tempTimer;

  HealthMonitoringRecord? _result;

  // ─── ALL LOGIC UNCHANGED ────────────────────────────────────────────────
  bool get _isHighRisk {
    final risk = _result?.riskDiabetes.toUpperCase().trim() ?? '';
    return risk == 'YES' || risk == 'YA' || risk == 'TINGGI' || risk == 'HIGH';
  }
  String get _riskLabel => _isHighRisk ? 'YES "Resiko Tinggi"' : 'NO "Resiko rendah"';
  String get _riskRecommendation {
    if (_isHighRisk) return 'Tubuh kamu perlu dijaga lebih baik ⚠️\nKurangi makan makanan manis, pilih makanan sehat, dan jangan lupa cek kesehatan ya!.';
    return 'Terus makan makanan sehat dan jangan kebanyakan gula \ntetap rajin bergerak ya!';
  }

  @override
  void dispose() { _heartTimer?.cancel(); _tempTimer?.cancel(); _ageController.dispose(); _heightController.dispose(); _weightController.dispose(); super.dispose(); }

  double? get _bmi {
    final heightCm = double.tryParse(_heightController.text.replaceAll(',', '.'));
    final weightKg = double.tryParse(_weightController.text.replaceAll(',', '.'));
    if (heightCm == null || weightKg == null || heightCm <= 0 || weightKg <= 0) return null;
    final meter = heightCm / 100;
    return weightKg / (meter * meter);
  }

  Future<void> _checkHeartRate() async {
    _heartTimer?.cancel(); setState(() => _loadingHeartRate = true); _startHeartCountdown();
    _snack('Letakkan jari Anda ke sensor. Sistem mulai menghitung detak jantung 60 detik.');
    try {
      final map = await ref.read(apiServiceProvider).checkHeartRate();
      final raw = map['data'];
      if (raw is! Map<String, dynamic>) throw Exception('Data detak jantung tidak valid.');
      final nextCheckId = int.tryParse(raw['check_id'].toString());
      final nextHeartRate = double.tryParse(raw['heart_rate'].toString());
      if (nextCheckId == null || nextHeartRate == null) throw Exception('Data detak jantung dari server tidak lengkap.');
      if (!mounted) return;
      setState(() { _checkId = nextCheckId; _heartRate = nextHeartRate; _bodyTemp = null; _result = null; });
      _snack('Detak jantung berhasil diambil. Lanjut cek suhu tubuh.');
    } catch (e) { if (!mounted) return; _snack(e.toString().replaceFirst('Exception: ', '')); }
    finally { _heartTimer?.cancel(); if (mounted) setState(() { _loadingHeartRate = false; _heartRemainingSeconds = 0; }); }
  }

  Future<void> _checkBodyTemperature() async {
    final checkId = _checkId;
    if (checkId == null) { _snack('Tekan Cek Detak Jantung dulu supaya sesi pengecekan dibuat.'); return; }
    _tempTimer?.cancel(); setState(() => _loadingBodyTemp = true); _startTempCountdown();
    _snack('Silakan arahkan dahi Anda ke sensor sampai suhu terbaca.');
    try {
      final map = await ref.read(apiServiceProvider).checkBodyTemperature(checkId: checkId);
      final raw = map['data'];
      if (raw is! Map<String, dynamic>) throw Exception('Data suhu tubuh tidak valid.');
      final nextBodyTemp = double.tryParse(raw['body_temp'].toString());
      if (nextBodyTemp == null) throw Exception('Data suhu tubuh dari server tidak lengkap.');
      if (!mounted) return;
      setState(() { _bodyTemp = nextBodyTemp; _result = null; });
      _snack('Suhu tubuh berhasil diambil.');
    } catch (e) { if (!mounted) return; _snack(e.toString().replaceFirst('Exception: ', '')); }
    finally { _tempTimer?.cancel(); if (mounted) setState(() { _loadingBodyTemp = false; _tempRemainingSeconds = 0; }); }
  }

  Future<void> _process() async {
    final checkId = _checkId; final heartRate = _heartRate; final bodyTemp = _bodyTemp;
    final age = int.tryParse(_ageController.text);
    final heightCm = double.tryParse(_heightController.text.replaceAll(',', '.'));
    final weightKg = double.tryParse(_weightController.text.replaceAll(',', '.'));
    final bmi = _bmi;
    if (checkId == null || heartRate == null) { _snack('Cek Detak Jantung dulu.'); return; }
    if (bodyTemp == null) { _snack('Cek Suhu Tubuh dulu.'); return; }
    if (age == null || age <= 0) { _snack('Umur wajib diisi dengan angka valid.'); return; }
    if (heightCm == null || heightCm <= 0) { _snack('Tinggi badan wajib diisi dengan angka valid.'); return; }
    if (weightKg == null || weightKg <= 0) { _snack('Berat badan wajib diisi dengan angka valid.'); return; }
    if (bmi == null) { _snack('BMI belum bisa dihitung.'); return; }
    setState(() => _processing = true);
    try {
      final result = await ref.read(apiServiceProvider).analyzeHealthMonitoring(checkId: checkId, age: age, gender: _selectedGender, heightCm: heightCm, weightKg: weightKg, bmi: bmi);
      final finalResult = HealthMonitoringRecord(checkId: result.checkId, heartRate: result.heartRate, bodyTemp: result.bodyTemp, age: result.age, gender: result.gender, heightCm: result.heightCm, weightKg: result.weightKg, bmi: result.bmi, riskDiabetes: result.riskDiabetes, algorithm: result.algorithm, riskPercent: result.riskPercent, checkedAtIso: result.checkedAtIso);
      await ref.read(localStorageProvider).saveHealthMonitoringRecord(finalResult);
      await ref.read(localStorageProvider).appendHealthMonitoringHistory(finalResult);
      if (!mounted) return;
      setState(() => _result = finalResult);
      ref.read(profileRefreshSignalProvider.notifier).state++;
      _snack('Monitoring kesehatan berhasil diproses.');
    } catch (e) { if (!mounted) return; _snack(e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => _processing = false); }
  }

  void _snack(String message) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }

  void _startHeartCountdown() {
    setState(() => _heartRemainingSeconds = _heartMeasureSeconds);
    _heartTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_heartRemainingSeconds <= 1) { timer.cancel(); setState(() => _heartRemainingSeconds = 0); return; }
      setState(() => _heartRemainingSeconds -= 1);
    });
  }

  void _startTempCountdown() {
    setState(() => _tempRemainingSeconds = _tempMeasureSeconds);
    _tempTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_tempRemainingSeconds <= 1) { timer.cancel(); setState(() => _tempRemainingSeconds = 0); return; }
      setState(() => _tempRemainingSeconds -= 1);
    });
  }

  // ─── BUILD (UI UPGRADED) ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bmi = _bmi;
    return Scaffold(
      appBar: AppBar(title: const Text('Monitoring Kesehatan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (_checkId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.tag_rounded, size: 16, color: Color(0xFF0D9F6E)),
                const SizedBox(width: 8),
                Text('Sesi Check ID: $_checkId', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF065F46))),
              ]),
            ),
          // Sensor section
          _sectionLabel('Sensor', Icons.sensors_rounded),
          const SizedBox(height: 12),
          _sensorCard(
            icon: Icons.favorite_rounded, iconColor: const Color(0xFFEF4444), iconBg: const Color(0xFFFEE2E2),
            title: 'Detak Jantung',
            value: _heartRate == null ? '-' : '${_heartRate!.toStringAsFixed(0)} bpm',
            buttonLabel: _loadingHeartRate ? 'Menghitung...' : 'Cek Detak Jantung',
            loading: _loadingHeartRate,
            onPressed: _loadingHeartRate ? null : _checkHeartRate,
            countdown: _loadingHeartRate ? (_heartRemainingSeconds > 0 ? 'Letakkan jari di sensor... ${_heartRemainingSeconds}s' : 'Memproses hasil...') : null,
            progress: _loadingHeartRate ? (_heartMeasureSeconds == 0 ? null : ((_heartMeasureSeconds - _heartRemainingSeconds) / _heartMeasureSeconds).clamp(0.0, 1.0)) : null,
          ),
          const SizedBox(height: 12),
          _sensorCard(
            icon: Icons.thermostat_rounded, iconColor: const Color(0xFFF59E0B), iconBg: const Color(0xFFFEF3C7),
            title: 'Suhu Tubuh',
            value: _bodyTemp == null ? '-' : '${_bodyTemp!.toStringAsFixed(1)} °C',
            buttonLabel: _loadingBodyTemp ? 'Membaca...' : 'Cek Suhu Tubuh',
            loading: _loadingBodyTemp,
            onPressed: _loadingBodyTemp ? null : _checkBodyTemperature,
            countdown: _loadingBodyTemp ? (_tempRemainingSeconds > 0 ? 'Arahkan dahi ke sensor... ${_tempRemainingSeconds}s' : 'Memproses hasil...') : null,
            progress: _loadingBodyTemp ? (_tempMeasureSeconds == 0 ? null : ((_tempMeasureSeconds - _tempRemainingSeconds) / _tempMeasureSeconds).clamp(0.0, 1.0)) : null,
          ),
          const SizedBox(height: 24),
          // Form section
          _sectionLabel('Data Pribadi', Icons.person_rounded),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF0F0F0)),
              boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 16, offset: Offset(0, 6))],
            ),
            child: Column(children: [
              TextField(controller: _ageController, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Umur', prefixIcon: Icon(Icons.cake_outlined, size: 20)), onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(value: _selectedGender,
                items: const [DropdownMenuItem(value: 'Male', child: Text('Laki-laki')), DropdownMenuItem(value: 'Female', child: Text('Perempuan'))],
                onChanged: (value) { if (value == null) return; setState(() => _selectedGender = value); },
                decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.wc_outlined, size: 20))),
              const SizedBox(height: 14),
              TextField(controller: _heightController, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(labelText: 'Tinggi badan (cm)', prefixIcon: Icon(Icons.height_rounded, size: 20)), onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              TextField(controller: _weightController, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(labelText: 'Berat badan (kg)', prefixIcon: Icon(Icons.monitor_weight_outlined, size: 20)), onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              _readOnlyField('BMI', bmi == null ? '-' : bmi.toStringAsFixed(2), Icons.speed_rounded),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _processing ? null : _process,
            icon: _processing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.analytics_rounded, size: 20),
            label: Text(_processing ? 'Memproses...' : 'Proses Prediksi Dini'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          )),
          // Result
          if (_result != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _isHighRisk ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5), width: 1.5),
                boxShadow: [BoxShadow(color: (_isHighRisk ? const Color(0xFFEF4444) : const Color(0xFF0D9F6E)).withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: Column(children: [
                const Text('ESTIMASI KONDISI', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280), fontWeight: FontWeight.w600, letterSpacing: 1)),
                const SizedBox(height: 4),
                const Text('Hasil Deteksi Dini', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Color(0xFF111827), letterSpacing: -0.3)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isHighRisk ? const Color(0xFFEF4444) : const Color(0xFF0D9F6E),
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [BoxShadow(color: (_isHighRisk ? const Color(0xFFEF4444) : const Color(0xFF0D9F6E)).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Text(_riskLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                const SizedBox(height: 16),
                Text(_riskRecommendation, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.5)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, IconData icon) {
    return Row(children: [
      Icon(icon, size: 20, color: const Color(0xFF0D9F6E)),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827), letterSpacing: -0.2)),
    ]);
  }

  Widget _sensorCard({
    required IconData icon, required Color iconColor, required Color iconBg,
    required String title, required String value, required String buttonLabel,
    required bool loading, required VoidCallback? onPressed, String? countdown, double? progress,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
          ])),
        ]),
        if (countdown != null) ...[const SizedBox(height: 10), Text(countdown, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))],
        if (progress != null) ...[const SizedBox(height: 8), ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 4))],
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onPressed,
          icon: Icon(icon, size: 18), label: Text(buttonLabel, style: const TextStyle(fontSize: 13)))),
      ]),
    );
  }

  Widget _readOnlyField(String label, String value, IconData icon) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20)),
      child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
    );
  }

  // ─── OLD _readOnly & _info widgets ───
  // Widget _readOnly(String label, String value) { return InputDecorator(...); }
  // Widget _info(String label, String value) { return Padding(...); }
}
